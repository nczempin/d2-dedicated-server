const std = @import("std");
// Bounded read-only capture of ONE actor's complete current inventory chain.
// Not a global loaded-item census, property snapshot or action permission.
pub const Item = struct {
    pointer: u32, guid: u32, class: u32, mode: u32, body: u8, page: u8,
    quality: u32, flags: u32, data: u32, previous: u32, next: u32, parent: u32,
};
pub const Slice = struct {
    inventory: u32, owner: u32, cursor: u32,
    count: u32, items: [128]Item,
};
fn itemAt(access: anytype, at: u32) ?Item {
    if (at == 0 or (access.read(at) orelse return null) != 4) return null;
    const data = access.read(at + 0x14) orelse return null;
    if (data == 0) return null;
    const bp = access.read(data + 0x44) orelse return null;
    const row = Item{
        .pointer = at, .guid = access.read(at + 0xc) orelse return null,
        .class = access.read(at + 4) orelse return null,
        .mode = access.read(at + 0x10) orelse return null,
        .data = data, .body = @truncate(bp), .page = @truncate(bp >> 8),
        .quality = access.read(data) orelse return null,
        .flags = access.read(data + 0x18) orelse return null,
        .parent = access.read(data + 0x5c) orelse return null,
        .previous = access.read(data + 0x60) orelse return null,
        .next = access.read(data + 0x64) orelse return null,
    };
    if (row.guid == 0 or row.mode > 6 or row.quality < 1 or row.quality > 9) return null;
    return row;
}
pub fn capture(access: anytype, actor: u32, guid: u32) ?Slice {
    const inv = access.read(actor + 0x60) orelse return null;
    if (inv == 0 or (access.read(inv) orelse return null) != 0x01020304 or
        (access.read(inv + 8) orelse return null) != actor or
        (access.read(inv + 0x24) orelse return null) != guid or guid == 0) return null;
    const count = access.read(inv + 0x28) orelse return null;
    if (count > 128) return null;
    const first = access.read(inv + 0xc) orelse return null;
    const last = access.read(inv + 0x10) orelse return null;
    const cursor = access.read(inv + 0x20) orelse return null;
    // Cursor custody is deliberately not inferred from ordinary chain ownership.
    // Keep such inventories unavailable until its separate native semantics exist.
    if (cursor != 0) return null;
    var out = Slice{ .inventory = inv, .owner = guid, .cursor = cursor, .count = count, .items = undefined };
    var at = first;
    var previous: u32 = 0;
    for (0..count) |i| {
        const row = itemAt(access, at) orelse return null;
        if (row.parent != inv or row.previous != previous) return null;
        for (out.items[0..i]) |seen| if (seen.pointer == row.pointer or seen.guid == row.guid) return null;
        out.items[i] = row;
        previous = at;
        at = row.next;
    }
    if (at != 0 or previous != last) return null; // No truncation, including zero-count contradictions.
    for (out.items[0..count]) |before| {
        const after = itemAt(access, before.pointer) orelse return null;
        if (!std.meta.eql(before, after)) return null;
    }
    if ((access.read(actor + 0x60) orelse return null) != inv or
        (access.read(inv) orelse return null) != 0x01020304 or
        (access.read(inv + 8) orelse return null) != actor or
        (access.read(inv + 0x24) orelse return null) != guid or
        (access.read(inv + 0x28) orelse return null) != count or
        (access.read(inv + 0xc) orelse return null) != first or
        (access.read(inv + 0x10) orelse return null) != last or
        (access.read(inv + 0x20) orelse return null) != cursor) return null;
    return out;
}
const Fake = struct {
    owner: u32 = 1, count: u32 = 2, cursor: u32 = 0,
    cycle: bool = false, foreign: bool = false, missing: bool = false,
    reads: u32 = 0, changing: bool = false,
    pub fn read(self: *Fake, at: u32) ?u32 {
        if (self.missing) return null;
        if (at == 0x30028) {
            self.reads += 1;
            if (self.changing and self.reads > 1) return 1;
        }
        return switch (at) {
            0x20060 => 0x30000, 0x30000 => 0x01020304, 0x30008 => 0x20000,
            0x30024 => self.owner, 0x30028 => self.count, 0x30020 => self.cursor,
            0x3000c => 0x40000, 0x30010 => 0x41000,
            0x40000, 0x41000 => 4, 0x40004 => 67, 0x41004 => 87,
            0x4000c => 2, 0x4100c => 3, 0x40010 => 1, 0x41010 => 2,
            0x40014 => 0x50000, 0x41014 => 0x51000,
            0x50000, 0x51000 => 2, 0x50018, 0x51018 => 0x10,
            0x50044 => 4, 0x51044 => 0,
            0x5005c => 0x30000, 0x5105c => if (self.foreign) 0x99000 else 0x30000,
            0x50060 => 0, 0x51060 => 0x40000,
            0x50064 => 0x41000, 0x51064 => if (self.cycle) 0x40000 else 0,
            else => null,
        };
    }
};
test "complete owned chain retains exact equipped staff and belt item" {
    var memory = Fake{};
    const result = capture(&memory, 0x20000, 1).?;
    try std.testing.expectEqual(@as(u32, 2), result.count);
    try std.testing.expectEqual(@as(u8, 4), result.items[0].body);
    try std.testing.expectEqual(@as(u32, 1), result.items[0].mode);
    try std.testing.expectEqual(@as(u32, 2), result.items[1].mode);
}
test "foreign partial cyclic truncated changing and cursor inventories refuse completeness" {
    var memory = Fake{ .owner = 2 };try std.testing.expect(capture(&memory, 0x20000, 1) == null);
    memory = .{ .foreign = true };try std.testing.expect(capture(&memory, 0x20000, 1) == null);
    memory = .{ .missing = true };try std.testing.expect(capture(&memory, 0x20000, 1) == null);
    memory = .{ .cycle = true };try std.testing.expect(capture(&memory, 0x20000, 1) == null);
    memory = .{ .count = 1 };try std.testing.expect(capture(&memory, 0x20000, 1) == null);
    memory = .{ .count = 0 };try std.testing.expect(capture(&memory, 0x20000, 1) == null);
    memory = .{ .count = 129 };try std.testing.expect(capture(&memory, 0x20000, 1) == null);
    memory = .{ .changing = true };try std.testing.expect(capture(&memory, 0x20000, 1) == null);
    memory = .{ .cursor = 0x40000 };try std.testing.expect(capture(&memory, 0x20000, 1) == null);
}
