module shard.memory.allocators.api;

import shard.math : round_to_next;
import shard.memory.lifetime;

public import std.typecons : Ternary;

struct IAllocator {
    void* instance;
    size_t function(const void*) nothrow                alignment_fn;
    size_t function(const void*, size_t) nothrow        optimal_size_fn;
    void[] function(void*, size_t) nothrow              allocate_fn;
    void function(void*, void[]) nothrow                deallocate_fn;
    bool function(void*, ref void[], size_t) nothrow    reallocate_fn;

    /// The minimum alignment for all allocations.
    size_t alignment() const nothrow {
        return alignment_fn(instance);
    }

    /// Returns a size >= `size` that reduces internal fragmentation.
    size_t optimal_size(size_t size) const nothrow {
        return optimal_size_fn ? optimal_size_fn(instance, size) : round_to_next(size, alignment);
    }

    /// Allocates `size` bytes of memory. Returns `null` if out of memory.
    void[] allocate(size_t size) nothrow {
        return allocate_fn(instance, size);
    }

    /**
    Returns `memory` to the allocator.

    Params:
        memory      = A block of memory previously allocated by `allocate()` or
                      `resize()`.
    */
    void deallocate(void[] block) nothrow {
        deallocate_fn(instance, block);
    }

    /// ditto
    void deallocate(ref void[] block) nothrow {
        deallocate_fn(instance, block);
        block = null;
    }

    /**
    Attempts to resize `memory`.

    Params:
        memory      = The memory block to resize. May be `null`.
        size        = The size of the memory block after `reallocate()` returns.
                      May be 0.

    Returns: `true` if `memory` was resized, `false` otherwise.
    */
    bool reallocate(ref void[] block, size_t size) nothrow {
        return reallocate_fn ? reallocate_fn(instance, block, size) : false;
    }
}

version (unittest) {
    void test_allocate_api(AllocatorType)(ref AllocatorType allocator) {
        assert(allocator.allocate(0) == []);

        auto empty = [];
        allocator.deallocate(empty);

        assert(allocator.optimal_size(0) == 0);

        auto m = allocator.allocate(allocator.optimal_size(1));
        assert(m);
        assert(m.length == allocator.optimal_size(1));
        assert((cast(size_t) m.ptr) % allocator.alignment == 0);
        allocator.deallocate(m);
        assert(!m);

        auto m2 = allocator.allocate(7);
        assert(m2);
        assert(m2.length == 7);
        assert((cast(size_t) m2.ptr) % allocator.alignment == 0);
        allocator.deallocate(m2);
        assert(!m2);
    }

    void test_resize_api(AllocatorType)(ref AllocatorType allocator) {
        void[] m1;

        // Reallocation as allocation
        allocator.reallocate(m1, allocator.optimal_size(13));
        assert(m1);
        assert(m1.length == allocator.optimal_size(13));

        // Reallocation as resize down
        assert(allocator.reallocate(m1, 1));
        assert(m1.length == 1);

        // Reallocation as resize up
        assert(allocator.reallocate(m1, 12));
        assert(m1.length == 12);

        {
            void[] m2;
            m2 = allocator.allocate(20);

            // Grow not-most-recent allocation
            allocator.reallocate(m1, 50);
            assert(m1.length == 50);

            // Grow not-most-recent allocation
            allocator.reallocate(m2, 123);
            assert(m2.length == 123);

            allocator.deallocate(m2);
        }

        // Reallocation as deallocation
        assert(allocator.reallocate(m1, 0));
        assert(m1 == null);
    }
}
