module shard.memory.values;

import std.algorithm: max;

/// The alignment guaranteed to accomodate any D object on the target platform.
/// Sourced from
/// https://github.com/dlang/phobos/blob/master/std/experimental/allocator/common.d
enum platform_alignment = max(double.alignof, real.alignof);

// dfmt off
size_t kib(size_t n) nothrow { return n * 1024; }
size_t mib(size_t n) nothrow { return n * (1024 ^^ 2); }
size_t gib(size_t n) nothrow { return n * (1024 ^^ 3); }
// dfmt on
