module shard.memory.allocators.api;

import shard.math : round_to_next;
import shard.memory.lifetime;

public import std.typecons : Ternary;

/** 
 * IAllocator provides a uniform interface for accessing custom allocators and
 * sub-allocators.
 */
struct IAllocator {
    @disable this(this);

    enum no_name = "unknown";

    nothrow {
        alias Self = void*;
        alias AlignmentFn = size_t function(const Self);
        alias OptimalSizeFn = size_t function(const Self, size_t);
        alias AllocateFn = void[]function(Self, size_t, string name = no_name);
        alias DeallocateFn = void function(Self, void[], string name = no_name);
        alias ReallocateFn = bool function(Self, ref void[], size_t, size_t, string name = no_name);
    }

    void* instance;
    AlignmentFn alignment_fn;
    OptimalSizeFn optimal_size_fn;
    AllocateFn allocate_fn;
    DeallocateFn deallocate_fn;
    ReallocateFn reallocate_fn;

    static assert(typeof(this).sizeof == 48);

    /// The minimum alignment for all allocations.
    size_t alignment() const nothrow {
        return alignment_fn(instance);
    }

    /// Returns a size >= `size` that reduces internal fragmentation.
    size_t optimal_size(size_t size) const nothrow {
        return optimal_size_fn ? optimal_size_fn(instance, size) : round_to_next(size, alignment);
    }

    /**
    Allocates `size` bytes of memory. Returns `null` if out of memory.

    Params:
        size        = The number of bytes to allocate. Must not be 0.

    Returns:
        A block of `size` bytes of memory or `null` if out of memory or `size`
        = 0.
    */
    void[] allocate(size_t size, string name = no_name) nothrow {
        return allocate_fn(instance, size, name);
    }

    /**
    Returns `memory` to the allocator.

    Params:
        memory      = A block of memory previously allocated by `allocate()` or
                      `resize()`.
    */
    void deallocate(void[] block, string name = no_name) nothrow {
        deallocate_fn(instance, block, name);
    }

    /// ditto
    void deallocate(ref void[] block, string name = no_name) nothrow {
        deallocate_fn(instance, block, name);
        block = null;
    }

    /**
    Attempts to resize `memory`. If `memory.length = size`, this function is a
    no-op.
    
    If `memory` is `null` and `size` > 0, `reallocate()` acts as `allocate()`.

    If `memory` is not `null` and `size` = 0, `reallocate()` acts as `deallocate()`.

    Params:
        memory      = The memory block to resize. May be `null`.
        size        = The size of each sub-unit in the memory block.
        count       = The number of sub-units to be in the resized block.

    Returns: `true` if `memory` was resized, `false` otherwise.
    */
    bool reallocate(ref void[] memory, size_t size, size_t count, string name = no_name) nothrow {
        return reallocate_fn ? reallocate_fn(instance, memory, size, count, name) : false;
    }

    auto make(T, Args...)(auto ref Args args) {
        return shard.memory.lifetime.make!T(this, args);
    }

    auto make_array(T)(size_t length) {
        return shard.memory.lifetime.make_array!T(this, length);
    }

    auto make_raw_array(T)(size_t length) {
        return shard.memory.lifetime.make_raw_array!T(this, length);
    }

    void dispose(T)(auto ref T* p) {
        shard.memory.lifetime.dispose(this, p);
    }

    void dispose(T)(auto ref T p) if (is(T == class) || is(T == interface)) {
        shard.memory.lifetime.dispose(this, p);
    }

    void dispose(T)(auto ref T[] array) {
        shard.memory.lifetime.dispose(this, array);
    }

    bool resize_array(T)(ref T[] array, size_t length) nothrow {
        return shard.memory.lifetime.resize_array(this, array, length);
    }
}

version (unittest) {
    void test_allocate_api(ref IAllocator allocator) {
        auto m1 = allocator.allocate(0);
        assert(m1 == null);

        allocator.deallocate(m1); // must not crash

        auto m2 = allocator.allocate(8);
        assert(m2.length == 8);
        assert(allocator.optimal_size(8) >= 8);
        assert((cast(size_t) m2.ptr) % allocator.alignment == 0);

        auto m3 = allocator.allocate(13);
        assert(m3.length == 13);
        assert(allocator.optimal_size(13) >= 13);
        assert((cast(size_t) m3.ptr) % allocator.alignment == 0);

        auto m4 = allocator.allocate(21);
        assert(m4.length == 21);
        assert(allocator.optimal_size(21) >= 21);
        assert((cast(size_t) m4.ptr) % allocator.alignment == 0);

        allocator.deallocate(m4);
        assert(m4 == null);

        auto m5 = allocator.allocate(34);
        assert(m5.length == 34);
        assert(allocator.optimal_size(34) >= 34);
        assert((cast(size_t) m5.ptr) % allocator.alignment == 0);

        allocator.deallocate(m2);
        allocator.deallocate(m3);
        allocator.deallocate(m4);
        allocator.deallocate(m5);
    }

    void test_resize_api(ref IAllocator allocator) {
        void[] m1;

        // Reallocation as allocation
        allocator.reallocate(m1, 1, 23);
        assert(m1);
        assert(m1.length == 23);

        auto p1 = m1.ptr;
        allocator.reallocate(m1, 1, 23);
        assert(m1.length == 23);
        assert(m1.ptr == p1);

        // Reallocation as resize down
        assert(allocator.reallocate(m1, 1, 1));
        assert(m1.length == 1);

        // Reallocation as resize up
        assert(allocator.reallocate(m1, 1, 12));
        assert(m1.length == 12);

        {
            void[] m2;
            m2 = allocator.allocate(20);

            // Grow not-most-recent allocation
            allocator.reallocate(m1, 1, 64);
            assert(m1.length == 64);

            // Shrink not-most-recent allocation
            allocator.reallocate(m2, 1, 1);
            assert(m2.length == 1);

            allocator.deallocate(m2);
        }

        // Reallocation as deallocation
        assert(allocator.reallocate(m1, 1, 0));
        assert(m1 == null);
    }
}
