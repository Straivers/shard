module shard.memory.tracker;

import shard.memory.common : Ternary;
import std.traits: hasMember, isPointer;

struct MemoryStats {
    size_t bytes_allocated;
    size_t most_bytes_allocated;

    size_t total_allocations;
    size_t num_allocations;
    size_t num_failed_allocations;
}

struct MemoryTracker(Allocator) {
    static if (is(Allocator == struct))
        this(A...)(A args) {
            _allocator = Allocator(args);
        }
    else static if (is(isPointer!Allocator)) {
        this(Allocator allocator) {
            _allocator = allocator;
        }
    }
    else static if (is(Allocator == class) || is(Allocator == interface))
        this(Allocator allocator) {
            _allocator = allocator;
        }
    else static assert(0, "Unconsidered case.");

    @disable this(this);

    ~this() {
        destroy(_allocator);
    }

    void get_stats(out MemoryStats stats) {
        stats = _stats;
    }

    size_t alignment() const nothrow { return _allocator.alignment; }

    static if (hasMember!(Allocator, "owns"))
        Ternary owns(void[] memory) const nothrow { return _allocator.owns(memory); }

    static if (hasMember!(Allocator, "get_optimal_alloc_size"))
        size_t get_optimal_alloc_size(size_t size) const nothrow { return _allocator.get_optimal_alloc_size(size); }

    void[] allocate(size_t size) {
        if (auto p = _allocator.allocate(size)) {
            _stats.bytes_allocated += size;
            _stats.num_allocations++;
            _stats.total_allocations++;

            if (_stats.bytes_allocated > _stats.most_bytes_allocated)
                _stats.most_bytes_allocated = _stats.bytes_allocated;
            return p;
        }
        else {
            _stats.num_failed_allocations++;
            return [];
        }
    }

    static if (hasMember!(Allocator, "deallocate"))
        bool deallocate(ref void[] memory) nothrow {
            const size = memory.length;
            const ok = _allocator.deallocate(memory);
            if (ok) {
                _stats.bytes_allocated -= size;
                _stats.num_allocations--;
            }
            return ok;
        }

    static if (hasMember!(Allocator, "reallocate"))
        bool reallocate(ref void[] memory, size_t new_size) nothrow { return _allocator.reallocate(memory, new_size); }

    static if (hasMember!(Allocator, "resize"))
        bool resize(ref void[] memory, size_t new_size) nothrow { return _allocator.resize(memory, new_size); }

private:
    Allocator _allocator;
    MemoryStats _stats;
}
