module shard.memory.tracker2;

import shard.hash : Hash32;
import shard.memory.allocators.api;
import shard.memory.allocators.system;
import shard.pad : pad_bytes;
import shard.utils.handle : HandlePool;
import shard.utils.table : HashTable;

import std.bitmanip : bitfields;
import std.exception : assumeWontThrow;
import std.typecons : scoped;

alias ScopeId = HandlePool!(scope_handle_name, TrackedScope).Handle;

final class MemoryTracker {
    enum default_max_scopes = 32;

@safe nothrow:
    @trusted this(size_t max_scopes = default_max_scopes) {
        _root = scoped!SystemAllocator();
        _scopes = typeof(_scopes)(max_scopes, _root);

        _tracker_scope = () {
            auto id = _scopes.allocate();
            _scopes.value_of(id).name = "MemoryTracker";
            return MemoryScope(id, this);
        } ();
    }

    ~this() {
        destroy(_scopes);
        destroy(_types);
    }

    @trusted MemoryScope acquire_scope(string name) {
        auto id = _scopes.allocate();

        auto clone = _tracker_scope.make_array!char(name.length);
        clone[] = name;

        _scopes.value_of(id).name = clone;
        return MemoryScope(id, this);
    }

private @safe nothrow:
    @trusted MemoryScope _acquire_scope(ScopeId parent, string name) {
        auto id = _scopes.allocate();

        auto clone = _tracker_scope.make_array!char(name.length);
        clone[] = name;

        _scopes.value_of(id).name = clone;
        return MemoryScope(id, this);
    }

    @trusted void _release_scope(ScopeId id) {
        assert(_scopes.is_valid(id));
        _tracker_scope.dispose(_scopes.value_of(id).name);
        _scopes.deallocate(id);
    }

    void[] _allocate(ScopeId scope_id, size_t size, string name) {
        assert(_scopes.is_valid(scope_id));

        auto root = (() @trusted => _root.Scoped_payload())();
        const type_id = Hash32.of(&name[0]);

        if (auto type = _types.get(type_id))
            type.num_allocated++;
        else
            _types.insert(type_id, TrackedType(name, cast(uint) size, 0), root);

        auto result = root.allocate(size, name);

        if (result)
            _scopes.value_of(scope_id).allocations.insert(TrackedAllocation(&result[0], type_id, scope_id), root);

        return result;
    }

    void _deallocate(ScopeId scope_id, void[] memory) {
        assert(_scopes.is_valid(scope_id));

        auto root = (() @trusted => _root.Scoped_payload())();
        auto allocations = &_scopes.value_of(scope_id).allocations;

        if (auto alloc = allocations.get(Hash32.of(&memory[0]))) {
            _types.get(alloc.type_id).num_allocated--;
            allocations.remove(alloc, root);
            root.deallocate(memory);
        }
        else {
            assert(0, "Double free detected!");
        }
    }

    void[] _reallocate_array(ScopeId scope_id, void[] memory, size_t size, length_t length, string name) {
        assert(_scopes.is_valid(scope_id));
        assert(memory.length % size == 0);

        auto root = (() @trusted => _root.Scoped_payload())();
        auto allocations = &_scopes.value_of(scope_id).allocations;

        const type_id = Hash32.of(&name[0]);

        if (auto new_memory = root.reallocate_array(memory, size, length, name)) {
            if (memory) {
                // We don't know where `memory`points to anymore, so don't index into it!
                auto old_pointer = &memory[0];
                auto old_allocation = allocations.get(Hash32.of(old_pointer));
                assert(old_allocation.scope_id == scope_id);
                assert(old_allocation.type_id == type_id);
                assert(old_allocation.is_array);
                assert(old_allocation.array_length * size == memory.length);

                if (old_pointer == &new_memory[0]) {
                    old_allocation.array_length = cast(uint) length;
                    return new_memory;
                }
                else {
                    allocations.remove(old_allocation, root);
                }
            }

            auto allocation = allocations.insert(TrackedAllocation(&memory[0], type_id, scope_id), root);
            allocation.is_array = true;
            allocation.array_length = cast(uint) length;

            return new_memory;
        }
        else {
            return [];
        }
    }

    typeof(scoped!SystemAllocator()) _root;

    MemoryScope _tracker_scope;
    HandlePool!(scope_handle_name, TrackedScope) _scopes;

    HashTable!(TrackedType, TrackedType.hash) _types;
}

struct MemoryScope {
    final class Impl : Allocator {
        ScopeId scope_id;
        MemoryTracker tracker;

    @safe nothrow:
        this(ScopeId id, MemoryTracker tracker) {
            scope_id = id;
            this.tracker = tracker;
        }

        ~this() {
            tracker._release_scope(scope_id);
        }

        void[] allocate(size_t size, string name = no_name) {
            return tracker._allocate(scope_id, size, name);
        }

        void deallocate(void[] memory) {
            tracker._deallocate(scope_id, memory);
        }

        void[] reallocate_array(void[] memory, size_t element_size, length_t new_length, string name = no_name) {
            return tracker._reallocate_array(scope_id, memory, element_size, new_length, name);
        }
    }

@safe nothrow:
    @trusted this(ScopeId id, MemoryTracker tracker) {
        impl = scoped!Impl(id, tracker);
    }

    @disable this(this);
    
    @trusted MemoryScope acquire_scope(string name) {
        return impl.tracker._acquire_scope(scope_id, name);
    }

    typeof(scoped!Impl(ScopeId(), null)) impl;
    alias impl this;
}

private:

enum scope_handle_name = "MemoryTracker::TrackedScope";

struct TrackedScope {
    const(char)[] name;
    ScopeId parent;

    HashTable!(TrackedAllocation, TrackedAllocation.hash) allocations;
}

struct TrackedType {
    string name;
    uint size;
    uint num_allocated;

    static assert(typeof(this).sizeof == 24);

    static @safe hash(ref TrackedType tt) nothrow {
        return Hash32.of(&tt.name[0]);
    }
}

struct TrackedAllocation {
    void* pointer;
    Hash32 type_id;
    ScopeId scope_id;

    mixin(bitfields!(
        uint, "array_length", 31,
        bool, "is_array", 1,
    ));

    mixin pad_bytes!4;

    static assert(typeof(this).sizeof == 24);

    static @safe hash(ref TrackedAllocation a) nothrow {
        return Hash32.of(a.pointer);
    }
}
