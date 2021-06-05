module shard.utils.array;

import shard.memory.allocators.api : Allocator;
import std.algorithm : move;

struct Array(T) {
    enum default_initial_size = 8;

nothrow public:
    this(Allocator allocator, size_t initial_size = default_initial_size) {
        _allocator = allocator;
        _impl = UnmanagedArray!T(allocator, initial_size);
    }

    @disable this(this);

    ~this() {
        if (_allocator)
            _impl.free(_allocator);
    }

    void unwrap(T)(out UnmanagedArray!T dest) {
        dest = move(_impl);
        assert(_impl == UnmanagedArray!T());
    }

    size_t length() const { return _impl.length(); }

    size_t capacity() const { return _impl.capacity(); }

    void clear() { _impl.clear(); }

    void reserve(size_t min_size) { _impl.reserve(_allocator, min_size); }

    void reserve_extra(size_t extra) { _impl.reserve_extra(_allocator, extra); }

    size_t push_back()(auto ref T value) { return _impl.push_back(_allocator, value); }

    size_t push_back(T[] values...) { return _impl.push_back(_allocator, values); }

    T pop_back() { return _impl.pop_back(); }

    ref inout(T) opIndex(size_t index) inout { return _impl.opIndex(index); }

    inout(T[]) opIndex() inout { return _impl.opIndex(); }

private:
    Allocator _allocator;
    UnmanagedArray!T _impl;

    static assert(Array!T.sizeof == 24);
}

unittest {
    import shard.memory.allocators.system : SystemAllocator;

    scope mem = new SystemAllocator();
    auto arr = Array!int(mem);

    foreach (i; 0 .. 512)
        arr.push_back(i);
    assert(arr.length == 512);

    foreach (i; 0 .. 512)
        assert(arr[i] == i);

    foreach_reverse (i; 0 .. 512) {
        assert(arr.pop_back() == i);
        assert(arr.length == i);
    }
}

unittest {
    import shard.memory.allocators.system : SystemAllocator;

    struct Foo {
        int value;
        @disable this(this);
    }

    scope mem = new SystemAllocator();
    auto arr = Array!Foo(mem);

    foreach (i; 0 .. 512) {
        auto foo = Foo(i);
        arr.push_back(foo);
    }
    assert(arr.length == 512);

    foreach (i; 0 .. 512)
        assert(arr[i].value == i);

    foreach_reverse (i; 0 .. 512) {
        assert(arr.pop_back().value == i);
        assert(arr.length == i);
    }
}

struct UnmanagedArray(T) {
    enum default_initial_size = 8;

nothrow public:
    this(Allocator allocator, size_t initial_size = default_initial_size) {
        _resize(allocator, initial_size);
    }

    @disable this(this);

    ~this() {
        assert(_p is null,
            "Unmanaged array was not freed before destruction. call free(Allocator) before destroying.");
    }

    void free(Allocator allocator) {
        allocator.dispose(_p[0 .. _capacity]);
        _p = null;
    }

    size_t length() const {
        return _length;
    }

    size_t capacity() const {
        return _capacity;
    }

    void clear() {
        _length = 0;
    }

    void reserve(Allocator allocator, size_t min_size) {
        if (_capacity < min_size) {
            _resize(allocator, min_size);
        }
    }

    void reserve_extra(Allocator allocator, size_t extra) {
        while (_capacity < _length + extra)
            _grow(allocator);
    }

    size_t push_back()(Allocator allocator, auto ref T value) {
        if (_length == _capacity)
            _grow(allocator);

        const index = _length;
        _p[_length] = move(value);
        _length++;
        return index;
    }

    size_t push_back(Allocator allocator, T[] values...) {
        while (_length + values.length > _capacity)
            _grow(allocator);

        const first = _length;
        static if (is(typeof(_p[] = values)))
            _p[_length .. _length + values.length] = values;
        else
            foreach (i, ref v; values)
                _p[_length + i] = move(v);

        _length += values.length;
        return first;
    }

    T pop_back() {
        assert(_length > 0);

        scope (exit)
            _length--;

        return move(_p[_length - 1]);
    }

    ref inout(T) opIndex(size_t index) inout in (index < length) {
        return _p[index];
    }

    inout(T[]) opIndex() inout {
        return _p[0 .. _length];
    }

private:
    void _grow(Allocator allocator) {
        // If array was constructed with initial_size == 0.
        if (_capacity == 0) {
            assert(default_initial_size < _capacity.max);
            auto arr = allocator.make_array!T(default_initial_size);
            assert(arr, "Out of memory! Array could not be expanded");
            _p = &arr[0];
            _capacity = cast(uint) arr.length;
        }
        else
            _resize(allocator, _capacity * 2);
    }

    void _resize(Allocator allocator, size_t size) {
        assert(size < uint.max, "Array max length = uint.max");

        auto arr = _p[0 .. _capacity];
        if (!allocator.resize_array(arr, cast(uint) size))
            assert(0, "Out of memory! Array could not be expanded");

        // resize_array() may have reallocated, so get the new pointer
        _p = &arr[0];
        assert(arr.length == size, "Assumption failure.");
        _capacity = cast(uint) arr.length;
    }

    T* _p;
    uint _length;
    uint _capacity;

    static assert(UnmanagedArray!T.sizeof == 16);
}
