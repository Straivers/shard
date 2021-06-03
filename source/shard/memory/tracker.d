module shard.memory.tracker;

import shard.hash : Hash32;
import shard.memory.allocators.api : IAllocator;
import shard.memory.allocators.system : SystemAllocator;
import shard.traits : PtrType, object_size;
import shard.utils.table : HashTable;
import std.bitmanip : bitfields;
import std.traits : fullyQualifiedName;

alias ScopeId = uint;
/*
struct AllocationTracker {
    TrackedAllocator* sys_allocator() {
        assert(0);
    }

    void register_allocation(T)(ScopeId tracking_scope, PtrType!T p) nothrow {
        const type_id = init_or_update_tracked_type!T();
        // _scopes.get(tracking_scope).allocations.insert(p, TrackedAllocation(type_id));
    }

    void register_deallocation(ScopeId tracking_scope, void[] p) nothrow {
        // auto tracked = _scopes.get(tracking_scope).allocations.get_and_remove(p.ptr);
        // _tracked_types.get(tracked.type_name).num_allocated--;
    }

    void register_array_allocation(T)(ScopeId tracking_scope, T[] a) nothrow {
        const type_id = init_or_update_tracked_type!T();
        // auto tracked = _scopes.get(tracking_scope).allocations.insert(a.ptr, TrackedAllocation(type_id));
        // tracked.is_array = true;
        // tracked.array_length = cast(uint) a.length;
    }

    void register_array_deallocation(T)(ScopeId tracking_scope, T[] a) nothrow {
        // auto tracked = _scopes.get(tracking_scope).allocations.get_and_remove(a.ptr);
        // _tracked_types.get(tracked.type_name).num_allocated -= a.length;
    }

    void register_array_reallocation(T)(ScopeId tracking_scope,
            void* old_location, size_t old_length, T[] a) nothrow {
        // auto tracked = _scopes.get(tracking_scope).allocations.get_and_remove(old_location);
        // _tracked_types.get(tracked.type_name).num_allocated += a.length - old_length;
        // tracked.array_length = a.length;
        // _scopes.get(tracking_scope).allocations.insert(a.ptr, tracked);
    }

private:
    struct TrackingScope {
        ScopeId parent_scope;
        const(char)[] name;
        HashTable!(TrackedAllocation, TrackedAllocation.hash) allocations;
    }

    struct TrackedType {
        immutable(char)* name;
        ushort name_length;
        ushort size;
        uint num_allocated;

        static assert(TrackedType.sizeof == 16);

        pragma(inline, true) static create(T)() nothrow {
            enum t_name = fullyQualifiedName!T;
            return TrackedType(t_name.ptr, cast(ushort) t_name.length, object_size!T, 0);
        }

        pragma(inline, true) static Hash32 hash(ref TrackedType tt) nothrow {
            return Hash32.of(tt.name);
        }
    }

    struct TrackedAllocation {
        void* pointer;
        Hash32 tracked_type_name;
        // dfmt off
        mixin(bitfields!(
            bool, "is_array", 1,
            uint, "array_length", 31,
        ));
        // dfmt on
        static assert(TrackedAllocation.sizeof == 16);

        pragma(inline, true) static Hash32 hash(ref TrackedAllocation ta) nothrow {
            return Hash32.of(ta.pointer);
        }
    }

    Hash32 init_or_update_tracked_type(T)() nothrow {
        enum t_name = fullyQualifiedName!T;
        const type_id = Hash32.of(t_name.ptr);
        auto tt = _tracked_types.get_or_insert(type_id,
                TrackedType.create!T(), _system.allocator_api());
        tt.num_allocated++;
        return type_id;
    }

    SystemAllocator _system;
    // HandlePool!TrackingScope _scopes;
    HashTable!(TrackedType, TrackedType.hash) _tracked_types;
}

struct TrackedAllocator {
    this(IAllocator* base, AllocationTracker* tracker) {
        _base = base;
        _tracker = tracker;
        _allocator_api = IAllocator(&this, &allocator_api_alignment, null,
                &allocator_api_allocate, &allocator_api_deallocate, &allocator_api_reallocate);
    }

    @disable this(this);

    ~this() {

    }

    ref IAllocator allocator_api() nothrow return {
        return _allocator_api;
    }

    PtrType!T make(T, Args...)(auto ref Args args) nothrow {
        auto p = _base.make!T(args);
        if (p)
            _tracker.register_allocation(0, memory);
        return p;
    }

    T[] make_array(T)(size_t length) nothrow {
        auto a = _base.make_array!T(length);
        if (a)
            _tracker.register_array_allocation(0, a);
        return a;
    }

    T[] make_raw_array(T)(size_t length) nothrow {
        auto a = _base.make_raw_array!T(length);
        if (a)
            _tracker.register_array_allocation(0, a);
        return a;
    }

    void dispose(T)(auto ref T* p) nothrow {
        _base.dispose(p);
        _tracker.register_deallocation(0, p);
    }

    void dispose(T)(auto ref T p) nothrow if (is(T == class) || is(T == interface)) {
        _base.dispose(p);
        _tracker.register_deallocation(0, p);
    }

    void dispose(T)(auto ref T[] p) nothrow {
        _base.dispose(p);
        _tracker.register_array_deallocation(0, p);
    }

    bool resize_array(T)(ref T[] array, size_t length) nothrow {
        assert(0);
    }

    TrackedAllocator* create_child() {
        assert(0);
    }

    void destroy_child(TrackedAllocator* child, size_t max_leaked_bytes = 0) {
        assert(0);
    }

private:
    static size_t allocator_api_alignment(const void* self) nothrow {
        return (cast(TrackedAllocator*) self)._base.alignment();
    }

    static void[] allocator_api_allocate(void* self, size_t size) nothrow {
        return (cast(TrackedAllocator*) self).make_raw_array!(void[])(size);
    }

    static void allocator_api_deallocate(void* self, void[] memory) nothrow {
        return (cast(TrackedAllocator*) self).dispose(memory);
    }

    static bool allocator_api_reallocate(void* self, ref void[] memory, size_t new_size) nothrow {
        return (cast(TrackedAllocator*) self).resize_array(memory, new_size);
    }

    IAllocator* _base;
    IAllocator _allocator_api;

    ScopeId _tracker_scope;
    AllocationTracker* _tracker;
}
*/