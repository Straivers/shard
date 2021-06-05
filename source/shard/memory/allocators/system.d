module shard.memory.allocators.system;

import shard.math: round_to_next;
import shard.memory.allocators.api;
import shard.memory.values: platform_alignment;

import core.stdc.stdlib: malloc, free, realloc;

class SystemAllocator : Allocator {
@safe nothrow:

    void[] allocate(size_t size, string name = no_name) {
        if (size == 0)
            return null;

        auto m = (() @trusted => malloc(size))();
        return m ? (() @trusted => m[0 .. size])() : null;
    }

    void deallocate(void[] block) {
        () @trusted { free(block.ptr); } ();
    }

    void[] reallocate_array(void[] memory, size_t element_size, length_t length, string name = no_name) {
        const size = element_size * length;
        if (memory && size == 0) {
            (() @trusted => free(memory.ptr))();
            return [];
        }

        if (memory.length == size)
            return memory;

        if (auto p = (() @trusted => realloc(memory.ptr, size))()) {
            return (() @trusted => p[0 .. size])();
        }

        return [];
    }
}

@("SystemAllocator: interface compliance") unittest {
    scope mem = new SystemAllocator;

    void[] a;
    a = mem.reallocate_array(a, 1, 20);
    assert(a);
    assert(a.length == 20);

    a = mem.reallocate_array(a, 1, 30);
    assert(a);
    assert(a.length == 30);

    a = mem.reallocate_array(a, 1, 10);
    assert(a);
    assert(a.length == 10);

    a = mem.reallocate_array(a, 1, 0);
    assert(!a);
}

@("SystemAllocator: make_array(), resize_array(), dispose(array)") unittest {
    scope mem = new SystemAllocator;

    auto a1 = mem.make_array!int(20);
    assert(a1);
    assert(a1.length == 20);

    assert(mem.resize_array(a1, 10));
    assert(a1);
    assert(a1.length == 10);

    mem.dispose(a1);
    assert(!a1);
}
