const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const String = @import("string").String;
const net = std.net;

pub fn start_server(ip: []const u8, port: i32, handle_func: anytype) i32 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const address = try net.Address.parseIp(ip, port);
    var listener = try address.listen(.{
        .reuse_address = true,
        .kernel_backlog = 1024,
    });

    defer listener.deinit();

    std.log.info("listening at {any}\n", .{address});

    var clients = std.AutoHashMap(*Client, void).init(allocator);

    while (true) {
        if (listener.accept()) |conn| {
            const client = try gpa.create(Client);
            errdefer client.deinit();

            client.* = Client.init(conn.stream);
            clients.put(client, {});
            const thread = try std.Thread.spawn(.{}, handle_func, .{client});
            thread.detach();
        } else |err| {
            std.log.err("failed to accept connection {}", .{err});
        }
    }
}

pub fn parseRequest(req: []const *u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var myString = String.init_with_contents(gpa.allocator(), req);
    defer myString.deinit();

    // Use functions provided
    try myString.concat("🔥 Hello!");
    _ = myString.pop();
    try myString.concat(", World 🔥");

    assert(myString.cmp("🔥 Hello, World 🔥"));
}

const Client = struct {
    req: *Request,
    stream: net.Stream,

    pub fn init(stream: net.Stream) Client {
        return .{
            .stream = stream,
        };
    }

    fn run(self: *Client) !void {
        defer self.arena.deinit();
        try self.room.add(self);
        defer {
            self.room.remove(self);
            self.stream.close();
        }

        const stream = self.stream;
        _ = try stream.write("server: welcome to the chat server\n");
        while (true) {
            var buf: [100]u8 = undefined;
            const n = try stream.read(&buf);
            if (n == 0) {
                return;
            }
            self.room.broadcast(buf[0..n], self);
        }
    }
};

const Request = struct {
    lock: std.Thread.RwLock,
    clients: std.AutoHashMap(*Client, void),

    pub fn add(self: *Request, client: *Client) !void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.clients.put(client, {});
    }

    pub fn remove(self: *Request, client: *Client) void {
        self.lock.lock();
        defer self.lock.unlock();
        _ = self.clients.remove(client);
    }

    fn broadcast(self: *Request, msg: []const u8, sender: *Client) void {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        var it = self.clients.keyIterator();
        while (it.next()) |key_ptr| {
            const client = key_ptr.*;
            if (client == sender) continue;
            _ = client.stream.write(msg) catch |e| std.log.warn("unable to send: {}\n", .{e});
        }
    }
};
