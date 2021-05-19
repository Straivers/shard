module shard.math;

T round_to_next(T)(T value, T base) nothrow {
    const rem = value % base;
    assert(value + (base - rem) > value, "Overflow error on rounding.");
    return rem ? value + (base - rem) : value;
}
