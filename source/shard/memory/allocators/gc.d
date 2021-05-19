module shard.memory.allocators.gc;

import shard.math: round_to_next;
import shard.memory.allocators.api;
import shard.memory.constants: platform_alignment;

import core.memory : GC;

final class GarbageCollector : Allocator {
    override size_t alignment() const nothrow {
        return platform_alignment;
    }

    override size_t optimal_size(size_t size) const nothrow {
        return size;
    }

    override void[] allocate(size_t size) nothrow {
        try {
            return GC.malloc(size)[0 .. size];
        } catch (Exception e) {
            GC.free(cast(void*) e);
            return null;
        }
    }

    alias deallocate = Allocator.deallocate;

    override void deallocate(ref void[] memory) nothrow {
        GC.free(memory.ptr);
        memory = null;
    }

    override bool reallocate(ref void[] memory, size_t size) nothrow {
        try {
            memory = GC.realloc(memory.ptr, size)[0 .. size];
            return true;
        } catch (Exception e) {
            GC.free(cast(void*) e);
            return false;
        }
    }

    override bool resize(ref void[] memory, size_t size) nothrow {
        return false;
    }
}

unittest {
    scope gc = new GarbageCollector();

    test_allocate_api(gc);
    test_resize_api(gc);
}
