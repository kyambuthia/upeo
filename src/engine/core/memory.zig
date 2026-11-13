//! Predictable, zero-fragmentation memory allocators for the frame loop.
//!
//! References:
//! - Berger, Zorn & McKinley, "Reconsidering Custom Memory Allocation", OOPSLA 2002
//!   (demonstrates region/arena allocators match or outperform general-purpose
//!   allocators while supporting O(1) bulk deallocation).
//! - Gregory, "Game Engine Architecture", 3rd ed., Ch. 6 (stack, double-buffered,
//!   and fixed-size pool allocators).

const std = @import("std");

/// Linear bump allocator backed by a caller-owned or heap-allocated slice.
/// Individual `free` calls are no-ops; call `reset()` at the frame boundary.
pub const FrameArena = struct {
    buf: []u8,
    offset: usize = 0,
    high_water_mark: usize = 0,

    pub fn init(buffer: []u8) FrameArena {
        return .{ .buf = buffer };
    }

    pub fn initOwned(backing: std.mem.Allocator, cap: usize) !FrameArena {
        return .{ .buf = try backing.alloc(u8, cap) };
    }

    pub fn deinitOwned(self: *FrameArena, backing: std.mem.Allocator) void {
        backing.free(self.buf);
        self.* = undefined;
    }

    pub fn allocator(self: *FrameArena) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub fn reset(self: *FrameArena) void {
        self.offset = 0;
    }

    pub fn bytesUsed(self: FrameArena) usize {
        return self.offset;
    }

    pub fn capacity(self: FrameArena) usize {
        return self.buf.len;
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = allocFn,
        .resize = resizeFn,
        .remap = remapFn,
        .free = freeFn,
    };

    fn allocFn(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *FrameArena = @ptrCast(@alignCast(ctx));
        const align_bytes = alignment.toByteUnits();
        const base_addr = @intFromPtr(self.buf.ptr);
        const aligned_addr = std.mem.alignForward(usize, base_addr + self.offset, align_bytes);
        const start = aligned_addr - base_addr;
        const end = std.math.add(usize, start, len) catch return null;
        if (end > self.buf.len) return null;

        self.offset = end;
        if (end > self.high_water_mark) self.high_water_mark = end;
        return self.buf.ptr + start;
    }

    fn resizeFn(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
        return new_len <= memory.len;
    }

    fn remapFn(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) ?[*]u8 {
        return if (new_len <= memory.len) memory.ptr else null;
    }

    fn freeFn(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize) void {}
};

/// Ping-pong pair of `FrameArena`s so allocations made on frame N remain valid
/// during frame N+1 (e.g. render command lists or async job payloads).
pub const DoubleFrameArena = struct {
    arenas: [2]FrameArena,
    active: u1 = 0,

    pub fn init(buf_a: []u8, buf_b: []u8) DoubleFrameArena {
        return .{ .arenas = .{ FrameArena.init(buf_a), FrameArena.init(buf_b) } };
    }

    pub fn swapAndReset(self: *DoubleFrameArena) void {
        self.active ^= 1;
        self.arenas[self.active].reset();
    }

    pub fn allocator(self: *DoubleFrameArena) std.mem.Allocator {
        return self.arenas[self.active].allocator();
    }
};

/// Fixed-capacity O(1) free-list pool for homogeneous objects of type `T`.
pub fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();

        const Slot = union {
            item: T,
            next_free: ?u32,
        };

        slots: []Slot,
        free_head: ?u32,
        active_count: usize = 0,

        pub fn init(backing: std.mem.Allocator, cap: usize) !Self {
            const slots = try backing.alloc(Slot, cap);
            for (slots, 0..) |*s, i| {
                s.* = .{ .next_free = if (i + 1 < cap) @intCast(i + 1) else null };
            }
            return .{
                .slots = slots,
                .free_head = if (cap > 0) 0 else null,
            };
        }

        pub fn deinit(self: *Self, backing: std.mem.Allocator) void {
            backing.free(self.slots);
            self.* = undefined;
        }

        pub fn alloc(self: *Self) ?*T {
            const idx = self.free_head orelse return null;
            self.free_head = self.slots[idx].next_free;
            self.active_count += 1;
            self.slots[idx] = .{ .item = undefined };
            return &self.slots[idx].item;
        }

        pub fn free(self: *Self, ptr: *T) void {
            const base = @intFromPtr(self.slots.ptr);
            const addr = @intFromPtr(ptr);
            const idx: u32 = @intCast((addr - base) / @sizeOf(Slot));
            std.debug.assert(idx < self.slots.len);
            self.slots[idx] = .{ .next_free = self.free_head };
            self.free_head = idx;
            self.active_count -= 1;
        }
    };
}

/// Debug wrapper that counts (and optionally panics on) allocations while locked.
/// Enforces the "zero heap allocations inside the frame loop" invariant.
pub const GuardAllocator = struct {
    backing: std.mem.Allocator,
    locked: bool = false,
    panic_on_violation: bool = true,
    violations: usize = 0,

    pub fn init(backing: std.mem.Allocator) GuardAllocator {
        return .{ .backing = backing };
    }

    pub fn lock(self: *GuardAllocator) void {
        self.locked = true;
    }

    pub fn unlock(self: *GuardAllocator) void {
        self.locked = false;
    }

    pub fn allocator(self: *GuardAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = allocFn,
        .resize = resizeFn,
        .remap = remapFn,
        .free = freeFn,
    };

    fn check(self: *GuardAllocator) void {
        if (self.locked) {
            self.violations += 1;
            if (self.panic_on_violation) {
                @panic("heap allocation attempted while GuardAllocator is locked");
            }
        }
    }

    fn allocFn(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *GuardAllocator = @ptrCast(@alignCast(ctx));
        self.check();
        return self.backing.rawAlloc(len, alignment, ret_addr);
    }

    fn resizeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *GuardAllocator = @ptrCast(@alignCast(ctx));
        self.check();
        return self.backing.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remapFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *GuardAllocator = @ptrCast(@alignCast(ctx));
        self.check();
        return self.backing.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn freeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *GuardAllocator = @ptrCast(@alignCast(ctx));
        self.backing.rawFree(memory, alignment, ret_addr);
    }
};

test "FrameArena alignment, high-water mark, and reset" {
    var buf: [256]u8 = undefined;
    var arena = FrameArena.init(&buf);
    const a = arena.allocator();

    const p1 = try a.alloc(u8, 3);
    try std.testing.expectEqual(@as(usize, 3), p1.len);

    const p2 = try a.alloc(u64, 4);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(p2.ptr) % @alignOf(u64));

    const peak = arena.high_water_mark;
    try std.testing.expect(peak >= 3 + 32);

    arena.reset();
    try std.testing.expectEqual(@as(usize, 0), arena.bytesUsed());
    try std.testing.expectEqual(peak, arena.high_water_mark);
}

test "Pool alloc, exhaustion, free, and reuse" {
    var pool = try Pool(u64).init(std.testing.allocator, 2);
    defer pool.deinit(std.testing.allocator);

    const a = pool.alloc().?;
    a.* = 42;
    const b = pool.alloc().?;
    b.* = 99;
    try std.testing.expect(pool.alloc() == null);
    try std.testing.expectEqual(@as(usize, 2), pool.active_count);

    pool.free(a);
    try std.testing.expectEqual(@as(usize, 1), pool.active_count);
    const c = pool.alloc().?;
    try std.testing.expectEqual(a, c);
}

test "GuardAllocator detects locked allocations" {
    var guard = GuardAllocator.init(std.testing.allocator);
    guard.panic_on_violation = false;
    const a = guard.allocator();

    const ok = try a.alloc(u8, 8);
    a.free(ok);
    try std.testing.expectEqual(@as(usize, 0), guard.violations);

    guard.lock();
    const bad = try a.alloc(u8, 8);
    a.free(bad);
    guard.unlock();
    try std.testing.expectEqual(@as(usize, 1), guard.violations);
}
