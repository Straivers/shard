module shard.memory.allocators.system;

import shard.math: round_to_next;
import shard.memory.allocators.api;
import shard.memory.values: platform_alignment;

import core.stdc.stdlib: malloc, free, realloc;

struct SystemAllocator {
@safe nothrow:
    mixin Allocator.api!("allocate", "deallocate", "reallocate_array");

    void[] allocate(size_t size, string name = Allocator.no_name) {
        if (size == 0)
            return null;

        auto m = (() @trusted => malloc(size))();
        return m ? (() @trusted => m[0 .. size])() : null;
    }

    void deallocate(void[] block) {
        () @trusted { free(block.ptr); } ();
    }

    void[] reallocate_array(void[] memory, size_t element_size, length_t length, string name = Allocator.no_name) {
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
    SystemAllocator mem;

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
    SystemAllocator mem;
    auto allocator = mem.allocator();

    auto a1 = allocator.make_array!int(20);
    assert(a1);
    assert(a1.length == 20);

    assert(allocator.resize_array(a1, 10));
    assert(a1);
    assert(a1.length == 10);

    allocator.dispose(a1);
    assert(!a1);
}
