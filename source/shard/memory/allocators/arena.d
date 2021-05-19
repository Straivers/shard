module shard.memory.allocators.arena;

import std.algorithm : min;
import core.stdc.string : memcpy;

import shard.math : round_to_next;
import shard.memory.allocators.api;
import shard.memory.constants : platform_alignment;

struct Arena {
public:
    this(void[] memory, size_t alignment = platform_alignment) {
        _allocator_api = IAllocator(
            &this,
            &allocator_api_alignment,
            null,
            &allocator_api_allocate,
            &allocator_api_deallocate,
            &allocator_api_reallocate,
        );

        const aligned_start = round_to_next(cast(size_t) memory.ptr, alignment);

        _alignment = alignment;

        _start = cast(void*) aligned_start;
        _end = memory.ptr + memory.length;
        _top = _start;
    }

    /// Retrieves a compliant IAllocator interface.
    ref IAllocator allocator_api() return nothrow {
        return _allocator_api;
    }

    /// The minimum alignment for all allocations.
    size_t alignment() const nothrow {
        return _alignment;
    }

    /**
    Allocates `size` bytes of memory. Returns `null` if out of memory.

    Params:
        size        = The number of bytes to allocate. Must not be 0.
    
    Returns:
        A block of `size` bytes of memory or `null` if out of memory or `size`
        = 0.
    */
    void[] allocate(size_t size) nothrow {
        if (size == 0)
            return null;

        return raw_allocate(round_to_next(size, _alignment), size);
    }

    /**
    Returns `memory` to the allocator.

    Params:
        memory      = A block of memory previously allocated by `allocate()` or
                      `resize()`.
    */
    void deallocate(void[] block) nothrow {
        // If this is the last block, deallocate it
        if (block && block.ptr + round_to_next(block.length, _alignment) == _top) {
            _top = block.ptr;
        }
    }

    /**
    Attempts to resize `memory`. If `memory.length = size`, this function is a
    no-op.
    
    If `memory` is `null` and `size` > 0, `reallocate()` acts as `allocate()`.

    If `memory` is not `null` and `size` = 0, `reallocate()` acts as `deallocate()`.

    Params:
        memory      = The memory block to resize. May be `null`.
        size        = The size of the memory block after `reallocate()` returns.
                      May be 0.

    Returns: `true` if `memory` was resized, `false` otherwise.
    */
    bool reallocate(ref void[] block, size_t size) nothrow {
        const block_size = round_to_next(block.length, _alignment);
        const actual_size = round_to_next(size, _alignment);

        if (block_size == actual_size) {
            block = block.ptr[0 .. size];
            return true;
        }

        if (block == null) {
            assert(actual_size > 0);

            block = raw_allocate(actual_size, size);
            return block != null;
        }

        assert(block);
        if (actual_size == 0) {
            deallocate(block);
            block = null;
            return true;
        }

        const is_last_block = block.ptr + block_size == _top;
        if (is_last_block && block.ptr + actual_size <= _end) {
            block = block.ptr[0 .. size];
            _top = block.ptr + actual_size;
            return true;
        }
        else if (actual_size < block_size) {
            block = block[0 .. size];
            return true;
        }
        else if (actual_size > block_size) {
            if (auto new_block = raw_allocate(actual_size, size)) {
                memcpy(new_block.ptr, block.ptr, min(size, block.length));
                block = new_block;
                return true;
            }

            return false;
        }

        assert(0, "Unreachable");
    }

private:
    static size_t allocator_api_alignment(const void* self) nothrow {
        return (cast(const Arena*) self).alignment();
    }

    static void[] allocator_api_allocate(void* self, size_t size) nothrow {
        return (cast(Arena*) self).allocate(size);
    }

    static void allocator_api_deallocate(void* self, void[] block) nothrow {
        return (cast(Arena*) self).deallocate(block);
    }

    static bool allocator_api_reallocate(void* self, ref void[] block, size_t size) nothrow {
        return (cast(Arena*) self).reallocate(block, size);
    }

    void[] raw_allocate(size_t aligned_size, size_t final_size) nothrow {
        if (_end - _top < aligned_size)
            return null;

        auto block = _top[0 .. final_size];
        _top += aligned_size;
        return block;
    }

    IAllocator _allocator_api;

    size_t _alignment;

    void* _start;
    void* _top;
    void* _end;
}

@("Arena IAllocator compliance")
unittest {
    auto ua = Arena(new void[](1024));
    test_allocate_api(ua.allocator_api());
    test_resize_api(ua.allocator_api());
}
