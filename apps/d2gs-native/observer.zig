const std = @import("std");
const builtin = @import("builtin");
const player_skills = @import("player_skills.zig");

// Qualified ONLY against the exact i386 Mac 1.14d image documented in native-observer.md.
pub const image_sha256 = "1e8dd6dd3d19019cbaa29270f4abfb04960fcf1ce5d341fa520863b0d640d177";
pub const Observation = struct {
    game_id: u32, actor: u32, class: u32, mode: u32, frame: u32, hp_q8: i32,
    // Native getter values indexed by the engine stat id 0..15, layer zero.
    // A record exists only if all values were read twice under this game lock.
    stats: [16]i32,
    skills: ?player_skills.Slice,
    pub fn alive(self: Observation) bool { return self.hp_q8 > 0 and self.mode != 0 and self.mode != 17; }
};

// Called only while realm.tickGames holds this actual native game's engine lock.
// The selected GUID is an explicit filter, not an ownership/name/census assertion.
pub fn capture(access: anytype, game_id: u32, game: u32, guid: u32) ?Observation {
    if (game_id == 0 or game == 0 or guid == 0) return null;
    const frame = access.read(game + 0xa8) orelse return null;
    const unit = access.find(game, guid);
    if (unit == 0 or (access.read(unit) orelse return null) != 0) return null;
    const class = access.read(unit + 4) orelse return null;
    const actor = access.read(unit + 0xc) orelse return null;
    const mode = access.read(unit + 0x10) orelse return null;
    if (class > 6 or actor != guid or mode > 20) return null;
    const stats = access.read(unit + 0x5c) orelse return null;
    if (stats == 0) return null;
    var values: [16]i32 = undefined;
    for (&values, 0..) |*value, id| {
        value.* = access.stat(unit, @intCast(id), 0) orelse return null;
    }
    // Point pools with actual zero values remain known zero. A failed/missing
    // getter invalidates this slice; absent wire deltas are never a zero source.
    for (values, 0..) |value, id| {
        if ((access.stat(unit, @intCast(id), 0) orelse return null) != value) return null;
    }
    const skills = if (class == 1) player_skills.capture(access, unit) else null;
    const hp = values[6];
    if (hp < 0) return null;
    if (access.find(game, guid) != unit or
        (access.read(unit) orelse return null) != 0 or
        (access.read(unit + 4) orelse return null) != class or
        (access.read(unit + 0xc) orelse return null) != actor or
        (access.read(unit + 0x10) orelse return null) != mode or
        (access.read(unit + 0x5c) orelse return null) != stats or
        (access.read(game + 0xa8) orelse return null) != frame) return null;
    return .{ .game_id = game_id, .actor = actor, .class = class, .mode = mode, .frame = frame, .hp_q8 = hp, .stats = values, .skills = skills };
}

pub fn qualified(bytes: []const u8) bool {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var expected: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&expected, image_sha256) catch return false;
    return std.mem.eql(u8, &digest, &expected);
}

const Find = *const fn (u32, u32, u32) callconv(.c) u32;
const Skill = *const fn (u32, u32, u32) callconv(.c) u32;
const Level = *const fn (u32, u32, i32) callconv(.c) i32;
var skiller: ?Skill = null;
var leveller: ?Level = null;
const Stat = *const fn (u32, i32, u16) callconv(.c) i32;
var finder: ?Find = null;
var statter: ?Stat = null;
var selected_guid: u32 = 0;
var remaining: u32 = 0;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;

pub fn configure(bytes: []const u8, image: anytype) void {
    finder = null;
    statter = null;
    skiller = null;
    leveller = null;
    remaining = 0;
    const requested = getenv("D2GS_OBSERVE_PLAYER_GUID") orelse return;
    if (builtin.cpu.arch != .x86 or builtin.os.tag != .linux or !qualified(bytes)) {
        std.debug.print("native-observer: refused unqualified image/ABI\n", .{});
        return;
    }
    selected_guid = std.fmt.parseInt(u32, std.mem.span(requested), 10) catch return;
    if (selected_guid == 0) return;
    finder = @ptrFromInt(image.at(0x0027905c));
    statter = @ptrFromInt(image.at(0x001949e8));
    skiller = @ptrFromInt(image.at(0x0018693f));
    leveller = @ptrFromInt(image.at(0x0018608e));
    remaining = 64; // bounded diagnostic producer; no input or protocol claims.
}

const Native = struct {
    pub fn read(_: *Native, at: u32) ?u32 {
        if (at == 0) return null;
        const value: *align(1) volatile const u32 = @ptrFromInt(at);
        return value.*;
    }
    pub fn find(_: *Native, game: u32, guid: u32) u32 { return finder.?(game, 0, guid); }
    pub fn skill(_: *Native, unit: u32, id: u32, owner: u32) u32 { return skiller.?(unit, id, owner); }
    pub fn level(_: *Native, unit: u32, skill_ptr: u32, effective: bool) i32 { return leveller.?(unit, skill_ptr, @intFromBool(effective)); }
    pub fn stat(_: *Native, unit: u32, id: i32, layer: u16) ?i32 { return statter.?(unit, id, layer); }
};

pub fn observe(game_id: u32, game: u32) void {
    if (remaining == 0 or finder == null or statter == null) return;
    remaining -= 1;
    var native = Native{};
    if (capture(&native, game_id, game, selected_guid)) |o| {
        std.debug.print("native-observer: {{\"game_id\":{d},\"actor\":{d},\"class\":{d},\"mode\":{d},\"native_frame\":{d},\"hp_q8\":{d},\"stats_layer0\":[{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}]}}\n", .{ o.game_id, o.actor, o.class, o.mode, o.frame, o.hp_q8, o.stats[0], o.stats[1], o.stats[2], o.stats[3], o.stats[4], o.stats[5], o.stats[6], o.stats[7], o.stats[8], o.stats[9], o.stats[10], o.stats[11], o.stats[12], o.stats[13], o.stats[14], o.stats[15] });
        if (o.skills) |skills| {
            std.debug.print("native-skills: {{\"game_id\":{d},\"actor\":{d},\"native_frame\":{d},\"hard_ranks_36_65\":[", .{ o.game_id, o.actor, o.frame });
            for (skills.hard, 0..) |rank, i| std.debug.print("{s}{d}", .{ if (i == 0) @as([]const u8, "") else ",", rank });
            std.debug.print("],\"effective_ranks_36_65\":[", .{});
            for (skills.effective, 0..) |rank, i| std.debug.print("{s}{d}", .{ if (i == 0) @as([]const u8, "") else ",", rank });
            std.debug.print("],\"hands\":[", .{});
            for (skills.hands, 0..) |hand, i| std.debug.print("{s}{{\"known\":{},\"id\":{d},\"owner\":{d}}}", .{ if (i == 0) @as([]const u8, "") else ",", hand.known, hand.id, hand.owner });
            std.debug.print("]}}\n", .{});
        }
    } else {
        std.debug.print("native-observer: {{\"game_id\":{d},\"requested_guid\":{d},\"observation\":null}}\n", .{ game_id, selected_guid });
    }
}
