module shard.utils.map;

import shard.hash : Hash32;
import shard.memory.allocators.api : IAllocator;
import shard.utils.array : UnmanagedArray;
import shard.utils.intrusive_list : intrusive_list;
import core.stdc.string: memmove;

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
        foreach (bucket; _buckets) {
            if (bucket)
                Node.cleanup(bucket, allocator);
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
        uint value_index;
        return _get_bucket(hash, bucket_id, value_index);
    }

    ref Value get(Hash32 hash) {
        const bucket_id = hash.int_value % _buckets.length;
        uint value_index;
        if (_get_bucket(hash, bucket_id, value_index))
            return _buckets[bucket_id].values[value_index];
        assert(0, "Key not found!");
    }

    Value try_get(Hash32 hash, lazy Value default_value) {
        const bucket_id = hash.int_value % _buckets.length;
        uint value_index;
        if (_get_bucket(hash, bucket_id, value_index))
            return _buckets[bucket_id].values[value_index];
        return default_value;
    }

    bool insert(Hash32 hash, Value value, ref IAllocator allocator) {
        if (_num_entries > _buckets.length && !_rehash(_buckets.length * 2, allocator))
            return false;

        const bucket_id = hash.int_value % _buckets.length;
        if (auto bucket = _buckets[bucket_id]) {
            foreach (i, map_hash; bucket.get_hashes()) {
                if (map_hash == hash) {
                    bucket.values[i] = value;
                    return true;
                }
            }

            if (bucket.append(hash, value, allocator)) {
                _num_entries++;
                return true;
            }
            else if (_rehash(_buckets.length * 2, allocator)) {
                return insert(hash, value, allocator);
            }

            return false;
        }
        else if (auto node = Node.create(allocator, hash, value)) {
            _buckets[bucket_id] = node;
            _num_entries++;
            return true;
        }

        return false;
    }

    Value remove(Hash32 hash, ref IAllocator allocator) {
        const bucket_id = hash.int_value % _buckets.length;
        uint value_index;

        if (!_get_bucket(hash, bucket_id, value_index))
            assert(0, "Key not found!");

        auto bucket = _buckets[bucket_id];
        auto value = bucket.values[value_index];
        if (!bucket.remove(value_index, allocator))
            assert(0, "Out of Memory!");

        _num_entries--;
        if (_num_entries * 4 < _buckets.length && !_rehash(_buckets.length / 2, allocator))
            assert(0, "Out of Memory!");

        return value;
    }

private:
    static struct Node {
        Hash32[8] hashes;
        Value[8] values;
        uint length;

        enum capacity = 8;

        static Node* create(ref IAllocator allocator, Hash32 first_hash, ref Value first_value) {
            if (auto node = allocator.make!Node()) {
                node.hashes[0] = first_hash;
                node.values[0] = first_value;
                node.length = 1;
                return node;
            }
            return null;
        }

        static void cleanup(Node* node, ref IAllocator allocator) {
            allocator.dispose(node);
        }

        pragma(inline, true) Hash32[] get_hashes() {
            return hashes[0 .. length];
        }

        bool append(Hash32 hash, ref Value value, ref IAllocator allocator) {
            if (length == capacity)
                return false;

            hashes[length] = hash;
            values[length] = value;
            length++;
            return true;
        }

        bool remove(uint index, ref IAllocator allocator) {
            assert(index < length);

            memmove(hashes.ptr + index, hashes.ptr + index + 1, Hash32.sizeof * (length - index));
            memmove(values.ptr + index, values.ptr + index + 1, Value.sizeof * (length - index));
            length--;

            return true;
        }
    }

    bool _rehash(size_t new_size, ref IAllocator allocator) {
        auto new_buckets = allocator.make_array!(Node*)(new_size);
        if (!new_buckets)
            return false;

        foreach (bucket; _buckets) {
            if (!bucket)
                continue;

            foreach (i; 0 .. bucket.length) {
                const map_hash = bucket.hashes[i];
                const new_index = map_hash.int_value % new_buckets.length;
                if (auto new_bucket = new_buckets[new_index]) {
                    new_bucket.append(map_hash, bucket.values[i], allocator);
                }
                else if (auto new_bucket = Node.create(allocator, map_hash, bucket.values[i])) {
                    new_buckets[new_index] = new_bucket;
                }
                else
                    return false;
            }

            Node.cleanup(bucket, allocator);
        }

        allocator.dispose(_buckets);
        _buckets = new_buckets;

        return true;
    }

    bool _get_bucket(Hash32 hash, size_t bucket_id, out uint index) {
        if (auto bucket = _buckets[bucket_id]) {
            foreach (i; 0 .. bucket.length)
                if (bucket.hashes[i] == hash) {
                    index = cast(uint) i;
                    return true;
                }
        }
        return false;

        // auto bucket =_buckets[bucket_id];
        // if (bucket) {
        //     for (uint i = 0; i < bucket.length; i++) {
        //         if (bucket.hashes.ptr[i] == hash) {
        //             index = i;
        //             return true;
        //         }
        //     }
        // }
        // return false;
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
