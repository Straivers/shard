module shard.traits;

template PtrType(T) {
    static if (is(T == class))
        alias PtrType = T;
    else
        alias PtrType = T*;
}

PtrType!T get_ptr_type(T)(ref T object) {
    static if (is(T == class) || is(T == interface))
        return object;
    else
        return &object;
}

PtrType!T to_ptr_type(T)(void* ptr) {
    static if (is(T == class) || is(T == interface))
        return cast(T) ptr;
    else
        return cast(T*) ptr;
}

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
