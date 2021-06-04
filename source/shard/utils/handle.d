module shard.utils.handle;

import shard.memory.allocators.api : IAllocator;
import shard.memory.tracker : TrackedAllocator;
import shard.traits : bits_to_store;
import std.bitmanip : taggedPointer;

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

        bool opCast(T : bool)() const {
            return value > 0;
        }
    }

    this(size_t capacity, ref IAllocator allocator) {
        assert(capacity < (1 << 31), "Specified capacity greater than 2 ^ 31 element limit");
        _allocator.api = &allocator;
        _init_handles(allocator.make_array!Handle(capacity));
    }

    this(size_t capacity, ref TrackedAllocator allocator) {
        assert(capacity < (1 << 31), "Specified capacity greater than 2 ^ 31 element limit");
        _is_tracked = true;
        _allocator.tracked = &allocator;
        _init_handles(allocator.make_array!Handle(capacity));
    }

    this(Handle[] handles) {
        assert(handles.length < (1 << 31), "Specified capacity greater than 2 ^ 31 element limit");
        handles[] = Handle();
        _init_handles(handles);
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
        const index = _get_index(handle);

        return index < _num_handles && _get_generation(_handles[index]) == _get_generation(handle);
    }

    /**
    Computes a non-unique unsigned integer associated with the handle.

    Params:
        handle = The handle to query

    Returns: An index in the range [0, capacity).
    */
    uint index_of(Handle handle) {
        assert(is_valid(handle));
        return _get_index(handle);
    }

    /**
    Allocates a new handle.

    Returns: A new opaque handle, or else Handle(0) if the pool has run out of
    handles.
    */
    Handle allocate() {
        if (_freelist_length) {
            const index = _freelist;
            _freelist = _get_index(_handles[index]);
            _freelist_length--;
            return Handle(_get_generation_bits(_handles[index]) | index);
        }

        return Handle();
    }

    /**
    Deallocates a valid handle, and invalidating it for the lifetime of the
    handle pool.
    */
    void deallocate(Handle handle) {
        assert(is_valid(handle));

        const index = _get_index(handle);
        if (_increment_generation(_handles[index]) != ~_value_mask) {
            _set_index(_handles[index], _freelist);
            _freelist = index;
            _freelist_length++;
        }
    }

private:
    void _init_handles(Handle[] handles) {
        _handles = handles.ptr;
        _num_handles = cast(uint) handles.length;
        _value_mask = (1 << bits_to_store(_num_handles - 1)) - 1;

        _freelist_length = _num_handles;
        foreach_reverse (i, ref handle; _handles[0 .. _num_handles]) {
            _set_index(handle, _freelist);
            _freelist = cast(uint) i;
        }

        _increment_generation(_handles[0]);

    }

    uint _get_index(Handle handle) {
        return handle.value & _value_mask;
    }

    void _set_index(ref Handle handle, uint index) {
        handle.value = (handle.value & ~_value_mask) | index;
    }

    uint _get_generation_bits(Handle handle) {
        return handle.value & ~_value_mask;
    }

    uint _get_generation(Handle handle) {
        return _get_generation_bits(handle) >> bits_to_store(_value_mask);
    }

    uint _increment_generation(ref Handle handle) {
        const generation = (_get_generation(handle) + 1) << bits_to_store(_value_mask);
        // This wraps generation if it gets too large to fit!
        handle.value = generation | (handle.value & _value_mask);
        return generation;
    }

    union Allocator {
        IAllocator* api;
        TrackedAllocator* tracked;
    }

    Handle* _handles;

    mixin(taggedPointer!(Allocator*, "_allocator", bool, "_is_tracked", 1));

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
            HandlePool.Handle v;
            pool1._set_index(v, 100);
            foreach (i; 0 .. 100)
                pool1._increment_generation(v);
            return v;
        }();

        assert(pool1._get_index(h1) == 100);
        assert(pool1._get_generation(h1) == 100);

        const h2 = () {
            HandlePool.Handle v;
            pool1._set_index(v, 4095);
            pool1._increment_generation(v);
            return v;
        }();

        assert(pool1._get_index(h2) == 4095);
        assert(pool1._get_generation(h2) == 1);
    }
    {
        HandlePool pool2;
        pool2._num_handles = 1 << 31;
        pool2._value_mask = (1 << bits_to_store(pool2._num_handles - 1)) - 1;
        assert(pool2._value_mask == uint.max >> 1);

        auto h1 = () {
            HandlePool.Handle v;
            pool2._set_index(v, 0);
            pool2._increment_generation(v);
            return v;
        }();

        assert(pool2._get_generation(h1) == 1);
        pool2._increment_generation(h1);
        assert(pool2._get_generation(h1) == 0);
    }
}

@("HandlePool: allocate(), deallocate()") unittest {
    HandlePool.Handle[32] handles;
    auto pool = HandlePool(handles);

    HandlePool.Handle[32] test_handles;

    { // Fully allocate the pool
        foreach (i, ref v; test_handles) {
            v = pool.allocate();
            assert(pool.is_valid(v));
            assert(pool.index_of(v) == i);
        }

        // HandlePool.allocate() fails as expected
        assert(pool.allocate() == HandlePool.Handle());
    }

    { // Allocated handles are invalidated successfully
        foreach (ref v; test_handles[]) {
            pool.deallocate(v);
            assert(!pool.is_valid(v));
        }
    }

    { // The full span of handles can be allocated again
        foreach (i, ref v; test_handles) {
            v = pool.allocate();
            assert(pool.is_valid(v));
            assert(pool.index_of(v) == test_handles.length - i - 1);
        }
    }
}
