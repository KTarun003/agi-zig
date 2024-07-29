const std = @import("std");
const agi = @import("lib.zig");
const Client = agi.Client;
pub fn main() anyerror!void {
    agi.start_server("127.0.0.1", 4573, handle_call);
}

fn handle_call() !void {}
