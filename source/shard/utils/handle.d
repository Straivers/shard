module shard.utils.handle;

import std.algorithm : max, min;
import std.traits : hasElaborateDestructor;
import core.lifetime : emplace;

import shard.math : round_to_next;
import shard.memory.allocators.api : IAllocator;
import shard.traits : bits_to_store;

alias Handle4k = Handle!12;

// 0b1111
static assert(Handle!12._index_bitmask == 0xF);
static assert(Handle!1_000_000._index_bitmask == 0xFFFFF);

struct Handle(uint max_instances) {
    alias IndexType = uint;

    enum max_index = _index_bitmask;
    enum max_tracks = (_track_bitmask >> _index_bits) - 1;

    IndexType index() const {
        return _value & _index_bitmask;
    }

    IndexType track() const {
        return _value >> _index_bits;
    }

private:
    enum IndexType _index_bits = bits_to_store(max_instances);

    enum IndexType _index_bitmask = (1 << _index_bits) - 1;
    enum IndexType _track_bitmask = ~_index_bitmask;

    void index(IndexType value) {
        _value = (_value & _track_bitmask) | value;
    }

    void track(IndexType value) {
        _value = (value << _index_bits) | _value;
    }

    IndexType _value;
}

alias H = HandlePool!32;

struct HandlePool(uint max_handles) {
    alias handle_t = Handle!max_handles;

    this(handle_t[] handles) {
        _handles = handles;
        _num_free_handles = num_handles();

        _freelist = handle_t.max_index;
        foreach (i, ref handle; _handles[0 .. _num_free_handles]) {
            handle.index = _freelist;
            _freelist = cast(handle_t.IndexType) i;
        }
    }

    /// The maximum number of handles this handle pool can hold
    uint num_handles() {
        return cast(uint) min(max_handles, _handles.length);
    }

    bool is_valid(handle_t handle) {
        // we only care that the track values match
        const generation_ok = _handles[handle.index].track == handle.track;
        assert(generation_ok || _handles[handle.index].index == 0);
        return generation_ok;
    }

    handle_t allocate_handle() {
        assert(_num_free_handles);

        const handle_index = _freelist;

        auto handle = _handles[handle_index];
        _freelist = handle.index;
        _num_free_handles--;

        handle.index = handle_index;
        return handle;
    }

    void deallocate_handle(handle_t handle) {
        assert(is_valid(handle));

        const handle_index = handle.index;

        // If the handle's generation hasn't been saturated yet, add it back to
        // the freelist
        if (_handles[handle_index].track < handle_t.max_tracks) {
            _handles[handle_index].index = _freelist;
            _freelist = handle_index;

            _num_free_handles++;
        }

        // Invalidate the handle
        _handles[handle_index].track = _handles[handle_index].track + 1;
    }

private:
    uint _freelist;
    uint _num_free_handles;

    handle_t[] _handles;
}
