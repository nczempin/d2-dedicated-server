const std = @import("std");
const observer = @import("observer.zig");

const Fake = struct {
    hp: i32 = 10240,
    missing_stat: ?i32 = null,
    changing_stat: ?i32 = null,
    frame: u32 = 17,
    guid: u32 = 7,
    cls: u32 = 1,
    mode: u32 = 1,
    missing: bool = false,
    mutate: bool = false,
    stats: usize = 0,
    stats_pointer: u32 = 0x30000,
    pub fn find(_: *Fake, game: u32, guid: u32) u32 { return if (game == 0x10000 and guid == 7) 0x20000 else 0; }
    pub fn read(self: *Fake, at: u32) ?u32 {
        if (self.missing) return null;
        return switch (at) {
            0x100a8 => self.frame,
            0x20000 => 0,
            0x20004 => self.cls,
            0x2000c => self.guid,
            0x20010 => self.mode,
            0x2005c => self.stats_pointer,
            0x200a8 => 0,
            else => null,
        };
    }
    pub fn skill(_: *Fake, _: u32, _: u32, _: u32) u32 { return 0; }
    pub fn level(_: *Fake, _: u32, _: u32, _: bool) i32 { return 0; }
    pub fn stat(self: *Fake, unit: u32, id: i32, layer: u16) ?i32 {
        if (unit != 0x20000 or id < 0 or id > 15 or layer != 0 or self.missing_stat == id) return null;
        self.stats += 1;
        if (self.mutate) self.frame += 1;
        if (self.changing_stat == id) return @intCast(self.stats);
        return switch (id) {
            0 => 10, 1 => 35, 2 => 25, 3 => 10, 4, 5 => 0,
            6 => self.hp, 7 => 10240, 8, 9 => 8960, 10, 11 => 18944,
            12 => 1, 13, 14, 15 => 0, else => unreachable,
        };
    }
};

test "actual observer publishes checked identity native frame and raw HP" {
    var memory = Fake{};
    const result = observer.capture(&memory, 3, 0x10000, 7).?;
    try std.testing.expectEqual(@as(u32, 7), result.actor);
    try std.testing.expectEqual(@as(u32, 17), result.frame);
    try std.testing.expectEqual(@as(i32, 10240), result.hp_q8);
    try std.testing.expect(result.alive());
    try std.testing.expectEqual(@as(usize, 32), memory.stats);
}

test "foreign incomplete and changing native observations never become records" {
    var memory = Fake{ .guid = 8 };
    try std.testing.expect(observer.capture(&memory, 3, 0x10000, 7) == null);
    memory = .{ .missing = true };
    try std.testing.expect(observer.capture(&memory, 3, 0x10000, 7) == null);
    memory = .{ .mutate = true };
    try std.testing.expect(observer.capture(&memory, 3, 0x10000, 7) == null);
    memory = .{ .stats_pointer = 0 };
    try std.testing.expect(observer.capture(&memory, 3, 0x10000, 7) == null);
    memory = .{ .cls = 7 };
    try std.testing.expect(observer.capture(&memory, 3, 0x10000, 7) == null);
    memory = .{};
    try std.testing.expect(observer.capture(&memory, 0, 0x10000, 7) == null);
    try std.testing.expect(observer.capture(&memory, 3, 0, 7) == null);
}

test "observed death is not fabricated positive life or gameplay permission" {
    var memory = Fake{ .mode = 17, .hp = 0 };
    const result = observer.capture(&memory, 3, 0x10000, 7).?;
    try std.testing.expect(!result.alive());
    try std.testing.expectEqual(@as(i32, 0), result.hp_q8);
}

test "wrong image never qualifies for native bindings" {
    try std.testing.expect(!observer.qualified(""));
    var bytes = [_]u8{0} ** 64;
    try std.testing.expect(!observer.qualified(&bytes));
}

test "native zero point pools are observations while absent points stay unknown" {
    var memory = Fake{};
    const result = observer.capture(&memory, 3, 0x10000, 7).?;
    try std.testing.expectEqual(@as(i32, 0), result.stats[4]);
    try std.testing.expectEqual(@as(i32, 0), result.stats[5]);
    try std.testing.expectEqual(@as(i32, 8960), result.stats[8]);
    try std.testing.expectEqual(@as(i32, 8960), result.stats[9]);
    try std.testing.expectEqual(@as(i32, 1), result.stats[12]);
    memory = .{ .missing_stat = 4 };
    try std.testing.expect(observer.capture(&memory, 3, 0x10000, 7) == null);
    memory = .{ .missing_stat = 8 };
    try std.testing.expect(observer.capture(&memory, 3, 0x10000, 7) == null);
}
test "changing mana or point pool cannot be published under a stable fake frame" {
    var memory = Fake{ .changing_stat = 8 };
    try std.testing.expect(observer.capture(&memory, 3, 0x10000, 7) == null);
    memory = .{ .changing_stat = 4 };
    try std.testing.expect(observer.capture(&memory, 3, 0x10000, 7) == null);
}
