module shard.memory.arena;

import shard.memory.allocator;
import shard.memory.common;

struct Arena {
public nothrow:
    this(Allocator allocator, size_t size, size_t alignment = default_alignment) {
        _base_allocator = allocator;
        _impl = UnmanagedArena(_base_allocator.allocate(size), alignment);
    }

    ~this() {
        if (_base_allocator)
            _base_allocator.deallocate(range_start[0 .. range_end - range_start]);
    }

    // dfmt off
    size_t alignment() const { return _impl.alignment(); }

    Ternary owns(void[] memory) const { return _impl.owns(memory); }

    void* range_start() { return _impl.range_start(); }

    void* range_end() { return _impl.range_end(); }

    size_t bytes_allocated() { return _impl.bytes_allocated(); }

    size_t bytes_available() { return _impl.bytes_available(); }
    // dfmt on

    size_t get_optimal_alloc_size(size_t size) const {
        return _impl.get_optimal_alloc_size(size);
    }

    void[] allocate(size_t size) {
        return _impl.allocate(size);
    }

    bool deallocate(ref void[] memory) {
        return _impl.deallocate(memory);
    }

    bool resize(ref void[] memory, size_t size) {
        return _impl.resize(memory, size);
    }

    bool reallocate(ref void[] memory, size_t new_size) {
        return _impl.reallocate(memory, new_size);
    }

private:
    Allocator _base_allocator;
    UnmanagedArena _impl;
}

struct UnmanagedArena {
    public nothrow:
    this(void[] memory, size_t alignment = default_alignment) {
        _start = align_pointer(memory.ptr, alignment);
        _alignment = alignment;

        _top = _start;
        _end = _start + memory.length;
    }

    @disable this(this);

    size_t alignment() const {
        return _alignment;
    }

    Ternary owns(void[] memory) const {
        return Ternary(memory == [] || memory.is_sub_slice_of(_start[0 .. _top - _start]));
    }

    void* range_start() {
        return _start;
    }

    void* range_end() {
        return _end;
    }

    size_t bytes_allocated() {
        assert(_top >= _start);
        return _top - _start;
    }

    size_t bytes_available() {
        return _end - _top;
    }

    size_t get_optimal_alloc_size(size_t size) const {
        return round_to_next(size, alignment);
    }

    void[] allocate(size_t size) {
        const alloc_size = get_optimal_alloc_size(size);

        if (alloc_size > 0 && _top + alloc_size <= _end) {
            auto mem = _top[0 .. size];
            _top += alloc_size;
            return mem;
        }

        return [];
    }

    bool deallocate(ref void[] memory)
    in (owns(memory) == Ternary.yes) {
        if (memory is null)
            return true;

        const alloc_size = get_optimal_alloc_size(memory.length);

        if (memory.ptr + alloc_size == _top) {
            _top -= alloc_size;
            memory = null;
            return true;
        }

        return false;
    }

    bool resize(ref void[] memory, size_t size)
    in (owns(memory) == Ternary.yes) {
        if (memory == null || size == 0)
            return false;

        const requested_size = get_optimal_alloc_size(size);
        const current_size = get_optimal_alloc_size(memory.length);

        // If the new size fits in the old allocation
        if (requested_size <= current_size) {
            memory = memory.ptr[0 .. size];
            return true;
        }

        if ((_top == memory.ptr + current_size) && (memory.ptr + requested_size) <= _end) {
            _top = memory.ptr + requested_size;
            memory = memory.ptr[0 .. size];
            return true;
        }

        return false;
    }

    bool reallocate(ref void[] memory, size_t new_size)
    in (owns(memory) == Ternary.yes) {
        if (new_size == 0 && deallocate(memory)) {
            memory = null;
            return true;
        }

        if (resize(memory, new_size))
            return true;

        if (auto new_memory = allocate(new_size)) {
            new_memory[0 .. memory.length] = memory;
            memory = new_memory;
            return true;
        }

        return false;
    }

private:
    size_t _alignment;
    void* _top, _start, _end;
}

unittest {
    import shard.memory.allocator: test_allocate_api, test_reallocate_api, test_resize_api;

    auto arena = UnmanagedArena(new void[](4 * 1024));

    test_allocate_api(arena);
    test_reallocate_api(arena);
    test_resize_api!true(arena);

    {
        // Fixed-order deallocation
        auto m1 = arena.allocate(10);
        auto m2 = arena.allocate(20);
        auto m3 = arena.allocate(30);

        assert(!arena.deallocate(m1));
        assert(!arena.deallocate(m2));

        assert(arena.deallocate(m3));
        assert(!arena.deallocate(m1));
        
        assert(arena.deallocate(m2));
        assert(arena.deallocate(m1));
    }
}
