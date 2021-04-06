module shard.bit_array;

import shard.memory : Allocator;
import core.stdc.string : memset;

struct BitArray {
    ubyte[] array;

    nothrow:
    this(ubyte[] storage) {
        array = storage;
    }

    /// Returns the number of bytes required to store n bits
    static size_t required_size_for(size_t n_bits) {
        const div = n_bits / 8;
        const rem = n_bits % 8;
        return div + (rem != 0);
    }

    bool opIndex(size_t bit) {
        const byte_index = bit / 8;
        return (array[byte_index] & (1 << (bit % 8))) != 0;
    }

    bool opIndexUnary(string op = "~")(size_t bit) in (bit < array.length * 8) {
        const byte_index = bit / 8;
        array[byte_index] ^= (1 << (bit % 8));
        return this[bit];
    }
}

unittest {
    auto array = BitArray([0]);

    assert(!array[0]);
    ~array[0];
    assert(array[0]);
    assert((array.array[0] & 1) != 0);
    assert((array.array[0] ^ 1) == 0);
    ~array[0];
    assert(!array[0]);

    assert(!array[7]);
    ~array[7];
    assert(array[7]);
    assert((array.array[0] & 1 << 7) != 0);
    assert((array.array[0] ^ 1 << 7) == 0);

    foreach (i; 0 .. 8)
        ~array[i];

    assert(array.array[0] == 127);
}

struct UnmanagedBitArray {
    this(size_t n_bits, Allocator allocator) {
        _storage = allocator.make_array!ubyte(size_for(n_bits));
    }

    void resize(size_t n_bits, Allocator allocator) {
        allocator.resize_array(_storage, size_for(n_bits));
    }

    void clear() {
        memset(_storage.ptr, 0, _storage.length);
    }

    void free(Allocator allocator) {
        allocator.resize_array(_storage, 0);
    }

    static size_t size_for(size_t n_bits) {
        const div = n_bits / 8;
        const rem = n_bits % 8;
        return div + (rem != 0);
    }

    bool get_bit(size_t index) {
        auto loc = coords(index);
        return (*loc.ptr & (1 << loc.bit_id)) != 0;
    }

    bool flip_bit(size_t index) {
        auto loc = coords(index);
        *loc.ptr ^= (1 << loc.bit_id);
        return (*loc.ptr & (1 << loc.bit_id)) != 0;
    }

    void set_bit(size_t index) {
        auto loc = coords(index);
        *loc.ptr |= (1 << loc.bit_id);
    }

    void set_bit(size_t index, bool value) {
        auto loc = coords(index);
        *loc.ptr ^= (-(cast(uint) value) ^ *loc.ptr) & (1 << loc.bit_id); 
    }

    void clear_bit(size_t index) {
        auto loc = coords(index);
        *loc.ptr &= ~(1 << loc.bit_id);
    }

private:
    struct Coords {
        ubyte* ptr;
        size_t bit_id;
    }

    pragma(inline, true)
    Coords coords(size_t i) { return Coords(&_storage[i / 8], i % 8); }

    ubyte[] _storage;
}
