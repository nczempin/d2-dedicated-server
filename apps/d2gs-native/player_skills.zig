const std = @import("std");
// Mac 1.14d exact-image bindings are qualified in docs/native-player-stats.md.
// Mirrors the existing NativeCurrentHands capture: active pointer, text/id,
// owner and native lookup must all agree before any hand is known.
pub const Hand = struct { known: bool = false, id: u16 = 0xffff, owner: u32 = 0 };
pub const Slice = struct { hard: [30]u16, effective: [30]u16, hands: [2]Hand };
pub fn capture(access: anytype, unit: u32) ?Slice {
    const list = access.read(unit + 0xa8) orelse return null;
    if (list == 0) return null;
    var result: Slice = undefined;
    for (0..30) |i| {
        const id: u32 = @intCast(36 + i);
        const skill = access.skill(unit, id, 0xffffffff);
        if (skill == 0) {
            result.hard[i] = 0;
            result.effective[i] = 0;
            continue;
        }
        const text = access.read(skill) orelse return null;
        const owner = access.read(skill + 0x34) orelse return null;
        if (text == 0 or owner != 0xffffffff or
            ((access.read(text) orelse return null) & 0xffff) != id) return null;
        const hard = access.level(unit, skill, false);
        const effective = access.level(unit, skill, true);
        if (hard < 0 or hard > 65535 or effective < 0 or effective > 65535 or
            access.skill(unit, id, owner) != skill or
            access.level(unit, skill, false) != hard or
            access.level(unit, skill, true) != effective) return null;
        result.hard[i] = @intCast(hard);
        result.effective[i] = @intCast(effective);
    }
    for (&result.hands, 0..) |*hand, i| {
        hand.* = .{};
        const selected = access.read(list + 8 + @as(u32, @intCast(i)) * 4) orelse continue;
        if (selected == 0) continue;
        const text = access.read(selected) orelse continue;
        if (text == 0) continue;
        const id: u16 = @truncate(access.read(text) orelse continue);
        const owner = access.read(selected + 0x34) orelse continue;
        if (id > 356 or access.skill(unit, id, owner) != selected or
            (access.read(list + 8 + @as(u32, @intCast(i)) * 4) orelse continue) != selected or
            (access.read(selected) orelse continue) != text or
            (access.read(selected + 0x34) orelse continue) != owner or
            @as(u16, @truncate(access.read(text) orelse continue)) != id) continue;
        hand.* = .{ .known = true, .id = id, .owner = owner };
    }
    if ((access.read(unit + 0xa8) orelse return null) != list) return null;
    return result;
}
const Fake = struct {
    bonus: i32 = 1, hard: i32 = 0, foreign: bool = false, no_list: bool = false,
    changing: bool = false, calls: u32 = 0, foreign_hand: bool = false,
    pub fn read(self: *Fake, at: u32) ?u32 {
        return switch (at) {
            0x200a8 => if (self.no_list) 0 else 0x30000,
            0x30008 => 0x40000, 0x3000c => 0x41000,
            0x40000 => 0x50000, 0x41000 => 0x51000,
            0x40034 => if (self.foreign_hand) 99 else 0xffffffff,
            0x41034 => if (self.foreign) 99 else 0xffffffff,
            0x50000 => 0, 0x51000 => 36,
            else => null,
        };
    }
    pub fn skill(_: *Fake, unit: u32, id: u32, owner: u32) u32 {
        if (unit != 0x20000 or owner != 0xffffffff) return 0;
        return switch (id) { 0 => 0x40000, 36 => 0x41000, else => 0 };
    }
    pub fn level(self: *Fake, _: u32, _: u32, effective: bool) i32 {
        self.calls += 1;
        return self.hard + (if (effective) self.bonus else @as(i32, 0)) + (if (self.changing) @as(i32, @intCast(self.calls)) else 0);
    }
};
test "staff bonus is distinct from zero hard rank and actual selected hands" {
    var memory = Fake{};
    const result = capture(&memory, 0x20000).?;
    try std.testing.expectEqual(@as(u16, 0), result.hard[0]);
    try std.testing.expectEqual(@as(u16, 1), result.effective[0]);
    try std.testing.expectEqual(@as(u16, 0), result.hard[12]);
    try std.testing.expect(result.hands[0].known and result.hands[1].known);
    try std.testing.expectEqual(@as(u16, 0), result.hands[0].id);
    try std.testing.expectEqual(@as(u16, 36), result.hands[1].id);
}
test "missing list foreign owner and changing rank never become complete skills" {
    var memory = Fake{ .no_list = true };
    try std.testing.expect(capture(&memory, 0x20000) == null);
    memory = .{ .foreign = true };
    try std.testing.expect(capture(&memory, 0x20000) == null);
    memory = .{ .changing = true };
    try std.testing.expect(capture(&memory, 0x20000) == null);
}

test "a selected hand with a mismatched native owner stays unknown" {
    var memory = Fake{ .foreign_hand = true };
    const result = capture(&memory, 0x20000).?;
    try std.testing.expect(!result.hands[0].known);
    try std.testing.expect(result.hands[1].known);
}
