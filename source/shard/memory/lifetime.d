module shard.memory.lifetime;

import core.checkedint : mulu;
import core.lifetime : emplace;
import shard.traits : object_size, PtrType;
import std.algorithm : max;
import std.traits : fullyQualifiedName, hasElaborateDestructor, hasMember;

PtrType!T make(T, A, Args...)(auto ref A storage, Args args) nothrow {
    // max(object_size!T, 1) to support 0-size types (void, especially)
    void[] m = storage.allocate(max(object_size!T, 1), fullyQualifiedName!T);
    if (!m.ptr) return null;

    static if (is(T == class)) {
        return emplace!T(m, args);
    }
    else {
        auto p = (() @trusted => cast(T*) m.ptr)();
        emplace!T(p, args);
        return p;
    }
}

T[] make_array(T, A)(auto ref A storage, size_t length) nothrow {
    auto t_array = make_raw_array!T(storage, length);

    static if (!is(T == void))
        t_array[] = T.init;

    return t_array;
}

T[] make_raw_array(T, A)(auto ref A storage, size_t length) nothrow {
    if (!length)
        return null;

    bool overflow;
    const _ = mulu(T.sizeof, length, overflow);
    if (overflow)
        assert(0, "Array size overflow!");

    void[] m;
    if (!storage.reallocate(m, T.sizeof, length, fullyQualifiedName!T))
        return null;

    return (() @trusted => cast(T[]) m)();
}

void dispose(T, A)(auto ref A storage, auto ref T* p) nothrow {
    static if (hasElaborateDestructor!T)
        destroy(*p);

    storage.deallocate((cast(void*) p)[0 .. T.sizeof], fullyQualifiedName!T);

    static if (__traits(isRef, p))
        p = null;
}

void dispose(T, A)(auto ref A storage, auto ref T p) nothrow
if (is(T == class) || is(T == interface)) {
    
    static if (is(T == interface))
        auto ob = cast(Object) p;
    else
        alias ob = p;

    auto support = (cast(void*) ob)[0 .. typeid(ob).initializer.length];

    destroy(p);
    storage.deallocate(support, fullyQualifiedName!T);

    static if (__traits(isRef, p))
        p = null;
}

void dispose(T, A)(auto ref A storage, auto ref T[] p) nothrow {
    static if (hasElaborateDestructor!(typeof(p[0])))
        foreach (ref e; p)
            destroy(e);

    storage.deallocate(cast(void[]) p, fullyQualifiedName!T);

    static if (__traits(isRef, p))
        p = null;
}

/**
Resizes an array to `new_length` elements, calling `ctor` on newly
allocated objects, and `dtor` on objects to be deallocated.

If `new_length > 0` and `array == null`, a new array will be allocated, and the
slice assigned to `array`. Similarly, if `new_length == 0` and `array != null`,
the array will be freed, and `array` will become `null`.

Params:
    allocator   = The allocator that the array was allocated from.
    array       = The array to be resized. May be `null`.
    length      = The length of the array after resizing. May be `0`.
*/
bool resize_array(T, A)(auto ref A storage, ref T[] array, size_t length) nothrow {
    static assert(!hasMember!(T, "opPostMove"), "Move construction on array reallocation not supported!");

    bool do_resize() {
        void[] array_ = array;
        if (!storage.reallocate(array_, T.sizeof, length, fullyQualifiedName!T))
            return false;

        array = cast(T[]) array_;
        return true;
    }

    if (length == array.length)
        return true;

    if (length < array.length) {
        static if (hasElaborateDestructor!T)
            foreach (ref object; array[length .. $])
                destroy(object);

        return do_resize();
    }
    else {
        const old_length = array.length;

        if (!do_resize())
            return false;

        static if (is(typeof(array[] = T.init)))
            array[old_length .. $] = T.init;
        else
            foreach (ref e; array[old_length .. $])
                e = T.init;

        return true;
    }
}
