module app;

import shard.hash : Hash32;
import shard.memory.allocators.system : SystemAllocator;
import std.random : uniform;
import std.range : iota, lockstep;
import std.stdio : writeln, writefln;
import std.datetime.stopwatch : StopWatch;
import std.traits : fullyQualifiedName;

// import shard.utils.map : UnmanagedHashMap32;
import shard.utils.map2;

void main() {
    HashTable!(Hash32, size_t) map;
    test(map);
    // writefln("%x", cast(byte) -1);

    // union T {
    //     byte[4] b = [-1, -1, -1, -1];
    //     int i;
    // }
    // writefln("%x", T().i);
    // writefln("%x", uint.max);
}

void test(Map)(ref Map map) {
    writeln("Running test on ", typeof(map).stringof);

    SystemAllocator mem;

    auto sw = StopWatch();
    sw.start();

    auto gt = StopWatch();
    gt.start();

    alias Unit = void[0];
    Unit[Hash32] hashes;
    while (hashes.length < 2_000_000)
        hashes[Hash32(uniform(0, uint.max))] = Unit.init;

    assert(map.is_empty());
    assert(map.size() == 0);

	const init_time = sw.peek().total!"nsecs";
	writeln("Init time: ", init_time);
	sw.reset();

    foreach (i, v; lockstep(iota(hashes.length), hashes.byKey)) {
        map.insert(v, cast(uint) i, mem.allocator_api());
        assert(map.contains(v));
        assert(*map.get(v) == i);
        // assert(map.size() == i + 1);
    }

	const insert_time = sw.peek().total!"nsecs";
	writeln("Insert time: ", insert_time);
	sw.stop();

	// sw.reset();
	// sw.start();

    // foreach (v; hashes.byKey) {
    //     map.remove(v, mem.allocator_api());
    //     assert(!map.contains(v));
    // }

	// const remove_time = sw.peek().total!"nsecs";
	// writeln("Remove time: ", remove_time);
	// sw.stop();

    const total_time = gt.peek().total!"msecs";
    writeln("Total time: ", total_time);
    gt.stop();

    // assert(map.size() == 0);
}
