//! Generational handles and cache-friendly dense `SlotMap` storage.
//!
//! Separates stable external handles `(index, generation)` from a packed dense
//! array of live values so systems can iterate contiguously while detecting
//! stale handles in O(1) time.

const std = @import("std");

/// Type-safe generational handle parameterized by a tag type.
pub fn Handle(comptime Tag: type) type {
    return packed struct(u64) {
        pub const _tag = Tag;
        pub const invalid: @This() = .{ .index = std.math.maxInt(u32), .gen = 0 };

        index: u32,
        gen: u32,

        pub fn isValid(self: @This()) bool {
            return self.gen != 0 and self.index != std.math.maxInt(u32);
        }
    };
}

/// Fixed-capacity generational slot map with dense value iteration.
pub fn SlotMap(comptime T: type, comptime Tag: type) type {
    return struct {
        const Self = @This();
        pub const Key = Handle(Tag);

        const SparseSlot = struct {
            dense_idx: u32 = 0,
            gen: u32 = 1,
            next_free: u32 = 0,
            alive: bool = false,
        };

        sparse: []SparseSlot,
        dense: []T,
        dense_to_sparse: []u32,
        len: usize = 0,
        free_head: u32 = 0,
        free_count: usize,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            const sparse = try allocator.alloc(SparseSlot, capacity);
            errdefer allocator.free(sparse);
            const dense = try allocator.alloc(T, capacity);
            errdefer allocator.free(dense);
            const d2s = try allocator.alloc(u32, capacity);

            for (sparse, 0..) |*s, i| {
                s.* = .{
                    .gen = 1,
                    .next_free = if (i + 1 < capacity) @intCast(i + 1) else std.math.maxInt(u32),
                    .alive = false,
                };
            }

            return .{
                .sparse = sparse,
                .dense = dense,
                .dense_to_sparse = d2s,
                .free_head = if (capacity > 0) 0 else std.math.maxInt(u32),
                .free_count = capacity,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.dense_to_sparse);
            allocator.free(self.dense);
            allocator.free(self.sparse);
            self.* = undefined;
        }

        pub fn insert(self: *Self, value: T) ?Key {
            if (self.free_count == 0) return null;
            const s_idx = self.free_head;
            const slot = &self.sparse[s_idx];
            self.free_head = slot.next_free;
            self.free_count -= 1;

            const d_idx: u32 = @intCast(self.len);
            self.dense[d_idx] = value;
            self.dense_to_sparse[d_idx] = s_idx;
            self.len += 1;

            slot.dense_idx = d_idx;
            slot.alive = true;

            return .{ .index = s_idx, .gen = slot.gen };
        }

        pub fn contains(self: Self, key: Key) bool {
            if (key.index >= self.sparse.len or key.gen == 0) return false;
            const slot = self.sparse[key.index];
            return slot.alive and slot.gen == key.gen;
        }

        pub fn getPtr(self: *Self, key: Key) ?*T {
            if (!self.contains(key)) return null;
            return &self.dense[self.sparse[key.index].dense_idx];
        }

        pub fn get(self: Self, key: Key) ?T {
            if (!self.contains(key)) return null;
            return self.dense[self.sparse[key.index].dense_idx];
        }

        pub fn remove(self: *Self, key: Key) bool {
            if (!self.contains(key)) return false;
            const s_idx = key.index;
            const d_idx = self.sparse[s_idx].dense_idx;
            const last_d: u32 = @intCast(self.len - 1);

            if (d_idx != last_d) {
                const moved_s = self.dense_to_sparse[last_d];
                self.dense[d_idx] = self.dense[last_d];
                self.dense_to_sparse[d_idx] = moved_s;
                self.sparse[moved_s].dense_idx = d_idx;
            }
            self.len -= 1;

            // Bump generation (skipping 0, the invalid sentinel)
            const next_gen = self.sparse[s_idx].gen +% 1;
            self.sparse[s_idx].gen = if (next_gen == 0) 1 else next_gen;
            self.sparse[s_idx].alive = false;
            self.sparse[s_idx].next_free = self.free_head;
            self.free_head = s_idx;
            self.free_count += 1;
            return true;
        }

        /// Contiguous slice of all live values for cache-friendly iteration.
        pub fn slice(self: *Self) []T {
            return self.dense[0..self.len];
        }
    };
}

test "SlotMap insert, stale handle rejection, and dense swap-remove" {
    const Tag = struct {};
    var map = try SlotMap(u32, Tag).init(std.testing.allocator, 4);
    defer map.deinit(std.testing.allocator);

    const k1 = map.insert(10).?;
    const k2 = map.insert(20).?;
    const k3 = map.insert(30).?;

    try std.testing.expectEqual(@as(?u32, 20), map.get(k2));
    try std.testing.expect(map.remove(k2));
    try std.testing.expect(!map.contains(k2));
    try std.testing.expectEqual(@as(?u32, null), map.get(k2));

    // Reusing the freed slot produces a new generation; old k2 stays invalid.
    const k4 = map.insert(40).?;
    try std.testing.expectEqual(k2.index, k4.index);
    try std.testing.expect(k4.gen != k2.gen);
    try std.testing.expectEqual(@as(?u32, null), map.get(k2));
    try std.testing.expectEqual(@as(?u32, 40), map.get(k4));
    try std.testing.expectEqual(@as(?u32, 10), map.get(k1));
    try std.testing.expectEqual(@as(?u32, 30), map.get(k3));
    try std.testing.expectEqual(@as(usize, 3), map.slice().len);
}
