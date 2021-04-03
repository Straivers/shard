module shard.memory.mem_api;

import shard.memory.tracker;
import shard.memory.measures : mib;
import shard.memory.allocator : Allocator, AllocatorApi;
import shard.memory.buddy : BuddyAllocator;
import shard.memory.sys_allocator : SysAllocator;
import std.typecons : scoped;

enum default_temp_size = 2.mib;

struct MemoryApi {
    import core.stdc.stdlib : malloc, free;

    this(size_t temp_size) {
        _sys_allocator = scoped!(AllocatorApi!(MemoryTracker!SysAllocator))();

        _temp_region = malloc(temp_size)[0 .. temp_size];
        _temp_allocator = scoped!(AllocatorApi!(MemoryTracker!BuddyAllocator))(_temp_region);
        temp_region_size = temp_size;
    }

    ~this() {
        destroy(_sys_allocator);
        destroy(_temp_allocator);
        free(_temp_region.ptr);
    }

    void get_sys_stats(out MemoryStats stats) {
        _sys_allocator.impl.get_stats(stats);
    }

    Allocator sys() nothrow {
        return _sys_allocator;
    }

    Allocator temp() nothrow {
        return _temp_allocator;
    }

    const size_t temp_region_size;

private:
    typeof(scoped!(AllocatorApi!(MemoryTracker!SysAllocator))()) _sys_allocator;
    typeof(scoped!(AllocatorApi!(MemoryTracker!BuddyAllocator))([])) _temp_allocator;

    void[] _temp_region;
}
