module shard.memory.lifetime;

import core.checkedint : mulu;
import core.lifetime : emplace;
import std.algorithm : max, min;
import std.traits : fullyQualifiedName, hasElaborateDestructor, hasMember;

import shard.traits : PtrType, object_size;

PtrType!T make(T, A, Args...)(auto ref A storage, Args args) nothrow {
    // Support 0-size structs
    void[] m = storage.allocate(max(object_size!T, 1));
    if (!m.ptr) return null;

    // g_mem_tracker.record_allocate(storage, fullyQualifiedName!T, m);

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
    import core.stdc.string : memcpy, memset;

    if (!length)
        return null;

    bool overflow;
    const size = mulu(T.sizeof, length, overflow);

    if (overflow)
        return null;

    auto m = storage.allocate(size);
    if (!m.ptr)
        return null;

    // g_mem_tracker.record_allocate(storage, fullyQualifiedName!T, m);

    auto t_array = (() @trusted => cast(T[]) m)();
    t_array[] = T.init;
    return t_array;
}

void dispose(T, A)(auto ref A storage, auto ref T* p) nothrow {
    static if (hasElaborateDestructor!T)
        destroy(*p);

    // void[] memory = (cast(void*) p)[0 .. T.sizeof];
    // g_mem_tracker.record_deallocate(storage, fullyQualifiedName!T, memory);

    storage.deallocate((cast(void*) p)[0 .. T.sizeof]);

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

    // g_mem_tracker.record_deallocate(storage, fullyQualifiedName!T, support);

    destroy(p);
    storage.deallocate(support);

    static if (__traits(isRef, p))
        p = null;

    storage.deallocate(support, file, line);
}

void dispose(T, A)(auto ref A storage, auto ref T[] p) nothrow {
    static if (hasElaborateDestructor!(typeof(p[0])))
        foreach (ref e; p)
            destroy(e);
    
    // g_mem_tracker.record_deallocate(storage, fullyQualifiedName!T, cast(void[]) p);

    storage.deallocate(cast(void[]) p);

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
        if (!storage.reallocate(array_, T.sizeof * length))
            return false;

        // g_mem_tracker.record_reallocate(storage, fullyQualifiedName!T, array, array_);

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
