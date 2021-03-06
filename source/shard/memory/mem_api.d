module shard.memory.mem_api;

import shard.memory.measures : mib;
import shard.memory.allocator : Allocator, AllocatorApi;
import shard.memory.buddy : BuddyAllocator;
import shard.memory.sys_allocator : SysAllocator;
import shard.memory.virtual_allocator : VirtualAllocator;
import std.typecons : scoped;

enum default_temp_size = 2.mib;

struct MemoryApi {
    import core.stdc.stdlib : malloc, free;

    this(size_t temp_size) {
        _sys_allocator = scoped!(AllocatorApi!(SysAllocator))();

        _temp_region = malloc(temp_size)[0 .. temp_size];
        _temp_allocator = scoped!(AllocatorApi!(BuddyAllocator))(_temp_region);
        temp_region_size = temp_size;

        _vm = VirtualAllocator();
    }

    ~this() {
        destroy(_sys_allocator);
        destroy(_temp_allocator);
        free(_temp_region.ptr);
    }

    Allocator sys() nothrow {
        return _sys_allocator;
    }

    Allocator temp() nothrow {
        return _temp_allocator;
    }

    VirtualAllocator* vm() return nothrow {
        return &_vm;
    }

    const size_t temp_region_size;

private:
    typeof(scoped!(AllocatorApi!(SysAllocator))()) _sys_allocator;
    typeof(scoped!(AllocatorApi!(BuddyAllocator))([])) _temp_allocator;
    VirtualAllocator _vm;

    void[] _temp_region;
}
