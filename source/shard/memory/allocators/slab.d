module shard.memory.allocators.slab;

import shard.math : round_to_next;
import core.stdc.string : memset;
import shard.memory.allocators.api : IAllocator;
import shard.memory.values : platform_alignment;
import shard.traits : uint_type_to_store;

struct Slab(size_t block_size, size_t num_blocks) {

    void initialize() {
        if (num_blocks) {
            foreach (i, ref block; _blocks) {
                block.next_index = _freelist;
                _freelist = cast(IndexType) i;
            }
        }
    }

    IAllocator allocator_api() {
        return IAllocator(
            &this,
            &allocator_api_alignment,
            null,
            &allocator_api_allocate,
            &allocator_api_deallocate,
            &allocator_api_reallocate,
        );
    }

    size_t alignment() const nothrow {
        return platform_alignment;
    }

    void[] allocate(size_t size) {
        if (_freelist != IndexType.max) {
            if (((0 < size) & (size <= block_size)) != 0) {
                auto block = &_blocks[_freelist];
                _freelist = block.next_index;

                block.next_index = 0;
                return block.memory[0 .. size];
            }
        }

        return null;
    }

    void deallocate(void[] memory) {
        if (memory == [])
            return;
        
        assert(_owns(memory) && _is_aligned(memory));
        assert(memory.length <= block_size);

        auto block = cast(Block*) memory.ptr;
        memset(block, 0, Block.sizeof);

        block.next_index = _freelist;
        size_t block_index = block - _blocks.ptr;
        
        assert(block_index <= IndexType.max);
        _freelist = cast(IndexType) block_index;
    }

    bool reallocate(ref void[] memory, size_t new_size) {
        if (new_size > block_size)
            return false;

        if (memory == []) {
            memory = allocate(new_size);
            return memory != [];
        }

        assert(_owns(memory) && _is_aligned(memory));

        if (new_size == 0) {
            deallocate(memory);
            memory = [];
            return true;
        }

        memory = memory.ptr[0 .. new_size];
        return true;
    }

private:
    alias IndexType = uint_type_to_store!num_blocks;

    union Block {
        void[block_size] memory;
        IndexType next_index;
    }

    static size_t allocator_api_alignment(const void* self) nothrow {
        return (cast(const Slab*) self).alignment();
    }

    static void[] allocator_api_allocate(void* self, size_t size) nothrow {
        return (cast(Slab*) self).allocate(size);
    }

    static void allocator_api_deallocate(void* self, void[] block) nothrow {
        return (cast(Slab*) self).deallocate(block);
    }

    static bool allocator_api_reallocate(void* self, ref void[] block, size_t size) nothrow {
        return (cast(Slab*) self).reallocate(block, size);
    }

    bool _owns(void[] memory) {
        return _blocks.ptr <= memory.ptr && memory.ptr + memory.length <= _blocks.ptr + _blocks.length;
    }

    bool _is_aligned(void[] memory) {
        return (memory.ptr - cast(void*) _blocks.ptr) % block_size == 0;
    }

    bool _has_blocks() {
        return _freelist != IndexType.max;
    }

    Block[num_blocks] _blocks;
    IndexType _freelist = IndexType.max;
}

@("Slab: initialization") unittest {
    Slab!(1, 5) slab;

    static assert(is(slab.IndexType == ubyte));
    static assert(is(Slab!(1, 512).IndexType == ushort));

    slab.initialize();

    size_t count;
    for (auto p = slab._freelist; p < slab.IndexType.max; p = slab._blocks[p].next_index)
        count++;

    assert(count == 5);
}

@("Slab: IAllocator compliance") unittest {
    import shard.memory.allocators.api : test_allocate_api, test_resize_api;

    Slab!(64, 16) slab;
    slab.initialize();
    auto api = slab.allocator_api();
    test_allocate_api(api);
    test_resize_api(api);
}
