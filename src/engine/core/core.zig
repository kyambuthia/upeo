//! Core engine systems: timing, memory allocators, generational handles, and
//! work-stealing job parallelism.

pub const time = @import("time.zig");
pub const memory = @import("memory.zig");
pub const handle = @import("handle.zig");
pub const jobs = @import("jobs.zig");

test {
    _ = time;
    _ = memory;
    _ = handle;
    _ = jobs;
}
