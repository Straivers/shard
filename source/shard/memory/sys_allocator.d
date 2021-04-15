module shard.memory.sys_allocator;

import shard.memory.common;
import core.stdc.stdlib: malloc, free, realloc;

struct SysAllocator {
    size_t alignment() const nothrow {
        // It has to be at least word-size
        return size_t.sizeof;
    }

    void[] allocate(size_t size) nothrow {
        if (auto p = malloc(size))
            return p[0 .. size];
        else
            return [];
    }

    bool deallocate(ref void[] memory) nothrow {
        free(memory.ptr);
        return true;
    }

    bool reallocate(ref void[] memory, size_t new_size) nothrow {
        if (auto p = realloc(memory.ptr, new_size)) {
            memory = p[0 .. new_size];
            return true;
        }
        else
            return false;
    }
}
