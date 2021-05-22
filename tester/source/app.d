module app;

import shard.hash : Hash32;
import shard.memory.allocators.system : SystemAllocator;
import shard.utils.map : UnmanagedHashMap32;
import std.random : randomCover, uniform;
import std.range : iota, lockstep;
import std.stdio : writeln;
import std.datetime.stopwatch : StopWatch;
import std.array : array;
import core.memory : GC;

void main() {
    writeln("Running tester");
    GC.disable();

    auto gt = StopWatch();
    gt.start();

	auto sw = StopWatch();
	sw.start();

    SystemAllocator mem;
    auto map = UnmanagedHashMap32!uint(mem.allocator_api());

    alias Unit = void[0];
    Unit[Hash32] hashes;
    while (hashes.length < 10_000_000)
        hashes[Hash32(uniform(0, uint.max))] = Unit.init;

    auto values = new Hash32[](10_000_000);
    foreach(i, hash; lockstep(iota(values.length), hashes.byKey))
        values[i] = hash;

    assert(map.is_empty());
    assert(map.size() == 0);

	const init_time = sw.peek().total!"nsecs";
	writeln("Init time: ", init_time);
	sw.reset();

    foreach (i, v; values) {
        map.insert(v, cast(uint) i, mem.allocator_api());
        assert(map.contains(v));
        assert(map.get(v) == i);
        assert(map.size() == i + 1);
    }

	const insert_time = sw.peek().total!"nsecs";
	writeln("Insert time: ", insert_time);
	sw.stop();

	sw.reset();
	sw.start();

    foreach (v; values) {
        map.remove(v, mem.allocator_api());
        assert(!map.contains(v));
    }

	const remove_time = sw.peek().total!"nsecs";
	writeln("Remove time: ", remove_time);
	sw.stop();

    const total_time = gt.peek().total!"msecs";
    writeln("Total time: ", total_time);
    gt.stop();

    assert(map.size() == 0);
    GC.enable();
}