module shard.utils.map2;

import core.lifetime : core_emplace = emplace;
import shard.hash : Hash, is_hash;
import shard.math : ilog2, is_power_of_two;
import shard.memory.allocators.api : IAllocator;
import std.algorithm : max, move, swap;
import std.traits : ReturnType;

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

    size_t size() {
        return _table.num_entries;
    }

    bool is_empty() {
        return _table.num_entries == 0;
    }

    void reset(ref IAllocator allocator) {
        foreach (ref slot; _table.slots) {
            if (slot.has_value())
                destroy(slot.value);
        }
        allocator.dispose(_table.slots);
        _table = Table();
    }

    bool contains(hash_t key) {
        assert(0, "Not implemented");
    }

    bool insert(hash_t key, Value value, ref IAllocator allocator) {
        return _insert(_table, key, value, allocator);
    }

    bool insert(hash_t key, ref Value value, ref IAllocator allocator) {
        return _insert(_table, key, value, allocator);
    }

    void remove(hash_t key, ref IAllocator allocator) {
        assert(0, "Not implemented");
    }

    Value* get(hash_t key) {
        assert(0, "Not implemented");
    }

    // private:
    enum smallest_size = 8;
    enum min_distance = 4;

    struct Slot {
        Value value;
        byte distance = -1;

        bool has_value() {
            return distance >= 0;
        }

        bool is_empty() {
            return distance == -1;
        }
    }

    struct Table {
        /// The slots for values in the table. The length of the table is
        /// `max_entries + max_distance` to simplify code for insert().
        Slot[] slots;

        /// The maximum number of slots a value can be from the optimum.
        size_t max_distance;
        /// The maximum number of values that can be in the table, considering
        /// maximum load factor.
        size_t max_entries;
        /// The capacity for which the table was created.
        size_t created_capacity;

        /// The number of values in the table.
        size_t num_entries;

        alias slots this;

        /// Creates a new table with `capacity + ilog2(capacity)` slots. The
        /// extra slots enable search loops to avoid bounds checking by
        /// nature of `index_of`, which provides an index only to `capacity`.
        static bool create(size_t capacity, ref IAllocator allocator, out Table table) {
            const max_distance = max(min_distance, ilog2(capacity));
            const real_capacity = (capacity + max_distance);
            const max_entries = cast(size_t)(real_capacity * max_load_factor);

            if (auto slots = allocator.make_array!Slot(real_capacity)) {
                table = Table(slots, max_distance, max_entries, capacity, 0);
                return true;
            }
            return false;
        }

        static void dispose(ref Table table, ref IAllocator allocator) {
            allocator.dispose(table.slots);
            table = Table();
        }

        size_t index_of(hash_t hash) {
            // 2 ^ 64 / golden_ratio, rounded up to nearest odd
            enum size_t multiple = 11400714819323198485;

            assert(is_power_of_two(created_capacity));
            return (hash.int_value * multiple) & (created_capacity - 1);
        }
    }

    static bool _insert(ref Table table, hash_t key, ref Value value, ref IAllocator allocator) {
        if (table.num_entries == table.max_entries && !_grow(table, allocator)) {
            return false;
        }

        const index = table.index_of(key);

        byte distance = 0;
        auto insert_point = &table[index];
        for (; insert_point.distance >= distance; distance++, insert_point++) {
            if (value_hasher(insert_point.value) == key) {
                swap(insert_point.value, value);
                destroy(value);
                return true;
            }
        }

        if (insert_point.is_empty()) {
            insert_point.value = move(value);
            insert_point.distance = distance;
            table.num_entries++;
            return true;
        }

        auto swap_value = move(value);
        swap(insert_point.value, swap_value);
        swap(insert_point.distance, distance);

        distance++;
        insert_point++;
        while (true) {
            if (insert_point.is_empty()) {
                insert_point.distance = distance;
                insert_point.value = move(swap_value);
                table.num_entries++;
                return true;
            }
            else if (insert_point.distance < distance) {
                swap(insert_point.value, swap_value);
                swap(insert_point.distance, distance);
                distance++;
            }
            else {
                distance++;
                if (distance == table.max_distance) {
                    if (!_grow(table, allocator))
                        return false;
                    else
                        return _insert(table, value_hasher(swap_value), swap_value, allocator);
                }
            }
        }
    }

    static bool _grow(ref Table table, ref IAllocator allocator) {
        return _rehash(table, max(smallest_size, table.created_capacity * 2), allocator);
    }

    static bool _rehash(ref Table table, size_t capacity, ref IAllocator allocator) {
        Table new_table;
        if (!Table.create(capacity, allocator, new_table))
            return false;

        foreach (ref slot; table.slots) {
            if (slot.has_value) {
                _insert(new_table, value_hasher(slot.value), slot.value, allocator);
                // call to destructor here is necessary for ref-counted resources
                destroy(slot.value);
            }
        }

        swap(table, new_table);
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
    assert(set._table.slots[7] == set.Slot(100, 0));
    assert(set._table.slots[8] == set.Slot(200, 1));
    assert(set._table.slots[9] == set.Slot(300, 2));
    assert(set._table.slots[10] == set.Slot(400, 3));
}
