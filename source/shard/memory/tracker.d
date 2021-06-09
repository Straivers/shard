module shard.memory.tracker;

import shard.memory.allocators.api;
import shard.memory.allocators.system;
import shard.pad : pad_bytes;

import shard.utils.handle : HandlePool;

/*
final class MemoryTracker {
    alias no_name = Allocator.no_name;

    enum max_tracked_scopes = 64;

public @safe nothrow:
    this(SystemAllocator allocator) {
        _allocator = allocator;
        _scopes = ScopePool(_scopes_storage);
    }

    MemoryScope acquire_scope() {
        const id = _scopes.allocate();
        assert(0);

    }

    void[] allocate(ScopeId id, size_t size, string name = no_name) {
        return _allocator.allocate(size, name);
    }

    void deallocate(ScopeId id, void[] memory) {
        _allocator.deallocate(memory);
    }

    void[] reallocate_array(ScopeId id, void[] memory, size_t size, length_t length, string name = no_name) {
        return _allocator.reallocate_array(memory, size, length, name);
    }

private:
    ScopePool _scopes;
    uint _bytes_allocated;

    SystemAllocator _allocator;
    ScopePool.Slot[max_tracked_scopes] _scopes_storage;
}

struct MemoryScope {
    ~this() {
        destroy(_impl);
    }

    Allocator allocator() {
        return _impl;
    }

private:
    TrackedAllocator _impl;
}

private:

alias ScopePool = HandlePool!("MemoryTracker::ScopePool", TrackedScope);
alias ScopeId = ScopePool.Handle;

struct TrackedScope {
    const(char)* name;
    uint name_length;
    uint bytes_allocated;
    ScopeId[8] child_scopes;

    static assert(typeof(this).sizeof == 48);
}

final class TrackedAllocator : Allocator {
    ScopeId scope_id;
    MemoryTracker base_allocator;

@safe:
    this(ScopeId id, MemoryTracker base) {
        scope_id = id;
        base_allocator = base;
    }

    ~this() {
        // base.destroy_scope(scope_id);
    }

    void[] allocate(size_t size, string name = no_name) {
        return base_allocator.allocate(scope_id, size, name);
    }

    void deallocate(void[] memory) {
        base_allocator.deallocate(scope_id, memory);
    }

    void[] reallocate_array(void[] memory, size_t element_size, length_t new_length, string name = no_name) {
        return base_allocator.reallocate_array(scope_id, memory, element_size, new_length, name);
    }
}
*/