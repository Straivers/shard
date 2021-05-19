module shard.memory.allocators.api;

import shard.memory.lifetime;
import shard.math: round_to_next;

public import std.typecons : Ternary;

/**
Abstract allocator interface for working with custom memory allocators.
*/
abstract class Allocator {
    /// The minimum alignment for all allocations.
    size_t alignment() const nothrow;

    /// Rounds `size` up to minimize internal allocator fragmentation.
    size_t optimal_size(size_t size) const nothrow {
        return round_to_next(size, alignment);
    }

    /**
    Allocates `size` bytes of memory.
    */
    void[] allocate(size_t size) nothrow;

    /**
    Returns `memory` to the allocator.

    Params:
        memory      = A block of memory previously allocated by `allocate()` or
                      `resize()`.
    */
    void deallocate(ref void[] memory) nothrow;

    /// ditto
    void deallocate(void[] memory) nothrow {
        deallocate(memory);
    }

    bool reallocate(ref void[] memory, size_t size) nothrow;

    /**
    Attempts to resize `memory`.

    Params:
        memory      = The memory block to resize. May be `null`.
        size        = The size of the memory block after `resize()` returns.
                      May be 0.
        in_place    = If `true`, restricts `resize()` to non-copying operations.

    Returns: `true` if `memory` was resized, `false` otherwise.
    */
    bool resize(ref void[] memory, size_t size) nothrow;
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

        // cleanup
        allocator.deallocate(m);
        assert(!m);
    }

    void test_resize_api(AllocatorType)(ref AllocatorType allocator) {
        void[] m;
        allocator.reallocate(m, 20);
        assert(m);
        assert(m.length == 20);
        const s = m.ptr;
        
        // Reallocation as resize down
        assert(allocator.reallocate(m, 1));
        assert(m.ptr == s);
        assert(m.length == 1);

        // Reallocation as resize up
        if (allocator.optimal_size(m.length) > m.length) {
            assert(allocator.reallocate(m, allocator.optimal_size(1)));
            assert(m.ptr == s);
        }

        // Reallocation as allocation and copy
        assert(!allocator.reallocate(m, m.length + 1));

        assert(allocator.reallocate(m, m.length + 1));
        assert(m.length == allocator.optimal_size(1) + 1);
        assert(m.ptr != s); // error here!

        // Reallocation as deallocation
        assert(allocator.reallocate(m, 0));
        assert(m == null);

        // Empty reallocation
        assert(allocator.reallocate(m, 0));
    }
}
