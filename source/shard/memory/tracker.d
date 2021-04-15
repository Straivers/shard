module shard.memory.tracker;

__gshared g_memory_tracker;

struct MemoryTracker {
    void record_allocate(string type_name, void[] memory) {

    }

    void record_deallocate(string type_name, void[] memory) {

    }

    void record_reallocate(string type_name, void[] old_place, void[] new_place) {

    }
}
