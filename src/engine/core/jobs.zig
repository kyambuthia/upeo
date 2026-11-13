//! Work-stealing job system for multi-core frame parallelism.
//!
//! Architecture & literature:
//! - Lock-free circular work-stealing deque: Chase & Lev, "Dynamic Circular
//!   Work-Stealing Deque", SPAA 2005, with C11/Zig atomic memory orderings from
//!   Lê, Pop, Cohen & Zappa Nardelli, "Correct and Efficient Work-Stealing for
//!   Weak Memory Models", PPoPP 2013.
//! - Random-victim stealing: Blumofe & Leiserson, "Scheduling Multithreaded
//!   Computations by Work Stealing", JACM 1999.
//! - Cooperative `wait` (helping workers execute jobs instead of blocking):
//!   Gyrling, "Parallelizing the Naughty Dog Engine Using Fibers", GDC 2015.
//!
//! Preallocates all job nodes and per-worker deques at `init`; submitting and
//! running jobs performs zero heap allocations. Degrades to inline execution
//! when `builtin.single_threaded` or `worker_count == 0` (e.g. WebAssembly
//! without pthreads).

const std = @import("std");
const builtin = @import("builtin");
const c = @import("../platform/c.zig").c;

const cache_line = std.atomic.cache_line;

/// Lock-free single-producer / multi-stealer bounded circular deque.
pub fn WorkStealingDeque(comptime T: type, comptime log2_cap: u5) type {
    const cap: usize = @as(usize, 1) << log2_cap;
    const mask: isize = @intCast(cap - 1);

    return struct {
        const Self = @This();

        pub const StealResult = union(enum) {
            item: T,
            empty,
            abort,
        };

        top: std.atomic.Value(isize) align(cache_line) = std.atomic.Value(isize).init(0),
        bottom: std.atomic.Value(isize) align(cache_line) = std.atomic.Value(isize).init(0),
        buffer: [cap]T align(cache_line) = undefined,

        /// Owner-only: pushes an item onto the bottom of the deque.
        pub fn push(self: *Self, item: T) error{QueueFull}!void {
            const b = self.bottom.load(.monotonic);
            const t = self.top.load(.acquire);
            if (b - t >= @as(isize, @intCast(cap))) return error.QueueFull;
            self.buffer[@intCast(b & mask)] = item;
            self.bottom.store(b + 1, .release);
        }

        /// Owner-only: pops an item from the bottom (LIFO for cache locality).
        pub fn pop(self: *Self) ?T {
            const b = self.bottom.load(.monotonic) - 1;
            self.bottom.store(b, .seq_cst);
            const t = self.top.load(.seq_cst);

            if (t <= b) {
                const item = self.buffer[@intCast(b & mask)];
                if (t == b) {
                    if (self.top.cmpxchgStrong(t, t + 1, .seq_cst, .monotonic) != null) {
                        self.bottom.store(b + 1, .monotonic);
                        return null;
                    }
                    self.bottom.store(b + 1, .monotonic);
                }
                return item;
            } else {
                self.bottom.store(b + 1, .monotonic);
                return null;
            }
        }

        /// Any thief thread: steals an item from the top (FIFO).
        pub fn steal(self: *Self) StealResult {
            const t = self.top.load(.seq_cst);
            const b = self.bottom.load(.seq_cst);
            if (t < b) {
                const item = self.buffer[@intCast(t & mask)];
                if (self.top.cmpxchgStrong(t, t + 1, .seq_cst, .monotonic) != null) {
                    return .abort;
                }
                return .{ .item = item };
            }
            return .empty;
        }
    };
}

/// A single cache-line-sized unit of work with inline payload storage.
pub const Job = struct {
    pub const PayloadBytes = 40;
    pub const Fn = *const fn (job: *Job) void;

    func: Fn,
    parent: ?*Job = null,
    unfinished_jobs: std.atomic.Value(i32) = std.atomic.Value(i32).init(1),
    _pad: u32 = 0,
    data: [PayloadBytes]u8 = undefined,

    pub fn setPayload(self: *Job, value: anytype) void {
        const T = @TypeOf(value);
        comptime std.debug.assert(@sizeOf(T) <= PayloadBytes);
        const bytes = std.mem.asBytes(&value);
        @memcpy(self.data[0..bytes.len], bytes);
    }

    pub fn getPayload(self: *const Job, comptime T: type) T {
        comptime std.debug.assert(@sizeOf(T) <= PayloadBytes);
        var out: T = undefined;
        @memcpy(std.mem.asBytes(&out), self.data[0..@sizeOf(T)]);
        return out;
    }
};

comptime {
    if (@sizeOf(Job) > cache_line) {
        @compileError("Job must fit inside a single cache line (64 bytes)");
    }
}

pub const JobSystem = struct {
    pub const MAX_JOBS_PER_FRAME = 4096;
    const Deque = WorkStealingDeque(*Job, 12); // 4096 entries

    const Worker = struct {
        deque: Deque = .{},
        thread: ?std.Thread = null,
        rng_state: u64 = 0x9e3779b97f4a7c15,

        fn nextRand(self: *Worker) u64 {
            // SplitMix64 step for fast thief victim selection
            self.rng_state +%= 0x9e3779b97f4a7c15;
            var z = self.rng_state;
            z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
            z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
            return z ^ (z >> 31);
        }
    };

    allocator: std.mem.Allocator,
    workers: []Worker,
    job_ring: []Job,
    next_job: std.atomic.Value(usize) align(cache_line) = std.atomic.Value(usize).init(0),
    running: std.atomic.Value(bool) align(cache_line) = std.atomic.Value(bool).init(true),
    wake_sem: ?*c.SDL_Semaphore = null,

    // Worker 0 is always the calling/main thread.
    threadlocal var tls_worker_index: usize = 0;

    pub fn init(allocator: std.mem.Allocator, requested_workers: ?usize) !*JobSystem {
        const self = try allocator.create(JobSystem);
        errdefer allocator.destroy(self);

        const bg_count: usize = if (builtin.single_threaded) 0 else blk: {
            if (requested_workers) |w| break :blk w;
            const cpus = std.Thread.getCpuCount() catch 2;
            break :blk if (cpus > 1) cpus - 1 else 0;
        };

        const total_workers = 1 + bg_count;
        const workers = try allocator.alloc(Worker, total_workers);
        errdefer allocator.free(workers);
        for (workers, 0..) |*w, i| {
            w.* = .{ .rng_state = 0x9e3779b97f4a7c15 ^ (@as(u64, i + 1) *% 0xbf58476d1ce4e5b9) };
        }

        const job_ring = try allocator.alloc(Job, MAX_JOBS_PER_FRAME);
        errdefer allocator.free(job_ring);

        const sem = if (bg_count > 0) c.SDL_CreateSemaphore(0) else null;

        self.* = .{
            .allocator = allocator,
            .workers = workers,
            .job_ring = job_ring,
            .wake_sem = sem,
        };

        for (1..total_workers) |idx| {
            workers[idx].thread = try std.Thread.spawn(.{}, workerLoop, .{ self, idx });
        }

        return self;
    }

    pub fn deinit(self: *JobSystem) void {
        self.running.store(false, .release);
        if (self.wake_sem) |sem| {
            for (1..self.workers.len) |_| {
                c.SDL_SignalSemaphore(sem);
            }
        }
        for (1..self.workers.len) |idx| {
            if (self.workers[idx].thread) |t| t.join();
        }
        if (self.wake_sem) |sem| {
            c.SDL_DestroySemaphore(sem);
        }
        self.allocator.free(self.job_ring);
        self.allocator.free(self.workers);
        self.allocator.destroy(self);
    }

    fn allocJob(self: *JobSystem) *Job {
        const slot = self.next_job.fetchAdd(1, .monotonic) % self.job_ring.len;
        return &self.job_ring[slot];
    }

    pub fn createJob(self: *JobSystem, func: Job.Fn, payload: anytype) *Job {
        const job = self.allocJob();
        job.* = .{
            .func = func,
            .parent = null,
            .unfinished_jobs = std.atomic.Value(i32).init(1),
        };
        if (@TypeOf(payload) != void) {
            job.setPayload(payload);
        }
        return job;
    }

    pub fn createChildJob(self: *JobSystem, parent: *Job, func: Job.Fn, payload: anytype) *Job {
        _ = parent.unfinished_jobs.fetchAdd(1, .monotonic);
        const job = self.allocJob();
        job.* = .{
            .func = func,
            .parent = parent,
            .unfinished_jobs = std.atomic.Value(i32).init(1),
        };
        if (@TypeOf(payload) != void) {
            job.setPayload(payload);
        }
        return job;
    }

    pub fn submit(self: *JobSystem, job: *Job) void {
        if (self.workers.len == 1) {
            executeJob(job);
            return;
        }
        const idx = tls_worker_index;
        self.workers[idx].deque.push(job) catch {
            // Queue full: execute inline to guarantee forward progress.
            executeJob(job);
            return;
        };
        if (self.wake_sem) |sem| {
            c.SDL_SignalSemaphore(sem);
        }
    }

    /// Blocks the calling thread until `job` (and all its children) finish,
    /// cooperatively executing available work in the meantime.
    pub fn wait(self: *JobSystem, job: *Job) void {
        while (job.unfinished_jobs.load(.acquire) > 0) {
            if (!self.tryRunOne(tls_worker_index)) {
                std.atomic.spinLoopHint();
            }
        }
    }

    /// Splits `slice` into batches of `batch_size` and runs `func(batch)` across workers.
    pub fn parallelFor(
        self: *JobSystem,
        comptime T: type,
        slice: []T,
        batch_size: usize,
        comptime func: fn ([]T) void,
    ) void {
        if (slice.len == 0) return;
        const step = @max(batch_size, 1);
        if (self.workers.len == 1 or slice.len <= step) {
            func(slice);
            return;
        }

        const Ctx = struct {
            ptr: [*]T,
            len: usize,

            fn run(j: *Job) void {
                const ctx = j.getPayload(@This());
                func(ctx.ptr[0..ctx.len]);
            }
        };

        const root = self.createJob(noopJob, {});
        var offset: usize = 0;
        while (offset < slice.len) {
            const end = @min(offset + step, slice.len);
            const child = self.createChildJob(root, Ctx.run, Ctx{
                .ptr = slice.ptr + offset,
                .len = end - offset,
            });
            self.submit(child);
            offset = end;
        }
        self.submit(root);
        self.wait(root);
    }

    fn noopJob(_: *Job) void {}

    fn executeJob(job: *Job) void {
        job.func(job);
        finishJob(job);
    }

    fn finishJob(job: *Job) void {
        const remaining = job.unfinished_jobs.fetchSub(1, .release) - 1;
        if (remaining == 0) {
            if (job.parent) |parent| {
                finishJob(parent);
            }
        }
    }

    fn tryRunOne(self: *JobSystem, worker_idx: usize) bool {
        if (self.workers[worker_idx].deque.pop()) |job| {
            executeJob(job);
            return true;
        }
        if (self.workers.len <= 1) return false;

        // Random victim stealing (Blumofe & Leiserson 1999)
        const start = @as(usize, @intCast(self.workers[worker_idx].nextRand() % self.workers.len));
        for (0..self.workers.len) |offset| {
            const victim = (start + offset) % self.workers.len;
            if (victim == worker_idx) continue;
            switch (self.workers[victim].deque.steal()) {
                .item => |job| {
                    executeJob(job);
                    return true;
                },
                .abort, .empty => {},
            }
        }
        return false;
    }

    fn workerLoop(self: *JobSystem, idx: usize) void {
        tls_worker_index = idx;
        var idle_spins: u32 = 0;

        while (self.running.load(.acquire)) {
            if (self.tryRunOne(idx)) {
                idle_spins = 0;
                continue;
            }
            idle_spins += 1;
            if (idle_spins < 64) {
                std.atomic.spinLoopHint();
            } else if (idle_spins < 128) {
                std.Thread.yield() catch {};
            } else if (self.wake_sem) |sem| {
                _ = c.SDL_WaitSemaphore(sem);
                idle_spins = 0;
            }
        }
    }
};

test "WorkStealingDeque single-threaded LIFO pop and FIFO steal" {
    var dq = WorkStealingDeque(usize, 4){};
    try dq.push(1);
    try dq.push(2);
    try dq.push(3);

    // Thief steals oldest (FIFO)
    switch (dq.steal()) {
        .item => |v| try std.testing.expectEqual(@as(usize, 1), v),
        else => return error.TestUnexpectedResult,
    }
    // Owner pops newest (LIFO)
    try std.testing.expectEqual(@as(?usize, 3), dq.pop());
    try std.testing.expectEqual(@as(?usize, 2), dq.pop());
    try std.testing.expectEqual(@as(?usize, null), dq.pop());
}

test "WorkStealingDeque multithreaded owner vs thieves consumes every item once" {
    const N: usize = 2000;
    const num_thieves = 3;

    var dq = WorkStealingDeque(usize, 12){};
    var seen: [N]std.atomic.Value(u32) = undefined;
    for (&seen) |*s| s.* = std.atomic.Value(u32).init(0);

    var done_pushing = std.atomic.Value(bool).init(false);

    const Thief = struct {
        fn run(q: *WorkStealingDeque(usize, 12), flags: *[N]std.atomic.Value(u32), done: *std.atomic.Value(bool)) void {
            while (true) {
                switch (q.steal()) {
                    .item => |idx| _ = flags[idx].fetchAdd(1, .monotonic),
                    .abort => {},
                    .empty => {
                        if (done.load(.acquire)) break;
                        std.Thread.yield() catch {};
                    },
                }
            }
        }
    };

    var threads: [num_thieves]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, Thief.run, .{ &dq, &seen, &done_pushing });
    }

    for (0..N) |i| {
        try dq.push(i);
        if (i % 7 == 0) {
            if (dq.pop()) |idx| {
                _ = seen[idx].fetchAdd(1, .monotonic);
            }
        }
    }
    while (dq.pop()) |idx| {
        _ = seen[idx].fetchAdd(1, .monotonic);
    }
    done_pushing.store(true, .release);

    for (threads) |t| t.join();

    for (seen) |s| {
        try std.testing.expectEqual(@as(u32, 1), s.load(.monotonic));
    }
}

test "JobSystem parallelFor and nested parent/child jobs" {
    const js = try JobSystem.init(std.testing.allocator, 2);
    defer js.deinit();

    var data: [1024]u64 = undefined;
    var expected: u64 = 0;
    for (&data, 0..) |*v, i| {
        v.* = @intCast(i + 1);
        expected += v.*;
    }

    const Double = struct {
        fn run(slice: []u64) void {
            for (slice) |*v| v.* *= 2;
        }
    };

    js.parallelFor(u64, &data, 64, Double.run);

    var actual: u64 = 0;
    for (data) |v| actual += v;
    try std.testing.expectEqual(expected * 2, actual);
}

test "JobSystem single-threaded fallback (0 workers)" {
    const js = try JobSystem.init(std.testing.allocator, 0);
    defer js.deinit();

    var counter: usize = 0;
    const Inc = struct {
        fn run(j: *Job) void {
            const p = j.getPayload(*usize);
            p.* += 1;
        }
    };

    const j = js.createJob(Inc.run, &counter);
    js.submit(j);
    js.wait(j);
    try std.testing.expectEqual(@as(usize, 1), counter);
}
