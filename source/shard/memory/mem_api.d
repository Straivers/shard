module shard.memory.mem_api;

import shard.memory.tracker;
import shard.memory.measures : mib;
import shard.memory.allocator : Allocator, AllocatorApi;
import shard.memory.buddy : BuddyAllocator;
import shard.memory.sys_allocator : SysAllocator;
import std.typecons : scoped;

enum temp_size = 2.mib;

struct MemoryApi {
    void get_stats(out MemoryStats stats) {
        MemoryStats sys;
        _sys_allocator.impl.get_stats(sys);

        MemoryStats tmp;
        _temp_allocator.impl.get_stats(tmp);

        stats.num_allocations = sys.num_allocations + tmp.num_allocations;
        stats.num_failed_allocations = sys.num_failed_allocations + tmp.num_failed_allocations;
        stats.bytes_allocated = sys.bytes_allocated + tmp.bytes_allocated;

        /// Note: this is incorrect, because the high-water mark for sys and tmp
        /// may not have occured at the same time.
        stats.most_bytes_allocated = sys.most_bytes_allocated + temp_size;
    }

    Allocator sys() nothrow {
        return _sys_allocator;
    }

    Allocator temp() nothrow {
        return _temp_allocator;
    }

private:
    typeof(scoped!(AllocatorApi!(MemoryTracker!SysAllocator))()) _sys_allocator;
    typeof(scoped!(AllocatorApi!(MemoryTracker!BuddyAllocator))([])) _temp_allocator;

    this(size_t temp_size) {
        _sys_allocator = scoped!(AllocatorApi!(MemoryTracker!SysAllocator))();
        _temp_allocator = scoped!(AllocatorApi!(MemoryTracker!BuddyAllocator))(_sys_allocator.allocate(temp_size));
    }

    ~this() {
        destroy(_sys_allocator);
        destroy(_temp_allocator);
    }
}

void initialize_memory_api(ref MemoryApi api) {
    api = MemoryApi(temp_size);
}

void terminate_memory_api(ref MemoryApi api) {
    MemoryStats stats;
    api.get_stats(stats);
    // assert(stats.num_allocations == 0);
    // assert(stats.bytes_allocated == temp_size);

    destroy(api);
}
