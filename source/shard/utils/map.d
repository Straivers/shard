module shard.utils.map;

import shard.hash : Hash;
import shard.memory.allocators.api : Allocator;
import shard.utils.table;
import std.algorithm : move;
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
struct HashMap(Key, Value, alias key_hasher = Hash!32.of!Key) {
    size_t size() nothrow {
        return _impl.size();
    }

    bool is_empty() nothrow {
        return _impl.is_empty();
    }

    bool contains(Key key) nothrow {
        return _impl.contains(key_hasher(key));
    }

    void reset(Allocator allocator) nothrow {
        _impl.reset(allocator);
    }

    Value* insert(Key key, ref Value value, Allocator allocator) nothrow {
        auto pair = Pair(key, move(value));
        return &_impl.insert(key_hasher(key), pair, allocator).value;
    }

    Value* insert(Key key, Value value, Allocator allocator) nothrow {
        return &_impl.insert(key_hasher(key), Pair(key, value), allocator).value;
    }

    bool remove(Key key, Allocator allocator) nothrow {
        return _impl.remove(key_hasher(key), allocator);
    }

    Value* get(Key key) nothrow {
        return &_impl.get(key_hasher(key)).value;
    }

    Value* get_or_insert()(Key key, auto ref Value value, Allocator allocator) nothrow {
        return &_impl.get_or_insert(key_hasher(key), Pair(key, move(value)), allocator).value;
    }

private:
    struct Pair {
        Key key;
        Value value;

        pragma(inline, true) static hash(ref Pair pair) nothrow {
            return key_hasher(pair.key);
        }
    }

    HashTable!(Pair, Pair.hash) _impl;
}

@("HashMap: insert(), contains(), and get()") unittest {
    import shard.memory.allocators.system : SystemAllocator;
    import std.random : uniform;
    import std.range : iota, lockstep;

    scope mem = new SystemAllocator();
    HashMap!(Hash!32, ulong) map;

    ulong[Hash!32] hashes;
    while (hashes.length < 1_000)
        hashes[Hash!32(uniform(0, uint.max))] = hashes.length;

    foreach (key; hashes.byKey)
        map.insert(key, hashes[key], mem);

    foreach (key; hashes.byKey) {
        assert(map.contains(key));
        assert(*map.get(key) == hashes[key]);
    }
}

@("HashMap: get_or_insert()") unittest {
    import shard.memory.allocators.system : SystemAllocator;

    scope mem = new SystemAllocator();
    HashMap!(ulong, ulong) map;

    map.insert(20, 100, mem);
    assert(map.contains(20));

    assert(!map.contains(10));
    auto value = map.get_or_insert(10, 200, mem);
    assert(map.contains(10));

    assert(*value == 200);
    *value = 500;

    assert(*map.get_or_insert(10, 10, mem) == 500);
    assert(*map.get(10) == 500);

    map.reset(mem);
}
