module shard.math;

import std.traits: isIntegral;

/**
 Returns the integer log for `i`. Rounds up towards infinity.
 */
@safe T ilog2(T)(T i) nothrow if (isIntegral!T) {
    import core.bitop : bsr;

    return i == 0 ? 1 : bsr(i) + !is_power_of_two(i);
}

@safe T round_to_next(T)(T value, T base) nothrow {
    const rem = value % base;
    assert(value + (base - rem) > value, "Overflow error on rounding.");
    return rem ? value + (base - rem) : value;
}

pragma(inline, true) @safe bool is_power_of_two(size_t n) nothrow {
    return (n != 0) & ((n & (n - 1)) == 0);
}

@("is_power_of_two(size_t)")
unittest {
    assert(is_power_of_two(1));
    assert(is_power_of_two(1 << 20));
    assert(!is_power_of_two(0));
}
