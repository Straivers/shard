module shard.memory.tracker;

import shard.hash : Hash32;
import shard.memory.allocators.api : IAllocator;
import shard.memory.allocators.system : SystemAllocator;
import shard.pad : pad_bytes;
import shard.traits : object_size, PtrType;
import shard.utils.array : UnmanagedArray;
import shard.utils.handle : HandlePool;
import shard.utils.table : HashTable;

import std.algorithm : move, min;
import std.bitmanip : bitfields;
import std.traits : fullyQualifiedName;
/*
alias ScopeId = HandlePool.Handle;

struct MemoryTracker {
    enum default_max_tracking_scopes = 256;

public:
    this(IAllocator root, size_t max_scopes = default_max_tracking_scopes) {
        _root = move(root);
        _scopes = _root.make_array!Scope(max_scopes);
        _handles = _root.make_array!(HandlePool.Handle)(max_scopes);
        _scope_ids = HandlePool(_handles);
    }

    ~this() {
        _name_storage.free(_root);
        _root.dispose(_scopes);
        _root.dispose(_handles);
        _tracked_types.reset(_root);
    }

    void register_allocation(T)(ScopeId scope_id, PtrType!T p) nothrow {
        assert(_scope_ids.is_valid(scope_id));

        const alloc_id = Hash32.of(p);
        assert(!_allocations.contains(alloc_id));

        auto type = _get_type_id!T();
        auto tracking_scope = &_scopes[_scope_ids.index_of(scope_id)];

        type.num_allocations++;
        tracking_scope.num_allocations++;
        _allocations.insert(alloc_id, Allocation(p, type.id), _root);
    }

    void register_deallocation(T)(ScopeId scope_id, PtrType!T p) nothrow {
        assert(_scope_ids.is_valid(scope_id));

        if (!_allocations.remove(Hash32.of(p), _root))
            assert(0, "Double free detected!");

        _get_type_id!T().num_allocations--;
        _scopes[_scope_ids.index_of(scope_id)].num_allocations--;
    }

    void register_array_allocation(T)(ScopeId scope_id, T[] a) nothrow {
        assert(_scope_ids.is_valid(scope_id));
        const type = _get_type_id!T();
        // auto tracked = _scopes.get(scope_id).allocations.insert(a.ptr, Allocation(type_id));
        // tracked.is_array = true;
        // tracked.array_length = cast(uint) a.length;
    }

    void register_array_deallocation(T)(ScopeId scope_id, T[] a) nothrow {
        assert(_scope_ids.is_valid(scope_id));
        // auto tracked = _scopes.get(scope_id).allocations.get_and_remove(a.ptr);
        // _tracked_types.get(tracked.type_name).num_allocated -= a.length;
    }

    void register_array_reallocation(T)(ScopeId scope_id,
            void* old_location, size_t old_length, T[] a) nothrow {
        assert(_scope_ids.is_valid(scope_id));
        // auto tracked = _scopes.get(scope_id).allocations.get_and_remove(old_location);
        // _tracked_types.get(tracked.type_name).num_allocated += a.length - old_length;
        // tracked.array_length = a.length;
        // _scopes.get(scope_id).allocations.insert(a.ptr, tracked);
    }

private:
    static struct Scope {
        static assert(typeof(this).sizeof == 20);

        bool is_in_use;
        mixin pad_bytes!3;

        uint name_offset;
        uint name_length;
        
        uint num_allocations;
        
        ScopeId parent_scope;
    }

    static struct Type {
        static assert(typeof(this).sizeof == 20);

        Hash32 id;

        uint name_offset;
        uint name_length;

        ushort size;
        mixin pad_bytes!2;

        uint num_allocations;

        static Hash32 hash(ref Type tt) nothrow {
            return tt.id;
        }
    }

    static struct Allocation {
        static assert(typeof(this).sizeof == 16);

        void* pointer;
        Hash32 tracking_type;

        // dfmt off
        mixin(bitfields!(
            bool, "is_array", 1,
            uint, "array_length", 31,
        ));
        // dfmt on

        static Hash32 hash(ref Allocation ta) nothrow {
            return Hash32.of(ta.pointer);
        }
    }

    Type* _get_type_id(T)() nothrow {
        enum t_name = fullyQualifiedName!T;
        const type_id = Hash32.of(t_name.ptr);

        if (auto tt = _tracked_types.get(type_id)) {
            return tt;
        }
        else {
            const name_length = cast(typeof(Type.name_length)) t_name.length;
            const name_offset = _name_storage.push_back(_root, cast(char[]) t_name[0 .. name_length]);
            assert(name_offset < Type.name_offset.max, "Name storage too large, max 2 ^ 32 characters!");

            auto type = Type(type_id, cast(typeof(Type.name_offset)) name_offset, name_length, object_size!T);
            return _tracked_types.insert(type_id, type, _root);
        }
    }

    IAllocator _root;

    UnmanagedArray!(char) _name_storage;

    Scope[] _scopes;
    HandlePool _scope_ids;
    HandlePool.Handle[] _handles;

    HashTable!(Type, Type.hash) _tracked_types;
    HashTable!(Allocation, Allocation.hash) _allocations;
}

struct TrackedAllocator {
    this(IAllocator* base, MemoryTracker* tracker) {
        _base = base;
        _tracker = tracker;
    }

    @disable this(this);

    ~this() {

    }

    IAllocator allocator_api() nothrow return {
        // dfmt off
        return IAllocator(
            &this,
            &allocator_api_alignment,
            null,
            &allocator_api_allocate,
            &allocator_api_deallocate,
            &allocator_api_reallocate
        );
        // dfmt on
    }

    PtrType!T make(T, Args...)(auto ref Args args) nothrow {
        auto p = _base.make!T(args);
        if (p)
            _tracker.register_allocation(_tracker_scope, memory);
        return p;
    }

    T[] make_array(T)(size_t length) nothrow {
        auto a = _base.make_array!T(length);
        if (a)
            _tracker.register_array_allocation!T(_tracker_scope, a);
        return a;
    }

    T[] make_raw_array(T)(size_t length) nothrow {
        auto a = _base.make_raw_array!T(length);
        if (a)
            _tracker.register_array_allocation(_tracker_scope, a);
        return a;
    }

    void dispose(T)(auto ref T* p) nothrow {
        _base.dispose(p);
        _tracker.register_deallocation!T(_tracker_scope, p);
    }

    void dispose(T)(auto ref T p) nothrow if (is(T == class) || is(T == interface)) {
        _base.dispose(p);
        _tracker.register_deallocation(_tracker_scope, p);
    }

    void dispose(T)(auto ref T[] p) nothrow {
        _base.dispose(p);
        _tracker.register_array_deallocation(_tracker_scope, p);
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
        return (cast(const typeof(this)*) self)._base.alignment();
    }

    static void[] allocator_api_allocate(void* self, size_t size, string name) nothrow {
        return (cast(typeof(this)*) self).make_array!void(size);
    }

    static void allocator_api_deallocate(void* self, void[] block, string name) nothrow {
        return (cast(typeof(this)*) self).dispose(block);
    }

    static bool allocator_api_reallocate(void* self, ref void[] block, size_t size, size_t count, string name) nothrow {
        return (cast(typeof(this)*) self).resize_array(block, size * count);
    }

    IAllocator* _base;

    ScopeId _tracker_scope;
    mixin pad_bytes!4;

    MemoryTracker* _tracker;
    
    static assert(typeof(this).sizeof == 24);
}
*/