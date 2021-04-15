module shard.memory.allocator;

import shard.memory.common;
import shard.memory.measures;
import std.traits : hasElaborateDestructor, hasMember;
import core.lifetime : emplace;
import core.checkedint : mulu;
import std.algorithm : max, min;

// Re-export Ternary from common, which re-exports std.typecons.Ternary.
public import shard.memory.common: Ternary;

abstract class Allocator {
    /// The default alignment used by the allocator.
    size_t alignment() const nothrow;

    /**
    OPTIONAL

    Tests if the memory was allocated from this allocator.

    Params:
        memory =    The block of memory to test. May be `null`.
    
    Returns: `yes` if `memory` is `null` or was allocated from the allocator,
             `unknown` if it _might_ have been allocated from this allocator,
             and `no` was not allocated from this allocator.
    */
    Ternary owns(void[] memory) const nothrow;

    /**
    OPTIONAL

    Calculates the optimal allocation size for at least `size` bytes of data to
    minimize fragmentation.

    Params:
        size =      The minimum size of a block.

    Returns: The optimal size. If `size` is `0`, this must also be `0`.
    */
    size_t get_optimal_alloc_size(size_t size) const nothrow;

    /**
    Allocates `size` bytes from the allocator if `size > 0`, otherwise this
    function is a no-op.

    Params:
        size =      The size of the block of memory to allocate.

    Returns: A block of memory of the requested size, or `null` if `size == 0`
             or the allocation failed.
    */
    void[] allocate(size_t size) nothrow;

    /**
    OPTIONAL

    If supported by the allocator, returns the memory to the allocator to be
    reused for further allocations. It is an error to call this with a block of
    memory that was not allocated by the allocator.

    Params:
        memory =    The block of memory to deallocate.

    Returns: `true` if `memory` was `null` or was returned to the allocator,
             `false` if the memory was not returned, or if allocator does not
             support deallocation.
    */
    bool deallocate(ref void[] memory) nothrow;

    /// ditto
    bool deallocate(void[] memory) nothrow {
        return deallocate(memory);
    }

    /**
    OPTIONAL

    Attempts to resize a block of memory, possibly allocating new memory to do
    so. It is an error to call this with a block of memory that was not
    allocated by this allocator.

    Note: If `memory` is `null` and `size` is `0`, this function attempts an
    empty allocation.

    Params:
        memory =    The block of memory to resize. If `null`, `reallocate` will
                    attempt to allocate a block of memory.
        new_size =  The new size of the block. If `0`, `reallocate` will
                    attempt to deallocate the block.

    Returns: `true` if the memory block was reallocated, `false` otherwise.
    */
    bool reallocate(ref void[] memory, size_t new_size) nothrow;

    /**
    OPTIONAL

    Attempts to resize a block of memory in-place. It is an error to call this
    with a block of memory that was not allocated by this allocator.

    Params:
        memory =    The block of memory to resize. Resizing fails if this is
                    `null`.
        new_size =  The new size of the block. Resizing fails if this is `0`.

    Returns: `true` if the memory block was resized, `false` otherwise.
    */
    bool resize(ref void[] memory, size_t new_size) nothrow;

    /// Forward shard.memory.make()
    auto make(T, A...)(auto ref A args) {
        return make!T(this, args);
    }

    /// Forward shard.memory.make_array()
    auto make_array(T)(size_t length) {
        return shard.memory.make_array!(T)(this, length);
    }

    /// Forward shard.memory.dispose()
    void dispose(T)(auto ref T* p) {
        shard.memory.dispose(this, p);
    }

    /// Ditto
    void dispose(T)(auto ref T p) if (is(T == class) || is(T == interface)) {
        shard.memory.dispose(this, p);
    }

    /// Ditto
    void dispose(T)(auto ref T[] array) {
        shard.memory.dispose(this, array);
    }

    /// Forward shard.memory.resize_array()
    bool resize_array(T)(
            ref T[] array,
            size_t new_length,
            scope void delegate(size_t, ref T) nothrow init_obj = null,
            scope void delegate(size_t, ref T) nothrow clear_obj = null) {
        return shard.memory.resize_array(this, array, new_length, init_obj, clear_obj);
    }
}

final class AllocatorApi(T) : Allocator {
    T impl;

nothrow public:
    this(Args...)(Args args) {
        impl = T(args);
    }

    ~this() {
        destroy(impl);
    }

    override size_t alignment() const {
        return impl.alignment();
    }

    override Ternary owns(void[] memory) const {
        static if (hasMember!(T, "owns"))
            return impl.owns(memory);
        else
            return Ternary.unknown;
    }

    override size_t get_optimal_alloc_size(size_t size) const {
        static if (hasMember!(T, "get_optimal_alloc_size"))
            return impl.get_optimal_alloc_size(size);
        else
            return round_to_next(size, alignment);
    }

    override void[] allocate(size_t size) {
        return impl.allocate(size);
    }

    alias deallocate = Allocator.deallocate;

    override bool deallocate(ref void[] memory) {
        static if (hasMember!(T, "deallocate"))
            return impl.deallocate(memory);
        else
            return false;
    }

    override bool reallocate(ref void[] memory, size_t new_size) {
        static if (hasMember!(T, "reallocate"))
            return impl.reallocate(memory, new_size);
        else
            return false;
    }

    override bool resize(ref void[] memory, size_t new_size) {
        static if (hasMember!(T, "resize"))
            return impl.resize(memory, new_size);
        else
            return false;
    }
}

PtrType!T make(T, A, Args...)(auto ref A allocator, Args args) {
    // Support 0-size structs
    void[] m = allocator.allocate(max(object_size!T, 1));
    if (!m.ptr) return null;

    static if (is(T == class))
        return emplace!T(m, args);
    else {
        auto p = (() @trusted => cast(T*) m.ptr)();
        emplace!T(p, args);
        return p;
    }
}

T[] make_array(T, A)(auto ref A allocator, size_t length) {
    import core.stdc.string : memcpy, memset;

    if (!length)
        return null;
    
    bool overflow;
    const size = mulu(T.sizeof, length, overflow);
    
    if (overflow)
        return null;

    auto m = allocator.allocate(size);
    if (!m.ptr)
        return null;
    
    assert(m.length > 0);

    static if (__traits(isZeroInit, T)) {
        memset(m.ptr, 0, size);
    }
    else static if (T.sizeof == 1) {
        T t = T.init;
        memset(m.ptr, *(cast(ubyte*) &t), m.length);
    }
    else {
        T t = T.init;
        memcpy(m.ptr, &t, T.sizeof);

        // Copy exponentially
        for (size_t offset = T.sizeof; offset < m.length; ) {
            auto extent = min(offset, m.length - offset);
            memcpy(m.ptr + offset, m.ptr, extent);
            offset += extent;
        }
    }
    return (() @trusted => cast(T[]) m)();
}

void dispose(T, A)(auto ref A allocator, auto ref T* p) {
    static if (hasElaborateDestructor!T)
        destroy(*p);
    
    allocator.deallocate((cast(void*) p)[0 .. T.sizeof]);

    static if (__traits(isRef, p))
        p = null;
}

void dispose(T, A)(auto ref A allocator, auto ref T p)
if (is(T == class) || is(T == interface)) {
    if (!p)
        return;
    
    static if (is(T == interface))
        auto ob = cast(Object) p;
    else
        alias ob = p;
    
    auto support = (cast(void*) ob)[0 .. typeid(ob).initializer.length];
    destroy(p);
    allocator.deallocate(support);

    static if (__traits(isRef, p))
        p = null;
}

void dispose(T, A)(auto ref A allocator, auto ref T[] p) {
    static if (hasElaborateDestructor!(typeof(p[0])))
        foreach (ref e; p)
            destroy(e);
    
    allocator.deallocate(cast(void[]) p);

    static if (__traits(isRef, p))
        p = null;
}

/**
Resizes an array to `new_length` elements, calling `init_obj` on newly
allocated objects, and `clear_obj` on objects to be deallocated.

If `new_length > 0` and `array == null`, a new array will be allocated, and the
slice assigned to `array`. Similarly, if `new_length == 0` and `array != null`,
the array will be freed, and `array` will become `null`.

Params:
    allocator   = The allocator that the array was allocated from.
    array       = The array to be resized. May be `null`.
    new_length  = The length of the array after resizing. May be `0`.
    init_obj    = The delegate to call on newly allocated array elements (during array expansion).
    clear_obj   = The delegate to call on array elements that will be freed (during array reduction).
*/
bool resize_array(T, A)(
        auto ref A allocator,
        ref T[] array,
        size_t new_length,
        scope void delegate(size_t, ref T) nothrow init_obj = null,
        scope void delegate(size_t, ref T) nothrow clear_obj = null) nothrow {
    import std.algorithm: min;

    static assert(!hasMember!(T, "opPostMove"), "Move construction on array reallocation not supported!");

    if (new_length == array.length)
        return true;

    const common_length = min(array.length, new_length);

    if (new_length < array.length && clear_obj) {
        foreach (i, ref object; array[new_length .. $])
            clear_obj(i, object);
    }

    void[] array_ = array;
    if (!allocator.reallocate(array_, T.sizeof * new_length))
        return false;
    array = cast(T[]) array_;

    if (common_length < new_length && init_obj) {
        foreach (i, ref object; array[common_length .. $])
            init_obj(i, object);
    }

    return true;
}

// public import std.experimental.allocator: dispose;

version (unittest) {
    void test_allocate_api(AllocatorType)(ref AllocatorType allocator) {
        assert(allocator.owns([]) == Ternary.yes);
        assert(allocator.allocate(0) == []);

        auto empty = [];

        static if (hasMember!(AllocatorType, "deallocate"))
            assert(allocator.deallocate(empty));

        assert(allocator.get_optimal_alloc_size(0) == 0);

        auto m = allocator.allocate(allocator.get_optimal_alloc_size(1));
        assert(m);
        assert(m.length == allocator.get_optimal_alloc_size(1));
        assert(allocator.owns(m) != Ternary.no);
        assert((cast(size_t) m.ptr) % allocator.alignment == 0);

        static if (hasMember!(AllocatorType, "deallocate")) {
            // cleanup
            allocator.deallocate(m);
            assert(!m);
        }
    }

    void test_reallocate_api(AllocatorType)(ref AllocatorType allocator) {
        void[] m;
        allocator.reallocate(m, 20);
        assert(m);
        assert(m.length == 20);
        const s = m.ptr;
        
        // Reallocation as resize
        assert(allocator.reallocate(m, 1));
        assert(m.ptr == s);
        assert(m.length == 1);

        // Reallocation as resize (limits)
        assert(allocator.reallocate(m, allocator.get_optimal_alloc_size(1)));
        assert(m.ptr == s);

        // Reallocation as allocation and copy
        static if (hasMember!(AllocatorType, "resize"))
            assert(!allocator.resize(m, m.length + 1));

        assert(allocator.reallocate(m, m.length + 1));
        assert(m.length == allocator.get_optimal_alloc_size(1) + 1);
        assert(m.ptr != s); // error here!

        // Reallocation as deallocation
        assert(allocator.reallocate(m, 0));
        assert(m == null);

        // Empty reallocation
        assert(allocator.reallocate(m, 0));
    }

    /// Set can_grow to indicate that resize() may grow an allocation even where
    /// `size == optimal_alloc_size(s)`
    void test_resize_api(bool can_grow = false, AllocatorType)(ref AllocatorType allocator) {
        auto empty = [];
        assert(!allocator.resize(empty, 1));
        assert(!allocator.resize(empty, 0));

        auto m = allocator.allocate(1);
        const s = m.ptr;

        // Resize fail on size 0
        auto m2 = m;
        assert(!allocator.resize(m2, 0));
        assert(m2 == m);

        // Resize down
        assert(allocator.resize(m, 1));
        assert(m.length == 1);
        assert(m.ptr == s);

        // Resize up
        assert(allocator.resize(m, allocator.get_optimal_alloc_size(1)));
        assert(m.ptr == s);

        // Failed resize (limits)
        static if (!can_grow)
            assert(!allocator.resize(m, allocator.get_optimal_alloc_size(1) + 1));

        static if (hasMember!(AllocatorType, "deallocate")) {
            allocator.deallocate(m);
            assert(!m);
        }
    }
}
