module shard.utils.map2;

import core.lifetime : core_emplace = emplace;
import shard.hash : Hash, is_hash;
import shard.math : ilog2, is_power_of_two;
import shard.memory.allocators.api : IAllocator;
import std.algorithm : max, move, swap;
import std.traits : ReturnType, hasElaborateDestructor;

/**
A normal Key-Value hash table with configurable hasher.

Params:
    Key = The value used to index the table.
    Value = The type containing data within the table.
    key_hasher = A callable that produces a hash from a key.

Note:
    If using `HashN.of` functions for hasher, make sure to instantiate the
    type!

    e.g.
    ```
    HashTable!(Hash32, size_t) map;
    ```
*/
struct HashTable(Key, Value, size_t hash_bits = 32, alias key_hasher = Hash!hash_bits.of!Key) {
    alias hash_t = ReturnType!key_hasher;
    static assert(is(hash_t == Hash!hash_bits),
            "key_hasher() must return a of " ~ Hash!hash_bits.stringof ~ " not " ~ (hash_t)
            .stringof);

    size_t size() {
        return _impl.size();
    }

    bool is_empty() {
        return _impl.is_empty();
    }

    bool contains(Key key) {
        return _impl.contains(key_hasher(key));
    }

    void insert(Key key, ref Value value, ref IAllocator allocator) {
        auto pair = Pair(key, move(value));
        _impl.insert(key_hasher(key), pair, allocator);
    }

    void insert(Key key, Value value, ref IAllocator allocator) {
        _impl.insert(key_hasher(key), Pair(key, value), allocator);
    }

    void remove(Key key, ref IAllocator allocator) {
        _impl.remove(key_hasher(key), allocator);
    }

    Value* get(Key key) {
        if (auto pair = _impl.get(key_hasher(key)))
            return &pair.value;
        return null;
    }

private:
    struct Pair {
        Key key;
        Value value;

        pragma(inline, true)
        static hash(ref Pair pair) {
            return key_hasher(pair.key);
        }
    }

    HashSet!(Pair, Pair.hash) _impl;
}

/**
A hash set with configurable hasher. The size of the hash is determined by the
return type of the `value_hasher` template parameter.

Params:
    Value = The type containing data within the table.
    hasher = A callable that produces a hash from a value.

Note:
    If using `HashN.of` functions for the hasher, make sure to instantiate the
    type!

    e.g.
    ```
    HashSet!(size_t, Hash32.of!Hash32) map;
    ```
*/
struct HashSet(Value, alias value_hasher = Hash!32.of!Value) {
    alias hash_t = ReturnType!value_hasher;

    enum max_load_factor = 0.8;

    static assert(is_hash!hash_t, "value_hasher() must return a hash type!");

    @disable this(this);

    size_t size() {
        return _table.num_entries;
    }

    bool is_empty() {
        return _table.num_entries == 0;
    }

    void reset(ref IAllocator allocator) {
        foreach (i, ref value; _table.values) {
            if (_table.has_value(i))
                destroy(value);
        }
        Table.dispose(_table, allocator);
        _table = Table();
    }

    bool contains(hash_t key) {
        return get(key) !is null;
    }

    bool insert(hash_t key, Value value, ref IAllocator allocator) {
        return _insert(&_table, key, value, allocator);
    }

    bool insert(hash_t key, ref Value value, ref IAllocator allocator) {
        return _insert(&_table, key, value, allocator);
    }

    void remove(hash_t key, ref IAllocator allocator) {
        assert(0, "Not implemented");
    }

    Value* get(hash_t key) {
        auto index = _table.index_of(key);
        auto distance = 0;

        for (; _table.distances[index] >= distance; distance++, index++) {
            if (key == value_hasher(_table.values[index]))
                return &_table.values[index];
        }

        return null;
    }

    // private:
    enum smallest_size = 8;

    struct Table {
        /// The slots for values in the table. The length of the table is
        /// `max_entries + max_distance` to simplify code for insert().
        Value[] values;
        byte[] distances;

        /// The maximum number of slots a value can be from the optimum.
        size_t max_distance;
        /// The maximum number of values that can be in the table, considering
        /// maximum load factor.
        size_t max_entries;
        /// The capacity for which the table was created.
        size_t created_capacity;

        /// The number of values in the table.
        size_t num_entries;

        @disable this(this);

        /// Creates a new table with `capacity + ilog2(capacity)` slots. The
        /// extra slots enable search loops to avoid bounds checking by
        /// nature of `index_of`, which provides an index only to `capacity`.
        static bool create(size_t capacity, ref IAllocator allocator, out Table table) {
            const max_distance = ilog2(capacity);
            const real_capacity = (capacity + max_distance);
            const max_entries = cast(size_t)(capacity * max_load_factor);

            auto values = allocator.make_raw_array!Value(real_capacity);
            if (!values)
                return false;
            
            auto distances = allocator.make_raw_array!byte(real_capacity);
            if (!distances)
                return false;
            distances[] = -1;

            table.values = values;
            table.distances = distances;
            table.max_distance = max_distance;
            table.max_entries = max_entries;
            table.created_capacity = capacity;
            table.num_entries = 0;

            return true;
        }

        static void dispose(ref Table table, ref IAllocator allocator) {
            allocator.dispose(table.values);
            allocator.dispose(table.distances);
            table = Table();
        }

        size_t index_of(hash_t hash) {
            // 2 ^ 64 / golden_ratio, rounded up to nearest odd
            enum size_t multiple = 114_00_714_819_323_198_485;

            assert(is_power_of_two(created_capacity));
            return (hash.int_value * multiple) & (created_capacity - 1);
        }

        pragma(inline, true)
        bool has_value(size_t index) {
            return distances[index] >= 0;
        }

        pragma(inline, true)
        bool is_empty(size_t index) {
            return distances[index] == -1;
        }
    }

    static bool _insert(Table* table, hash_t key, ref Value value, ref IAllocator allocator) {
        if (table.num_entries == table.max_entries && !_grow(table, allocator)) {
            return false;
        }

        byte distance = 0;
        size_t insert_point = table.index_of(key);
        for (; table.distances[insert_point] >= distance; distance++, insert_point++) {
            if (value_hasher(table.values[insert_point]) == key) {
                swap(table.values[insert_point], value);

                static if (hasElaborateDestructor!Value)
                    destroy(value);

                return true;
            }
        }

        if (distance > table.max_distance) {
            if (_grow(table, allocator))
                return _insert(table, key, value, allocator);
            return false;
        }

        if (table.is_empty(insert_point)) {
            table.values[insert_point] = move(value);
            table.distances[insert_point] = distance;
            table.num_entries++;
            return true;
        }

        auto swap_value = move(value);
        swap(table.values[insert_point], swap_value);
        swap(table.distances[insert_point], distance);

        distance++;
        insert_point++;
        for (; !table.is_empty(insert_point); distance++, insert_point++) {
            if (distance > table.max_distance) {
                if (!_grow(table, allocator))
                    return false;
                else
                    return _insert(table, value_hasher(swap_value), swap_value, allocator);
            }

            if (table.distances[insert_point] < distance) {
                swap(table.values[insert_point], swap_value);
                swap(table.distances[insert_point], distance);
            }
        }

        table.distances[insert_point] = distance;
        table.values[insert_point] = move(swap_value);
        table.num_entries++;
        return true;
    }

    static bool _grow(Table* table, ref IAllocator allocator) {
        return _rehash(table, max(smallest_size, table.created_capacity * 2), allocator);
    }

    static bool _rehash(Table* table, size_t capacity, ref IAllocator allocator) {
        Table new_table;
        if (!Table.create(capacity, allocator, new_table))
            return false;

        foreach (i, distance; table.distances) {
            if (distance >= 0) {
                _insert(&new_table, value_hasher(table.values[i]), table.values[i], allocator);

                static if (hasElaborateDestructor!Value)
                    destroy(table.values[i]);
            }
        }

        swap(*table, new_table);

        if (new_table.values)
            Table.dispose(new_table, allocator);

        return true;
    }

    Table _table;
}

@("HashSet: colliding inserts") unittest {
    import shard.memory.allocators.system : SystemAllocator;

    HashSet!int set;
    SystemAllocator mem;
    set.insert(Hash!32(3), 100, mem.allocator_api);
    set.insert(Hash!32(11), 200, mem.allocator_api);
    set.insert(Hash!32(19), 300, mem.allocator_api);
    set.insert(Hash!32(27), 400, mem.allocator_api);

    // Colliding slots are correctly inserted past `table.created_capacity`
    assert(set._table.created_capacity == 8);
    assert(set._table.max_distance == 3);

    assert(set._table.values[7] == 100);
    assert(set._table.distances[7] == 0);
    
    assert(set._table.values[8] == 200);
    assert(set._table.distances[8] == 1);
    
    assert(set._table.values[9] == 300);
    assert(set._table.distances[9] == 2);
    
    assert(set._table.values[10] == 400);
    assert(set._table.distances[10] == 3);
}

@("HashSet: insert(), contains(), and get()") unittest {
    import shard.memory.allocators.system : SystemAllocator;
    import std.random : uniform;

    HashSet!(Hash!32) set;
    SystemAllocator mem;

    alias Unit = void[0];
    Unit[Hash!32] hashes;
    while (hashes.length < 1_000)
        hashes[Hash!32(uniform(0, uint.max))] = Unit.init;
    
    foreach (v; hashes.byKey)
        set.insert(v, v, mem.allocator_api());
    
    foreach (v; hashes.byKey) {
        assert(set.contains(v));
        assert(*set.get(v) == v);
    }
}
