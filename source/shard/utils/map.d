module shard.utils.map;

import shard.hash : Hash32;
import shard.memory.allocators.api : IAllocator;
import shard.utils.intrusive_list : intrusive_list;

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
        _buckets = allocator.make_array!(Node.ListHead)(num_buckets);
    }

    @disable this(this);

    void clear(ref IAllocator allocator) {
        foreach (bucket; _buckets) {
            while (!bucket.is_empty())
                allocator.dispose(bucket.pop_front());
        }

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
        return _get_bucket(hash, bucket_id) !is null;
    }

    ref Value get(Hash32 hash) {
        const bucket_id = hash.int_value % _buckets.length;
        if (auto bucket = _get_bucket(hash, bucket_id))
            return bucket.value;
        assert(0, "Key not found!");
    }

    Value try_get(Hash32 hash, lazy Value default_value) {
        const bucket_id = hash.int_value % _buckets.length;
        if (auto bucket = _get_bucket(hash, bucket_id))
            return bucket.value;
        return default_value;
    }

    bool insert(Hash32 hash, Value value, ref IAllocator allocator) {
        if (_num_entries / _buckets.length > 1) {
            auto new_buckets = allocator.make_array!(Node.ListHead)(_buckets.length * 2);
            _buckets = _rehash(_buckets, new_buckets, allocator);
        }

        const bucket_id = hash.int_value % _buckets.length;

        foreach (node; _buckets[bucket_id][]) {
            if (node.hash == hash) {
                node.value = value;
                return true;
            }
        }

        if (auto n = allocator.make!Node(hash, value)) {
            _buckets[bucket_id].push_back(n);
            _num_entries++;
            return true;
        }

        return false;
    }

    Value remove(Hash32 hash, ref IAllocator allocator) {
        const bucket_id = hash.int_value % _buckets.length;
        auto bucket = _get_bucket(hash, bucket_id);

        if (!bucket)
            assert(0, "Key not found!");

        _buckets[bucket_id].remove(bucket);        
        scope (exit) allocator.dispose(bucket);

        _num_entries--;
        if (double(_num_entries) / _buckets.length < 0.25)
            _buckets = _rehash(_buckets, allocator.make_array!(Node.ListHead)(_buckets.length / 2), allocator);

        return bucket.value;
    }

private:
    struct Node {
        Hash32 hash;
        Value value;
        mixin intrusive_list!Node;
    }

    static Node.ListHead[] _rehash(Node.ListHead[] old_buckets, Node.ListHead[] new_buckets, ref IAllocator allocator) {
        foreach (bucket; old_buckets) {
            while (!bucket.is_empty) {
                auto entry = bucket.pop_front();
                const new_id = entry.hash.int_value % new_buckets.length;
                new_buckets[new_id].push_back(entry);
            }
        }

        allocator.dispose(old_buckets);
        return new_buckets;
    }

    Node* _get_bucket(Hash32 hash, size_t bucket_id) {
        foreach (bucket; _buckets[bucket_id][]) {
            if (bucket.hash == hash)
                return bucket;
        }
        return null;
    }

    uint _num_entries;
    Node.ListHead[] _buckets;
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
