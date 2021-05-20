module shard.math;

/**
 Returns the integer log for `i`. Rounds up towards infinity.
 */
T ilog2(T)(T i) nothrow if (isIntegral!T) {
    import core.bitop : bsr;

    return i == 0 ? 1 : bsr(i) + !is_power_of_two(i);
}

T round_to_next(T)(T value, T base) nothrow {
    const rem = value % base;
    assert(value + (base - rem) > value, "Overflow error on rounding.");
    return rem ? value + (base - rem) : value;
}