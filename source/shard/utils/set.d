module shard.utils.set;

import shard.hash : Hash;
import shard.memory.allocators.api : Allocator;
import shard.utils.table : HashTable;
import std.traits : ReturnType;
import std.algorithm : move;

struct HashSet(Value, alias value_hasher = Hash!32.of!Value) {
    alias hash_t = ReturnType!value_hasher;

    size_t size() nothrow {
        return _impl.size();
    }

    bool is_empty() nothrow {
        return _impl.is_empty();
    }

    bool contains(Value entry) nothrow {
        return _impl.contains(value_hasher(entry));
    }

    void reset(Allocator allocator) nothrow {
        _impl.reset(allocator);
    }

    Value* insert(Value value, Allocator allocator) nothrow {
        auto entry = Entry(value_hasher(value), move(value));
        return &_impl.insert(entry.key, entry, allocator).value;
    }

    bool remove(Value value, Allocator allocator) nothrow {
        return _impl.remove(value_hasher(value), allocator);
    }

private:
    struct Entry {
        hash_t key;
        Value value;

        pragma(inline, true) static hash(ref Entry entry) nothrow {
            return value_hasher(entry.key);
        }
    }

    HashTable!(Entry, Entry.hash) _impl;
}

@("HashSet: insert(), remove()") unittest {
    import shard.memory.allocators.system : SystemAllocator;
    import std.random : uniform;

    scope mem = new SystemAllocator();
    HashSet!(Hash!32) set;

    alias Unit = void[0];
    Unit[Hash!32] hashes;
    while (hashes.length < 1_000)
        hashes[Hash!32(uniform(0, uint.max))] = Unit.init;

    assert(set.is_empty());
    assert(set.size() == 0);

    foreach (v; hashes.byKey)
        set.insert(v, mem);

    assert(!set.is_empty());
    assert(set.size() == 1_000);

    foreach (v; hashes.byKey)
        assert(set.remove(v, mem));

    foreach (v; hashes.byKey)
        assert(!set.contains(v));

    assert(set.is_empty());
    assert(set.size() == 0);

    set.reset(mem);
}
