module shard.utils.map;

import shard.memory.allocators.api : IAllocator;
import shard.hash : Hash32;

/**
Two versions of `UnmanagedHashMap32` exist. The first maps keys to values, and
the second maps hashes to values.
*/
struct UnmanagedHashMap32(Key, Value) {
    alias Hasher = Hash32 function(ref Key);

    this(ref IAllocator allocator, Hash32 function(ref Key) hasher, uint num_buckets = 64) {
        _impl = UnmanagedHashMap32!Value(allocator, num_buckets);
        _hasher = hasher;
    }

    @disable this(this);

    void clear(ref IAllocator allocator) {
        return _impl.clear(allocator);
    }

    bool is_empty() {
        return _impl.is_empty();
    }

    size_t size() {
        return _impl.size();
    }

    bool contains(Key key) {
        return _impl.contains(_hasher(key));
    }

    ref Value get(Key key) in (contains(key)) {
        return _impl.get(_hasher(key));
    }

    Value try_get(Key key, lazy Value value) {
        return _impl.try_get(_hasher(key), value);
    }

    bool insert(Key key, Value value, ref IAllocator allocator) in (!contains(key)) {
        return _impl.insert(_hasher(key), value, allocator);
    }

    Value remove(Key key, ref IAllocator allocator) in (contains(key)) {
        return _impl.remove(_hasher(key), allocator);
    }

private:
    UnmanagedHashMap32!Value _impl;
    Hash32 function(ref Key) _hasher;
}

/// Ditto
struct UnmanagedHashMap32(Value) {
    this(ref IAllocator allocator, uint num_buckets = 64) {
        _buckets = allocator.make_array!(Node*)(num_buckets);
    }

    @disable this(this);

    void clear(ref IAllocator allocator) {
        static void free_node(Node* node, ref IAllocator allocator) {
            if (node) {
                free_node(node.next, allocator);
                allocator.dispose(node);
            }
        }

        foreach (node; _buckets)
            free_node(node, allocator);

        allocator.dispose(_buckets);
    }

    bool is_empty() {
        return _num_entries == 0;
    }

    size_t size() {
        return _num_entries;
    }

    bool contains(Hash32 hash) {
        const bucket_id = hash.int_value % _buckets.length;
        auto e = _buckets[bucket_id];
        while(e) {
            if (e.hash == hash)
                return true;
            e = e.next;
        }
        return false;
    }

    ref Value get(Hash32 hash) in(contains(hash)) {
        const bucket_id = hash.int_value % _buckets.length;
        auto e = _buckets[bucket_id];
        while(e) {
            if (e.hash == hash)
                return _buckets[bucket_id].value;
            e = e.next;
        }
        assert(0, "Key not found!");
    }

    Value try_get(Hash32 hash, lazy Value default_value) {
        const bucket_id = hash.int_value % _buckets.length;
        auto e = _buckets[bucket_id];
        while(e) {
            if (e.hash == hash)
                return _buckets[bucket_id].value;
            e = e.next;
        }
        return default_value;
    }

    bool insert(Hash32 hash, Value value, ref IAllocator allocator) in (!contains(hash)) {
        if (double(_num_entries) / _buckets.length > 0.7)
            _buckets = _rehash(_buckets, allocator.make_array!(Node*)(_buckets.length * 2), allocator);

        const bucket_id = hash.int_value % _buckets.length;

        if (_buckets[bucket_id] is null) {
            if (auto n = allocator.make!Node(null, hash, value)) {
                _buckets[bucket_id] = n;
                _num_entries++;
                return true;
            }
            return false;
        }

        if (auto n = allocator.make!Node(_buckets[bucket_id], hash, value)) {
            _buckets[bucket_id] = n;
            _num_entries++;
            return true;
        }
        return false;
    }

    Value remove(Hash32 hash, ref IAllocator allocator) in (contains(hash)) {
        void close() {
            _num_entries--;
            if (double(_num_entries) / _buckets.length < 0.25)
                _buckets = _rehash(_buckets, allocator.make_array!(Node*)(_buckets.length / 2), allocator);
        }

        const bucket_id = hash.int_value % _buckets.length;
        assert(_buckets[bucket_id], "Key not found!");

        if (_buckets[bucket_id].hash == hash) {
            auto entry = _buckets[bucket_id];
            auto value = entry.value;

            _buckets[bucket_id] = entry.next;
            allocator.dispose(entry);
            close();

            return value;
        }
        else {
            auto prev = _buckets[bucket_id];
            auto curr = prev.next;
            while (curr && curr.hash != hash) {
                prev = curr;
                curr = curr.next;
            }

            assert(curr, "Key not found!");
            prev.next = curr.next;

            auto value = curr.value;
            allocator.dispose(curr);
            close();
            return value;
        }
    }

private:
    struct Node {
        Node* next;
        Hash32 hash;
        Value value;
    }

    static Node*[] _rehash(Node*[] old_buckets, Node*[] new_buckets, ref IAllocator allocator) {
        foreach (bucket; old_buckets) {
            auto entry = bucket;
            while (entry) {
                const new_id = entry.hash.int_value % new_buckets.length;
                auto next = entry.next;

                if (new_buckets[new_id] is null) {
                    entry.next = null;
                    new_buckets[new_id] = entry;
                }
                else {
                    entry.next = new_buckets[new_id];
                    new_buckets[new_id] = entry;
                }

                entry = next;
            }
        }

        allocator.dispose(old_buckets);
        return new_buckets;
    }

    uint _num_entries;
    Node*[] _buckets;
}

unittest {
    import shard.memory.allocators.system : SystemAllocator;
    import std.random : uniform;
    import std.range : iota, lockstep;

    SystemAllocator mem;
    auto map = UnmanagedHashMap32!uint(mem.allocator_api());

    alias Unit = void[0];
    Unit[Hash32] hashes;
    while (hashes.length < 100_000)
        hashes[Hash32(uniform(0, uint.max))] = Unit.init;

    auto values = new Hash32[](100_000);
    foreach(i, hash; lockstep(iota(values.length), hashes.byKey))
        values[i] = hash;

    assert(map.is_empty());
    assert(map.size() == 0);

    foreach (i, v; values) {
        map.insert(v, cast(uint) i, mem.allocator_api());
        assert(map.contains(v));
        assert(map.get(v) == i);
        assert(map.size() == i + 1);
    }

    foreach (v; values) {
        map.remove(v, mem.allocator_api());
        assert(!map.contains(v));
    }

    assert(map.size() == 0);
}
