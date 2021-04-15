module shard.memory.tracker;

import shard.collections.array : UnmanagedArray;
import shard.handle_pool;
import shard.memory.allocator : Allocator;
import shard.os.time : OsClockApi, TimeStamp;
import std.bitmanip : bitfields;

enum tracked_allocator_handle_name = "shard_memory_tracker_handle";
alias TrackedAllocatorId = Handle32!tracked_allocator_handle_name;

final class MemoryTracker {
    this(OsClockApi clock, Allocator sys_allocator) {
        _clock = clock;
        _sys_allocator = sys_allocator;
        _sys_allocator_id = add_allocator(TrackedAllocatorId());
    }

    ~this() {
    }

    const TrackedAllocatorId sys_allocator_id() {
        return _sys_allocator_id;
    }

    TrackedAllocatorId add_allocator(TrackedAllocatorId parent) {

    }

    void remove_allocator(TrackedAllocatorId allocator) {

    }

    void record_allocate(TrackedAllocatorId allocator, string type_name, void[] memory) {

    }

    void record_deallocate(TrackedAllocatorId allocator, string type_name, void[] memory) {

    }

    void record_reallocate(TrackedAllocatorId allocator, string type_name, void[] old_place, void[] new_place) {

    }

private:
    OsClockApi _clock;

    Allocator _sys_allocator;
    TrackedAllocatorId _sys_allocator_id;

    size_t _free_list_length;
    AllocatorInfo* _free_list;

    // StringCache _string_cache;

    void[512 * size_t.sizeof] _allocator_mem;
    HandlePool!(AllocatorInfo*, tracked_allocator_handle_name, 512) _allocators;
}

private:

struct MemoryOp {
    enum Kind: ubyte {
        None = 0,
        Allocate = 1,
        Deallocate = 2,
        Reallocate = 3
    }

    TimeStamp time;
    string type_name;
    size_t memory1;
    size_t memory2;

    mixin(bitfields(
        Kind, "kind", 2,
        size_t, "size1", 31,
        size_t, "size2", 31
    ));
}

struct AllocatorInfo {
    AllocatorInfo* next_free;
    UnmanagedArray!MemoryOp ops;
}
