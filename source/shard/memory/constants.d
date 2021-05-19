module shard.memory.constants;

import std.algorithm: max;

/// The alignment guaranteed to accomodate any D object on the target platform.
/// Sourced from
/// https://github.com/dlang/phobos/blob/master/std/experimental/allocator/common.d
enum platform_alignment = max(double.alignof, real.alignof);
