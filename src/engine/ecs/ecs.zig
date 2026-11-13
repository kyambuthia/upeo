//! Cache-friendly Sparse-Set Entity-Component-System (ECS).
//!
//! Architecture & literature:
//! - Caini, "EnTT: Sparse Sets and EnTT Architecture" (2019) & Mertens,
//!   "Building an ECS: Sparse Sets" (Flecs) — separates dense packed component
//!   arrays from a sparse entity-index indirection table for O(1) add/remove/lookup
//!   and contiguous, SIMD/prefetch-friendly linear iteration.

const std = @import("std");
const handle = @import("../core/handle.zig");

pub const EntityTag = struct {};
pub const Entity = handle.Handle(EntityTag);

/// Fixed-capacity generational entity allocator.
pub const EntityRegistry = struct {
    const Slot = struct {
        gen: u32 = 1,
        next_free: u32 = 0,
        alive: bool = false,
    };

    slots: []Slot,
    free_head: u32 = 0,
    free_count: usize,
    alive_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, max_entities: usize) !EntityRegistry {
        const slots = try allocator.alloc(Slot, max_entities);
        for (slots, 0..) |*s, i| {
            s.* = .{
                .gen = 1,
                .next_free = if (i + 1 < max_entities) @intCast(i + 1) else std.math.maxInt(u32),
                .alive = false,
            };
        }
        return .{
            .slots = slots,
            .free_head = if (max_entities > 0) 0 else std.math.maxInt(u32),
            .free_count = max_entities,
        };
    }

    pub fn deinit(self: *EntityRegistry, allocator: std.mem.Allocator) void {
        allocator.free(self.slots);
        self.* = undefined;
    }

    pub fn spawn(self: *EntityRegistry) ?Entity {
        if (self.free_count == 0) return null;
        const idx = self.free_head;
        const slot = &self.slots[idx];
        self.free_head = slot.next_free;
        self.free_count -= 1;
        self.alive_count += 1;
        slot.alive = true;
        return .{ .index = idx, .gen = slot.gen };
    }

    pub fn isAlive(self: EntityRegistry, e: Entity) bool {
        if (e.index >= self.slots.len or e.gen == 0) return false;
        const s = self.slots[e.index];
        return s.alive and s.gen == e.gen;
    }

    pub fn despawn(self: *EntityRegistry, e: Entity) bool {
        if (!self.isAlive(e)) return false;
        const slot = &self.slots[e.index];
        const next_gen = slot.gen +% 1;
        slot.gen = if (next_gen == 0) 1 else next_gen;
        slot.alive = false;
        slot.next_free = self.free_head;
        self.free_head = e.index;
        self.free_count += 1;
        self.alive_count -= 1;
        return true;
    }
};

/// Sparse-set storage for a single component type `T`.
/// Guarantees contiguous `dense` iteration and O(1) insert, lookup, and swap-remove.
pub fn ComponentPool(comptime T: type) type {
    return struct {
        const Self = @This();
        const EMPTY: u32 = std.math.maxInt(u32);

        sparse: []u32,
        dense: []T,
        dense_entities: []Entity,
        len: usize = 0,

        pub fn init(allocator: std.mem.Allocator, max_entities: usize) !Self {
            const sparse = try allocator.alloc(u32, max_entities);
            errdefer allocator.free(sparse);
            const dense = try allocator.alloc(T, max_entities);
            errdefer allocator.free(dense);
            const dense_entities = try allocator.alloc(Entity, max_entities);

            @memset(sparse, EMPTY);
            return .{
                .sparse = sparse,
                .dense = dense,
                .dense_entities = dense_entities,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.dense_entities);
            allocator.free(self.dense);
            allocator.free(self.sparse);
            self.* = undefined;
        }

        pub fn set(self: *Self, e: Entity, value: T) void {
            std.debug.assert(e.index < self.sparse.len);
            const existing = self.sparse[e.index];
            if (existing != EMPTY and self.dense_entities[existing].gen == e.gen) {
                self.dense[existing] = value;
                return;
            }
            const d_idx: u32 = @intCast(self.len);
            self.sparse[e.index] = d_idx;
            self.dense[d_idx] = value;
            self.dense_entities[d_idx] = e;
            self.len += 1;
        }

        pub fn has(self: Self, e: Entity) bool {
            if (e.index >= self.sparse.len) return false;
            const d_idx = self.sparse[e.index];
            return d_idx != EMPTY and self.dense_entities[d_idx].gen == e.gen;
        }

        pub fn getPtr(self: *Self, e: Entity) ?*T {
            if (!self.has(e)) return null;
            return &self.dense[self.sparse[e.index]];
        }

        pub fn get(self: Self, e: Entity) ?T {
            if (!self.has(e)) return null;
            return self.dense[self.sparse[e.index]];
        }

        pub fn remove(self: *Self, e: Entity) bool {
            if (!self.has(e)) return false;
            const d_idx = self.sparse[e.index];
            const last_d: u32 = @intCast(self.len - 1);
            if (d_idx != last_d) {
                const moved_e = self.dense_entities[last_d];
                self.dense[d_idx] = self.dense[last_d];
                self.dense_entities[d_idx] = moved_e;
                self.sparse[moved_e.index] = d_idx;
            }
            self.sparse[e.index] = EMPTY;
            self.len -= 1;
            return true;
        }

        pub fn slice(self: *Self) []T {
            return self.dense[0..self.len];
        }

        pub fn entities(self: *const Self) []const Entity {
            return self.dense_entities[0..self.len];
        }
    };
}

/// Joins two component pools, iterating over the smaller dense array for cache
/// efficiency and invoking `func(entity, *A, *B)`.
pub fn join2(
    comptime A: type,
    comptime B: type,
    pool_a: *ComponentPool(A),
    pool_b: *ComponentPool(B),
    ctx: anytype,
    comptime func: fn (@TypeOf(ctx), Entity, *A, *B) void,
) void {
    if (pool_a.len <= pool_b.len) {
        for (pool_a.entities(), pool_a.slice()) |e, *a| {
            if (pool_b.getPtr(e)) |b| {
                func(ctx, e, a, b);
            }
        }
    } else {
        for (pool_b.entities(), pool_b.slice()) |e, *b| {
            if (pool_a.getPtr(e)) |a| {
                func(ctx, e, a, b);
            }
        }
    }
}

test "EntityRegistry and ComponentPool sparse-set join2" {
    const Pos = struct { x: f32 };
    const Vel = struct { vx: f32 };

    var reg = try EntityRegistry.init(std.testing.allocator, 8);
    defer reg.deinit(std.testing.allocator);

    var pos = try ComponentPool(Pos).init(std.testing.allocator, 8);
    defer pos.deinit(std.testing.allocator);

    var vel = try ComponentPool(Vel).init(std.testing.allocator, 8);
    defer vel.deinit(std.testing.allocator);

    const e1 = reg.spawn().?;
    const e2 = reg.spawn().?;
    const e3 = reg.spawn().?;

    pos.set(e1, .{ .x = 1.0 });
    vel.set(e1, .{ .vx = 10.0 });

    pos.set(e2, .{ .x = 2.0 }); // no velocity

    pos.set(e3, .{ .x = 3.0 });
    vel.set(e3, .{ .vx = 30.0 });

    // Remove e1's velocity and despawn e1 -> stale e1 must not match
    _ = vel.remove(e1);
    _ = reg.despawn(e1);
    try std.testing.expect(!reg.isAlive(e1));

    const Step = struct {
        count: usize = 0,
        fn run(self: *@This(), _: Entity, p: *Pos, v: *Vel) void {
            p.x += v.vx;
            self.count += 1;
        }
    };
    var step = Step{};
    join2(Pos, Vel, &pos, &vel, &step, Step.run);

    try std.testing.expectEqual(@as(usize, 1), step.count);
    try std.testing.expectApproxEqAbs(@as(f32, 33.0), pos.get(e3).?.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), pos.get(e2).?.x, 1e-5);
}
