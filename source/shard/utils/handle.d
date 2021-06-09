module shard.utils.handle;

import shard.memory.allocators.api : Allocator;
// import shard.memory.tracker : TrackedAllocator;
import shard.traits : bits_to_store;
import std.bitmanip : taggedPointer;
import std.traits : hasElaborateDestructor;

/**
A `HandlePool` allocates up to `capacity` unique, non-repeating handles. These
handles may be used to uniquely identify non-owned resources, and may be
invalidated when the resource expires.

To facilitate the association of these handles with backing resources, the
`HandlePool` provides an `index_of(handle)` method that returns a non-unique
unsigned integer in the range [0, capacity).
*/
struct HandlePool(string name, Value = void) {
    enum has_value = !is(Value == void);

    struct Handle {
        uint value;

        bool opCast(T : bool)() const nothrow {
            return value > 0;
        }
    }

    static if (has_value)
        struct Slot {
            Handle handle;
            Value value;

            alias handle this;
        }
    else
        alias Slot = Handle;

    this(Slot[] slots) nothrow {
        slots[] = Slot();
        _init_slots(slots);
    }

    /**
    Checks if the handle is valid.
    */
    @trusted bool is_valid(Handle handle) nothrow {
        const index = _get_index(handle);

        return index < _num_slots && _get_generation(_slots[index]) == _get_generation(handle);
    }

    /**
    Computes a non-unique unsigned integer associated with the handle.

    Params:
        handle = The handle to query

    Returns: An index in the range [0, capacity).
    */
    @safe uint index_of(Handle handle) nothrow {
        assert(is_valid(handle));
        return _get_index(handle);
    }

    static if (has_value) {
        @safe ref Value value_of(Handle handle) nothrow {
            assert(is_valid(handle));
            return _slot(_get_index(handle)).value;
        }
    }

    /**
    Allocates a new handle.

    Returns: A new opaque handle, or else Handle(0) if the pool has run out of
    handles.
    */
    @safe Handle allocate() nothrow {
        if (_freelist_length) {
            const index = _freelist;
            _freelist = _get_index(_slot(index));
            _freelist_length--;
            return Handle(_get_generation_bits(_slot(index)) | index);
        }

        return Handle();
    }

    /**
    Deallocates a valid handle, and invalidating it for the lifetime of the
    handle pool.
    */
    @safe void deallocate(Handle handle) nothrow {
        assert(is_valid(handle));

        const index = _get_index(handle);
        if (_increment_generation(_slot(index)) != ~_value_mask) {
            _set_index(_slot(index), _freelist);
            _freelist = index;
            _freelist_length++;
        }

        static if (has_value && hasElaborateDestructor!Value)
            destroy(_slot(index).value);
    }

@safe private:
    void _init_slots(Slot[] slots) nothrow {
        assert(slots.length < (1 << 31), "Specified capacity greater than 2 ^ 31 element limit");

        _slots = (() @trusted => slots.ptr)();
        _num_slots = cast(uint) slots.length;
        _value_mask = (1 << bits_to_store(_num_slots - 1)) - 1;

        _freelist_length = _num_slots;
        foreach_reverse (i, ref handle; slots) {
            _set_index(handle, _freelist);
            _freelist = cast(uint) i;
        }

        _increment_generation(_slots[0]);
    }

    @trusted ref Slot _slot(uint index) {
        assert(index < _num_slots);
        return _slots[index];
    }

    uint _get_index(Handle handle) nothrow {
        return handle.value & _value_mask;
    }

    void _set_index(ref Handle handle, uint index) nothrow {
        handle.value = (handle.value & ~_value_mask) | index;
    }

    uint _get_generation_bits(Handle handle) nothrow {
        return handle.value & ~_value_mask;
    }

    uint _get_generation(Handle handle) nothrow {
        return _get_generation_bits(handle) >> bits_to_store(_value_mask);
    }

    uint _increment_generation(ref Handle handle) nothrow {
        const generation = (_get_generation(handle) + 1) << bits_to_store(_value_mask);
        // This wraps generation if it gets too large to fit!
        handle.value = generation | (handle.value & _value_mask);
        return generation;
    }

    Slot* _slots;

    uint _num_slots;
    uint _value_mask;
    uint _freelist;
    uint _freelist_length;

    static assert(typeof(this).sizeof == 24);
}

@("HandlePool: bit manipulation") unittest {
    alias Pool = HandlePool!"Unittest";
    alias Handle = Pool.Handle;

    {
        Pool pool1;

        pool1._num_slots = 4096;
        pool1._value_mask = (1 << bits_to_store(pool1._num_slots - 1)) - 1;
        assert(pool1._value_mask == 0xFFF);

        const h1 = () {
            Handle v;
            pool1._set_index(v, 100);
            foreach (i; 0 .. 100)
                pool1._increment_generation(v);
            return v;
        }();

        assert(pool1._get_index(h1) == 100);
        assert(pool1._get_generation(h1) == 100);

        const h2 = () {
            Handle v;
            pool1._set_index(v, 4095);
            pool1._increment_generation(v);
            return v;
        }();

        assert(pool1._get_index(h2) == 4095);
        assert(pool1._get_generation(h2) == 1);
    }
    {
        Pool pool2;
        pool2._num_slots = 1 << 31;
        pool2._value_mask = (1 << bits_to_store(pool2._num_slots - 1)) - 1;
        assert(pool2._value_mask == uint.max >> 1);

        auto h1 = () {
            Handle v;
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
    alias Pool = HandlePool!"Unittest";
    alias Handle = Pool.Handle;

    Handle[32] handles;
    auto pool = Pool(handles);

    Handle[32] test_handles;

    { // Fully allocate the pool
        foreach (i, ref v; test_handles) {
            v = pool.allocate();
            assert(pool.is_valid(v));
            assert(pool.index_of(v) == i);
        }

        // HandlePool.allocate() fails as expected
        assert(pool.allocate() == Handle());
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
