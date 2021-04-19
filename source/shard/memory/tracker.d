module shard.memory.tracker;

import shard.collections.hash_map : UnmanagedHashMap32;
import shard.handle_pool : Handle32, HandlePool;
import shard.memory.allocator : Allocator;
import shard.hash : Hash32;
import std.bitmanip : bitfields;

enum tracked_allocator_handle_name = "shard_memory_tracker_handle";
alias TrackedAllocatorId = Handle32!tracked_allocator_handle_name;

final class MemoryTracker {
    this(Allocator sys_allocator) {
        _sys_allocator = sys_allocator;
        _sys_allocator_id = add_allocator(TrackedAllocatorId());
    }

    ~this() {
    }

    const TrackedAllocatorId sys_allocator_id() {
        return _sys_allocator_id;
    }

    TrackedAllocatorId add_allocator(TrackedAllocatorId parent) {
        // make sure to initialize AllocatorInfo
        assert(0, "Not Implemented");
    }

    void remove_allocator(TrackedAllocatorId allocator) {
        assert(0, "Not Implemented");
    }

    void record_allocate(TrackedAllocatorId allocator, string type_name, void[] memory) {
        auto op = MemoryOp(Hash32.of(type_name), cast(uint) memory.length, cast(size_t) memory.ptr);
        _allocators.get(allocator).ops.insert(memory.ptr, op, _sys_allocator);
    }

    void record_deallocate(TrackedAllocatorId allocator, void[] memory) {
        _allocators.get(allocator).ops.remove(memory.ptr, _sys_allocator);
    }

    void record_reallocate(TrackedAllocatorId allocator, string type_name, void[] old_place, void[] new_place) {
        if (old_place.ptr == new_place.ptr)
            _allocators.get(allocator).ops.get(old_place.ptr).size_1 = cast(uint) new_place.length;
        else {
            record_deallocate(allocator, old_place);
            record_allocate(allocator, type_name, new_place);
        }
    }

private:
    Allocator _sys_allocator;
    TrackedAllocatorId _sys_allocator_id;

    // Implement freelist for AllocatorInfo, reduce _allocators size

    // StringCache _string_cache;

    void[512 * size_t.sizeof] _allocator_mem;
    HandlePool!(AllocatorInfo, tracked_allocator_handle_name, 512) _allocators;
}

private:

struct MemoryOp {
    Hash32 type_name;
    uint size_1;
    size_t memory1;

    static assert(MemoryOp.sizeof == 16);
}

struct AllocatorInfo {
    UnmanagedHashMap32!(void*, MemoryOp) ops;
}
