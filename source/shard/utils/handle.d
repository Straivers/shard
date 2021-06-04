module shard.utils.handle;

import shard.memory.allocators.api : IAllocator;
import shard.memory.tracker: TrackedAllocator;
import shard.traits : bits_to_store;
import std.bitmanip : taggedPointer, bitfields;

/**
A `HandlePool` allocates up to `capacity` unique, non-repeating handles. These
handles may be used to uniquely identify non-owned resources, and may be
invalidated when the resource expires.

To facilitate the association of these handles with backing resources, the
`HandlePool` provides an `index_of(handle)` method that returns a non-unique
unsigned integer in the range [0, capacity).
*/
struct HandlePool {
    struct Handle {
        uint value;

        bool opCast(T: bool)() const {
            return value > 0;
        }
    }

    this(size_t capacity, ref IAllocator allocator) {
        assert(capacity < (1 << 31), "Specified capacity greater than 2 ^ 31 element limit");
        _allocator.api = &allocator;
        this(allocator.make_array!Handle(capacity));
    }

    this(size_t capacity, ref TrackedAllocator allocator) {
        assert(capacity < (1 << 31), "Specified capacity greater than 2 ^ 31 element limit");
        _is_tracked = true;
        _allocator.tracked = &allocator;
        this(allocator.make_array!Handle(capacity));
    }

    this(Handle[] handles) {
        assert(handles.length < (1 << 31), "Specified capacity greater than 2 ^ 31 element limit");
        _handles = handles.ptr;
        _num_handles = cast(uint) handles.length;
        _value_mask = (1 << bits_to_store(_num_handles - 1)) - 1;

        _freelist_length = _num_handles;
        foreach_reverse(i, ref handle; _handles[0 .. _num_handles]) {
            _set_index(handle.value, _freelist);
            _freelist = cast(uint) i;
        }
    }

    ~this() {
        if (_allocator) {
            if (_is_tracked)
                _allocator.tracked.dispose(_handles);
            else
                _allocator.api.dispose(_handles);
        }
    }

    /**
    Checks if the handle is valid.
    */
    bool is_valid(Handle handle) {
        const index = _get_index(handle.value);
        
        return index < _num_handles && _get_generation(_handles[index].value) == _get_generation(handle.value);
    }

    /**
    Computes a non-unique unsigned integer associated with the handle.

    Params:
        handle = The handle to query

    Returns: An index in the range [0, capacity).
    */
    uint index_of(Handle handle) {
        return _get_index(handle.value);
    }

    /**
    Allocates a new handle.

    */
    Handle allocate() {
        /*
        Problem:
         - Handle allocation can fail, but there's no way to easily indicate a
           failed allocation. Asserting that there are always handle available
           is a bad idea, and std.variant is not betterC compatible.
        
        Solution:
         - Reserve Handle() for an invalid handle.
            - We assert that there will never be more than 2 billion handles (8 gib of memory)
            - At 2 billion handles, 31 bits are consumed by the index
                - 1 bit is reserved for generation
                - Handle 0 can be used only once, all other indices can be used twice
        */

        assert(0, "unimplemented");
    }

    void deallocate(Handle handle) {
        assert(0);
    }

private:
    uint _get_index(uint value) {
        return value & _value_mask;
    }

    void _set_index(ref uint value, uint index) {
        value = (value & ~_value_mask) | index;
    }

    uint _get_generation(uint value) {
        const generation_in_place = value & ~_value_mask;
        return generation_in_place >> bits_to_store(_value_mask);
    }

    void _increment_generation(ref uint value) {
        const generation = _get_generation(value) + 1;
        // This wraps generation if it gets too large to fit!
        value = (generation << bits_to_store(_value_mask)) | (value & _value_mask);
    }

    union Allocator {
        IAllocator* api;
        TrackedAllocator* tracked;
    }

    Handle* _handles;

    mixin(taggedPointer!(
        Allocator*, "_allocator",
        bool, "_is_tracked", 1
    ));

    uint _num_handles;
    uint _value_mask;
    uint _freelist;
    uint _freelist_length;

    static assert(typeof(this).sizeof == 32);
}

@("HandlePool: bit manipulation") unittest {
    {
        HandlePool pool1;
        pool1._num_handles = 4096;
        pool1._value_mask = (1 << bits_to_store(pool1._num_handles - 1)) - 1;
        assert(pool1._value_mask == 0xFFF);

        const h1 = () {
            uint v;
            pool1._set_index(v, 100);
            foreach (i; 0 .. 100)
                pool1._increment_generation(v);
            return v;
        } ();

        assert(pool1._get_index(h1) == 100);
        assert(pool1._get_generation(h1) == 100);

        const h2 = () {
            uint v;
            pool1._set_index(v, 4095);
            pool1._increment_generation(v);
            return v;
        } ();

        assert(pool1._get_index(h2) == 4095);
        assert(pool1._get_generation(h2) == 1);
    }
    {
        HandlePool pool2;
        pool2._num_handles = 1 << 31;
        pool2._value_mask = (1 << bits_to_store(pool2._num_handles - 1)) - 1;
        assert(pool2._value_mask == uint.max >> 1);

        auto h1 = () {
            uint v;
            pool2._set_index(v, 0);
            pool2._increment_generation(v);
            return v;
        } ();

        assert(pool2._get_generation(h1) == 1);
        pool2._increment_generation(h1);
        assert(pool2._get_generation(h1) == 0);
    }
}

// alias Handle4k = Handle!12;

// 0b1111
// static assert(Handle!12._index_bitmask == 0xF);
// static assert(Handle!1_000_000._index_bitmask == 0xFFFFF);

// struct Handle(uint max_instances) {
//     alias IndexType = uint;

//     enum max_index = _index_bitmask;
//     enum max_tracks = (_track_bitmask >> _index_bits) - 1;

//     IndexType index() const {
//         return _value & _index_bitmask;
//     }

//     IndexType track() const {
//         return _value >> _index_bits;
//     }

// private:
//     enum IndexType _index_bits = bits_to_store(max_instances);

//     enum IndexType _index_bitmask = (1 << _index_bits) - 1;
//     enum IndexType _track_bitmask = ~_index_bitmask;

//     void index(IndexType value) {
//         _value = (_value & _track_bitmask) | value;
//     }

//     void track(IndexType value) {
//         _value = (value << _index_bits) | _value;
//     }

//     IndexType _value;
// }

// alias H = HandlePool!32;

// struct HandlePool(uint max_handles) {
//     alias handle_t = Handle!max_handles;

//     this(handle_t[] handles) {
//         _handles = handles;
//         _num_free_handles = num_handles();

//         _freelist = handle_t.max_index;
//         foreach (i, ref handle; _handles[0 .. _num_free_handles]) {
//             handle.index = _freelist;
//             _freelist = cast(handle_t.IndexType) i;
//         }
//     }

//     /// The maximum number of handles this handle pool can hold
//     uint num_handles() {
//         return cast(uint) min(max_handles, _handles.length);
//     }

//     bool is_valid(handle_t handle) {
//         // we only care that the track values match
//         const generation_ok = _handles[handle.index].track == handle.track;
//         assert(generation_ok || _handles[handle.index].index == 0);
//         return generation_ok;
//     }

//     handle_t allocate_handle() {
//         assert(_num_free_handles);

//         const handle_index = _freelist;

//         auto handle = _handles[handle_index];
//         _freelist = handle.index;
//         _num_free_handles--;

//         handle.index = handle_index;
//         return handle;
//     }

//     void deallocate_handle(handle_t handle) {
//         assert(is_valid(handle));

//         const handle_index = handle.index;

//         // If the handle's generation hasn't been saturated yet, add it back to
//         // the freelist
//         if (_handles[handle_index].track < handle_t.max_tracks) {
//             _handles[handle_index].index = _freelist;
//             _freelist = handle_index;

//             _num_free_handles++;
//         }

//         // Invalidate the handle
//         _handles[handle_index].track = _handles[handle_index].track + 1;
//     }

// private:
//     uint _freelist;
//     uint _num_free_handles;

//     handle_t[] _handles;
// }
