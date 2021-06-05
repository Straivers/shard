module shard.memory.allocators.api;

import core.lifetime : emplace, forward;
import shard.traits : object_size, PtrType;
import std.traits : fullyQualifiedName, hasElaborateDestructor, hasMember;

alias length_t = size_t;

/**
Yes, we are using an interface. The key reasoning being that we expect allocator
use to be fairly consistent, with only a few in existence at any time.

If you only have a few allocators and allocate memory in large chunks outside of
tight loops, the performance impact should be minimal. In return, we gain
significant flexibility in how we can choose to implement new allocators and
insert them with no change to the rest of the codebase.
*/
interface Allocator {
    enum no_name = "no_name";

@safe nothrow:

    /**
    Allocates `size` bytes of memory.

    Params:
        size            = The size of the object to allocate.
        name            = An identifier used to enable tracking of the
                          allocation.
    */
    void[] allocate(size_t size, string name = no_name);

    /**
    Deallocates block of memory.

    Params:
        memory          = The block of memory to deallocate.
        name            = The same identifier used 
    */
    void deallocate(void[] memory);

    /**
    Resizes an array. It may allocate a new region of memory and copy the old
    elements to it.

    Note that two special cases apply when calling `reallocate_array()`:
    * If `memory` is empty and `new_length > 0`, a new array will be dynamically
      allocated.
    * If `memory` is not empty, and `new_length` is 0, the array will be
      deallocated.

    Params:
        memory          = The array to be resized. May be empty (`[]`).
        element_size    = The size of each element in the array. Must be at
                          least 1, and must not change for the lifetime of the
                          array.
        new_length      = The length of the array after resizing. May be 0.
        name            = An identifier used to enable tracking of the
                          allocation. Must not change for the lifetime of the
                          array.
    
    Returns: The resized array, or `[]` if reallocation failed.
    */
    void[] reallocate_array(void[] memory, size_t element_size, length_t new_length, string name = no_name);

public:

    /**
    Dynamically allocates memory from the allocator then constructs an object of
    type `T` in that memory, with any provided arguments.

    Params:
        args            = Any arguments required for the construction of the
                          object

    Returns: A reference (class) or pointer (everything else) to the initialized
    object.
    */
    PtrType!T make(T, Args...)(auto ref Args args) {
        // max(object_size!T, 1) to support 0-size types (void, especially)
        const size = object_size!T > 1 ? object_size!T : 1;

        void[] m = allocate(size, fullyQualifiedName!T);
        if (!m.ptr) return null;

        static if (is(T == class)) {
            return emplace!T(m, forward!args);
        }
        else {
            auto p = (() @trusted => cast(T*) m.ptr)();
            emplace!T(p, forward!args);
            return p;
        }
    }

    /**
    Dynamically allocates memory for a `length`-element array of type `T`. All
    elements are initialized to their default value.

    Params:
        length          = The length of the array to create.

    Returns: The newly created array, or `null` if `length` was 0 or allocation failed.
    */
    T[] make_array(T)(length_t length) {
        if (!length)
            return null;

        if (auto array = reallocate_array([], T.sizeof, length, fullyQualifiedName!T)) {
            auto t_array = (() @trusted => cast(T[]) array)();

            static if (!is(T == void))
                t_array[] = T.init;

            return t_array;
        }

        return null;
    }

    /**
    Resizes an array to `new_length` elements.

    Note that two special cases apply when calling `resize_array()`:
    * If `array` is empty and `new_length > 0`, a new array will be dynamically
      allocated.
    * If `array` is not empty, and `new_length` is 0, the array will be
      deallocated.

    Params:
        array           = The array to be resized. May be `null`.
        new_length      = The length of the array after resizing. May be `0`.
    */
    bool resize_array(T)(ref T[] array, length_t new_length) {
        static assert(!hasMember!(T, "opPostMove"), "Move construction on array reallocation not supported!");
        assert(T.sizeof * new_length >= new_length, "Getting size of array overflows size_t!");

        @safe bool do_resize() {
            if (auto memory = reallocate_array(array, T.sizeof, new_length, fullyQualifiedName!T)) {
                array = (() @trusted => cast(T[]) memory)();
                return true;
            }

            return false;
        }

        if (new_length == array.length)
            return true;

        if (new_length < array.length) {
            static if (hasElaborateDestructor!T)
                foreach (ref object; array[new_length .. $])
                    destroy(object);

            return do_resize();
        }
        else {
            const old_length = array.length;

            if (!do_resize())
                return false;

            static if (is(typeof(array[] = T.init)))
                array[old_length .. $] = T.init;
            else
                foreach (ref e; array[old_length .. $])
                    e = T.init;

            return true;
        }
    }

    /**
    Destroys and deallocates the object pointed to by pointer, a `class` or
    `interface` reference, or an array.

    Disposing of an array will trigger the destructor for every element in the
    array.

    Params:
        p               = The object or array to be destroyed.
    */
    void dispose(T)(auto ref T* p) {
        static if (hasElaborateDestructor!T)
            destroy(*p);

        deallocate((() @trusted => (cast(void*) p)[0 .. T.sizeof])());

        static if (__traits(isRef, p))
            p = null;
    }

    /// Ditto
    void dispose(T)(auto ref T p)
    if (is(T == class) || is(T == interface)) {
        
        static if (is(T == interface))
            auto ob = cast(Object) p;
        else
            alias ob = p;

        auto support = (cast(void*) ob)[0 .. typeid(ob).initializer.length];

        destroy(p);
        deallocate(support);

        static if (__traits(isRef, p))
            p = null;
    }

    /// Ditto
    void dispose(T)(auto ref T[] p) {
        static if (hasElaborateDestructor!(typeof(p[0])))
            foreach (ref e; p)
                destroy(e);

        void[] m = (() @trusted => cast(void[]) p)();
        reallocate_array(m, T.sizeof, 0, fullyQualifiedName!T);

        static if (__traits(isRef, p))
            p = null;
    }
}
