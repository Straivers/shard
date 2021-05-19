module shard.memory.allocators.system;

import shard.math: round_to_next;
import shard.memory.allocators.api;
import shard.memory.constants: platform_alignment;

import core.stdc.stdlib: malloc, free, realloc;

struct SystemAllocator {
    private IAllocator _allocator_api;

    ref IAllocator allocator_api() return nothrow {
        return _allocator_api;
    }

    static create() nothrow {
        return SystemAllocator(IAllocator(
            null,
            &alignment,
            null,
            &allocate,
            &deallocate,
            &reallocate,
            null
        ));
    }

    static size_t alignment(const void* dummy) nothrow {
        return platform_alignment;
    }

    static void[] allocate(void* dummy, size_t size) nothrow {
        if (auto m = malloc(size)[0 .. size])
            return m;
        else
            return null;
    }

    static void deallocate(void* dummy, void[] block) nothrow {
        if (block)
            free(block.ptr);
    }

    static bool reallocate(void* dummy, ref void[] memory, size_t size) nothrow {
        if (memory && size == 0) {
            free(memory.ptr);
            memory = null;
            return true;
        }

        if (auto p = realloc(memory.ptr, size)) {
            memory = p[0 .. size];
            return true;
        }

        return false;
    }
}

unittest {
    auto sa = SystemAllocator.create();
    test_allocate_api(sa.allocator_api());
    test_resize_api(sa.allocator_api());
}
