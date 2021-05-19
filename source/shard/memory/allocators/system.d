module shard.memory.allocators.system;

import shard.math: round_to_next;
import shard.memory.allocators.api;
import shard.memory.constants: platform_alignment;

import core.stdc.stdlib: malloc, free, realloc;

final class SystemAllocator : Allocator {
    override size_t alignment() const nothrow {
        return platform_alignment;
    }

    override size_t optimal_size(size_t size) const nothrow {
        return size;
    }

    override void[] allocate(size_t size) nothrow {
        if (auto m = malloc(size)[0 .. size])
            return m;
        else
            return null;
    }

    alias deallocate = Allocator.deallocate;

    override void deallocate(ref void[] memory) nothrow {
        free(memory.ptr);
        memory = null;
    }

    override bool reallocate(ref void[] memory, size_t size) nothrow {
        if (auto p = realloc(memory.ptr, size)) {
            memory = p[0 .. size];
            return true;
        }
        else
            return false;
    }

    override bool resize(ref void[] memory, size_t size) nothrow {
        return false;
    }
}

unittest {
    scope sa = new SystemAllocator();

    test_allocate_api(sa);
    test_resize_api(sa);
}
