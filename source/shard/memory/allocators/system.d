module shard.memory.allocators.system;

import shard.math: round_to_next;
import shard.memory.allocators.api;
import shard.memory.values: platform_alignment;

import core.stdc.stdlib: malloc, free, realloc;

struct SystemAllocator {
public:
    /// Retrieves a compliant IAllocator interface.
    ref IAllocator allocator_api() return nothrow {
        if (_allocator_api == IAllocator())
            _allocator_api = IAllocator(
                &this,
                &allocator_api_alignment,
                null,
                &allocator_api_allocate,
                &allocator_api_deallocate,
                &allocator_api_reallocate,
            );

        return _allocator_api;
    }

    /// The minimum alignment for all allocations.
    size_t alignment() const nothrow {
        return platform_alignment;
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

        auto m = malloc(size);
        return m ? m[0 .. size] : null;
    }

    /**
    Returns `memory` to the allocator.

    Params:
        memory      = A block of memory previously allocated by `allocate()` or
                      `resize()`.
    */
    void deallocate(void[] block) nothrow {
        if (block)
            free(block.ptr);
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
    bool reallocate(ref void[] memory, size_t size) nothrow {
        if (memory && size == 0) {
            free(memory.ptr);
            memory = null;
            return true;
        }

        if (memory.length == size)
            return true;

        if (auto p = realloc(memory.ptr, size)) {
            memory = p[0 .. size];
            return true;
        }

        return false;
    }

private:
    static size_t allocator_api_alignment(const void* self) nothrow {
        return (cast(const SystemAllocator*) self).alignment();
    }

    static void[] allocator_api_allocate(void* self, size_t size) nothrow {
        return (cast(SystemAllocator*) self).allocate(size);
    }

    static void allocator_api_deallocate(void* self, void[] block) nothrow {
        return (cast(SystemAllocator*) self).deallocate(block);
    }

    static bool allocator_api_reallocate(void* self, ref void[] block, size_t size) nothrow {
        return (cast(SystemAllocator*) self).reallocate(block, size);
    }

    IAllocator _allocator_api;
}

@("SystemAllocator IAllocator compliance")
unittest {
    SystemAllocator sa;
    test_allocate_api(sa.allocator_api());
    test_resize_api(sa.allocator_api());
}
