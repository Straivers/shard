module shard.memory.measures;

// dfmt off
size_t kib(size_t n) nothrow { return n * 1024; }
size_t mib(size_t n) nothrow { return n * (1024 ^^ 2); }
size_t gib(size_t n) nothrow { return n * (1024 ^^ 3); }
// dfmt on

template object_size(T) {
    import std.traits : Fields, isNested;

    // From https://github.com/dlang/phobos/blob/master/std/experimental/allocator/common.d stateSize(T)
    static if (is(T == class) || is(T == interface))
        enum object_size = __traits(classInstanceSize, T);
    else static if (is(T == struct) || is(T == union))
        enum object_size = Fields!T.length || isNested!T ? T.sizeof : 0;
    else static if (is(T == void))
        enum size_t object_size = 0;
    else
        enum object_size = T.sizeof;
}

template object_alignment(T) {
    import std.traits : classInstanceAlignment;

    static if (is(T == class))
        enum object_alignment = classInstanceAlignment!T;
    else static if (is(T == interface))
        static assert(0, "Unable to determine object alignment from an interface.");
    else
        enum object_alignment = T.alignof;
}

size_t bits_to_store(size_t value) nothrow {
    import core.bitop : bsr;

    return value == 0 ? 0 : bsr(value) + 1;
}

unittest {
    assert(bits_to_store(0) == 0);
    assert(bits_to_store(1) == 1);
    assert(bits_to_store(2) == 2);
    assert(bits_to_store(3) == 2);
    assert(bits_to_store(64) == 7);
    assert(bits_to_store(128 - 1) == 7);
    assert(bits_to_store(128) == 8);
}
