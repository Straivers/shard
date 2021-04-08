
module shard.memory.temp;

import shard.memory.allocator: Allocator;
import shard.memory.common : Ternary;
import shard.memory.measures: kib;

enum default_temp_arena_size = 16.kib;

auto scoped_arena(Allocator allocator, size_t size = default_temp_arena_size) nothrow {
    return ScopedArena(allocator, size);
}

struct ScopedArena {
    import shard.memory.arena : Arena;
    import std.typecons : scoped;

    final class Impl : Allocator {
        Arena arena;

    nothrow:
        this(Allocator allocator, size_t size) {
            arena = Arena(allocator, size);
        }

        ~this() {
            destroy(arena);
        }

        override size_t alignment() const {
            return arena.alignment();
        }

        override Ternary owns(void[] memory) const {
            return arena.owns(memory);
        }

        override size_t get_optimal_alloc_size(size_t size) const {
            return arena.get_optimal_alloc_size(size);
        }

        override void[] allocate(size_t size, string file = __FILE__, uint line = __LINE__) {
            return arena.allocate(size, file, line);
        }

        alias deallocate = Allocator.deallocate;

        override bool deallocate(ref void[] memory, string file = __FILE__, uint line = __LINE__) {
            return arena.deallocate(memory, file, line);
        }

        override bool reallocate(ref void[] memory, size_t new_size, string file = __FILE__, uint line = __LINE__) {
            return arena.reallocate(memory, new_size, file, line);
        }

        override bool resize(ref void[] memory, size_t new_size, string file = __FILE__, uint line = __LINE__) {
            return arena.resize(memory, new_size, file, line);
        }

    }

nothrow public:
    Allocator source;
    typeof(scoped!Impl(null, 0)) base;
    alias base this;

    this(Allocator source, size_t size) {
        base = scoped!Impl(source, size);
    }

    @disable this(this);

    ~this() {
        destroy(base);
    }
}

unittest {
    import shard.memory.allocator: AllocatorApi, test_allocate_api, test_reallocate_api, test_resize_api;
    import shard.memory.arena: UnmanagedArena;

    auto base = new AllocatorApi!UnmanagedArena(new void[](32.kib));
    auto temp = scoped_arena(base);

    test_allocate_api(temp);
    test_reallocate_api(temp);
    test_resize_api!true(temp);
}
