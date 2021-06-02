module shard.utils.table;

import shard.hash : Hash, is_hash;
import shard.math : ilog2, is_power_of_two;
import shard.memory.allocators.api : IAllocator;
import std.algorithm : max, move, swap;
import std.traits : hasElaborateDestructor, ReturnType;

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
struct HashTable(Value, alias value_hasher = Hash!32.of!Value) {
    alias hash_t = ReturnType!value_hasher;

    enum max_load_factor = 0.8;

    static assert(is_hash!hash_t, "value_hasher() must return a hash type!");

    @disable this(this);

    size_t size() nothrow {
        return _table.num_entries;
    }

    bool is_empty() nothrow {
        return _table.num_entries == 0;
    }

    bool contains(hash_t key) nothrow {
        return get(key) !is null;
    }

    void reset(ref IAllocator allocator) nothrow {
        static if (hasElaborateDestructor!Value) {
            foreach (i, ref value; _table.values) {
                if (_table.has_value(i))
                    destroy(value);
            }
        }

        Table.dispose(_table, allocator);
        _table = Table();
    }

    bool insert()(hash_t key, auto ref Value value, ref IAllocator allocator) nothrow {
        return _insert(&_table, key, value, allocator) !is null;
    }

    void remove(hash_t key, ref IAllocator allocator) nothrow {
        auto value = get(key);
        if (value is null)
            return;

        auto index = value - _table.values.ptr;
        auto next = index + 1;

        _table.distances[index] = -1;
        static if (hasElaborateDestructor!Value)
            destroy(value);

        for (; _table.distances[next] > 0; index++, next++) {
            _table.values[index] = move(_table.values[next]);
            _table.distances[index] = cast(byte)(_table.distances[next] - 1);

            static if (hasElaborateDestructor!Value)
                destroy(_table.values[next]);
            _table.distances[next] = -1;
        }

        _table.num_entries--;
    }

    Value* get(hash_t key) nothrow {
        auto distance = 0;
        auto index = _table.index_of(key);

        for (; _table.distances[index] >= distance; distance++, index++) {
            if (key == value_hasher(_table.values[index]))
                return &_table.values[index];
        }

        return null;
    }

    Value* get_or_insert()(hash_t key, auto ref Value value, ref IAllocator allocator) nothrow {
        byte distance = 0;
        auto index = _table.index_of(key);

        for (; _table.distances[index] >= distance; distance++, index++) {
            if (key == value_hasher(_table.values[index]))
                return &_table.values[index];
        }

        return _insert_new_value(&_table, key, value, distance, index, allocator);
    }

private:
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

        static assert(Table.sizeof == 64);

        @disable this(this);

        /// Creates a new table with `capacity + ilog2(capacity)` slots. The
        /// extra slots enable search loops to avoid bounds checking by
        /// nature of `index_of`, which provides an index only to `capacity`.
        static bool create(size_t capacity, ref IAllocator allocator, out Table table) nothrow {
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

        static void dispose(ref Table table, ref IAllocator allocator) nothrow {
            allocator.dispose(table.values);
            allocator.dispose(table.distances);
            table = Table();
        }

        size_t index_of(hash_t hash) nothrow {
            // 2 ^ 64 / golden_ratio, rounded up to nearest odd
            enum size_t multiple = 114_00_714_819_323_198_485;

            assert(is_power_of_two(created_capacity));
            return (hash.int_value * multiple) & (created_capacity - 1);
        }

        pragma(inline, true) bool has_value(size_t index) nothrow {
            return distances[index] >= 0;
        }

        pragma(inline, true) bool is_empty(size_t index) nothrow {
            return distances[index] == -1;
        }
    }

    static Value* _insert(Table* table, hash_t key, ref Value value, ref IAllocator allocator) nothrow {
        if (table.num_entries == table.max_entries && !_grow(table, allocator)) {
            return null;
        }

        byte distance = 0;
        size_t insert_point = table.index_of(key);
        // import std.stdio; writeln(table.values.length, ":", insert_point);
        for (; table.distances[insert_point] >= distance; distance++, insert_point++) {
            if (value_hasher(table.values[insert_point]) == key) {
                swap(table.values[insert_point], value);

                static if (hasElaborateDestructor!Value)
                    destroy(value);

                return &table.values[insert_point];
            }
        }

        return _insert_new_value(table, key, value, distance, insert_point, allocator);
    }

    static Value* _insert_new_value(Table* table, hash_t key, ref Value value,
            byte distance, size_t insert_point, ref IAllocator allocator) nothrow {
        if (distance > table.max_distance) {
            if (_grow(table, allocator))
                return _insert(table, key, value, allocator);
            return null;
        }

        if (table.is_empty(insert_point)) {
            table.values[insert_point] = move(value);
            table.distances[insert_point] = distance;
            table.num_entries++;
            return &table.values[insert_point];
        }

        auto swap_value = move(value);
        swap(table.values[insert_point], swap_value);
        swap(table.distances[insert_point], distance);

        distance++;
        insert_point++;
        for (; !table.is_empty(insert_point); distance++, insert_point++) {
            if (table.distances[insert_point] < distance) {
                swap(table.values[insert_point], swap_value);
                swap(table.distances[insert_point], distance);
            }
            else if (distance == table.max_distance) {
                if (!_grow(table, allocator))
                    return null;
                else
                    return _insert(table, value_hasher(swap_value), swap_value, allocator);
            }
        }

        table.distances[insert_point] = distance;
        table.values[insert_point] = move(swap_value);
        table.num_entries++;
        return &table.values[insert_point];
    }

    static bool _grow(Table* table, ref IAllocator allocator) nothrow {
        return _rehash(table, max(smallest_size, table.created_capacity * 2), allocator);
    }

    static bool _rehash(Table* table, size_t capacity, ref IAllocator allocator) nothrow {
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

@("HashTable: colliding inserts") unittest {
    import shard.memory.allocators.system : SystemAllocator;

    SystemAllocator mem;
    HashTable!int table;

    table.insert(Hash!32(3), 100, mem.allocator_api);
    table.insert(Hash!32(11), 200, mem.allocator_api);
    table.insert(Hash!32(19), 300, mem.allocator_api);
    table.insert(Hash!32(27), 400, mem.allocator_api);

    // Colliding slots are correctly inserted past `table.created_capacity`
    assert(table._table.created_capacity == 8);
    assert(table._table.max_distance == 3);

    assert(table._table.values[7] == 100);
    assert(table._table.distances[7] == 0);

    assert(table._table.values[8] == 200);
    assert(table._table.distances[8] == 1);

    assert(table._table.values[9] == 300);
    assert(table._table.distances[9] == 2);

    assert(table._table.values[10] == 400);
    assert(table._table.distances[10] == 3);

    table.reset(mem.allocator_api());
}
