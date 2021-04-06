module shard.memory.virtual_allocator;

import shard.memory.common;
import shard.memory.arena : UnmanagedArena;
import std.algorithm : min, max;

public import core.memory : page_size = pageSize;

version (Windows) import core.sys.windows.windows : VirtualAlloc, VirtualFree, MEM_RESERVE, MEM_COMMIT, MEM_RELEASE, PAGE_READWRITE, PAGE_NOACCESS;

/**
API for allocating memory from the OS' virtual memory subsystem.
*/
struct VirtualAllocator {
    // TODO: Implement memory tracking for vm allocations.

    /**
    Reserves `num_bytes` rounded up to the nearest page size from the VM.

    Parameters:
        num_bytes = The number of bytes to be reserved. Gets rounded up to the
                    next multiple of the page size.
    
    Returns: A slice covering the entire reserved range of memory.
    */
    void[] reserve(size_t num_bytes) {
        const actual_size = round_to_next(num_bytes, page_size);

        version (Windows) {
            auto p = VirtualAlloc(null, actual_size, MEM_RESERVE, PAGE_NOACCESS);
            assert(p, "Failed to allocate virtual memory.");
            return p[0 .. actual_size];
        }
        else
            static assert(0, "Unsupported platform");
    }

    /**
    Commits a slice of previously reserved memory. The region is not backed by
    physical pages of memory until it is first touched. Committing a page
    multiple times will not crash the program, but will disrupt allocation
    tracking.
    
    Parameters:
        span = The sub-slice of reserved memory to be committed. Note that
               Windows does not allow you to over-commit, so be careful.
    */
    void commit(void[] span) {
        assert(span.length % page_size == 0, "Committed spans must have length a multiple of page size.");
        version (Windows) {
            const p = VirtualAlloc(span.ptr, span.length, MEM_COMMIT, PAGE_READWRITE);
            assert(p, "Failed to commit virtual memory.");
        }
        else
            static assert(0, "Unsupported platform");
    }

    /**
    Frees a reserved span and returns it to the operating system.
    */
    void free(void[] span) {
        version (Windows) {
            const err = VirtualFree(span.ptr, 0, MEM_RELEASE);
            assert(err, "Failed to free virtual memory.");
        }
        else
            static assert(0, "Unsupported platform");
    }
}
