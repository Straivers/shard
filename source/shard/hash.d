module shard.hash;

import shard.math : ilog2;
import std.digest.murmurhash : digest, MurmurHash3;
import std.traits : hasMember, isIntegral, isPointer;

nothrow:

alias Hash32 = Hash!32;
// alias Hash64 = Hash!64;
// alias Hash128 = Hash!128;

template is_hash(T) {
    enum is_hash = is(T == Hash32) /* || is(T == Hash64) || is(T == Hash128) */;
}

struct Hash(size_t N : 32) {
    enum hash_bytes = N / 8;

    static if (hash_bytes == 4) {
        alias IntType = uint;
        alias Hasher = MurmurHash3!32;
    }
    else static if (hash_bytes == 8) {
        alias IntType = ulong;
        alias Hasher = MurmurHash3!128;
    }
    else static assert(0, "Hash size not supported");

    union {
        ubyte[hash_bytes] bytes;
        IntType int_value;
    }

@safe nothrow:

    this(ubyte[] v) {
        bytes[] = v[0 .. bytes.sizeof];
    }

    this(IntType v) {
        int_value = v;
    }

    static @safe Hash of(T : Hash)(T hash) {
        return hash;
    }

    static @safe Hash of(T : const(char)[])(T str) {
        return Hash(digest!Hasher(str)[0 .. hash_bytes]);
    }

    static @trusted Hash of(T)(T p) if (isPointer!T) {
        enum size_t shift = ilog2(1 + T.alignof);
        const v8 = (cast(size_t) p) >> shift;
        return Hash((cast(ubyte*) &v8)[0 .. hash_bytes]);
    }

    static @safe Hash of(T)(T i) if (isIntegral!T) {
        return Hash(cast(IntType) i);
    }

    static @safe Hash of(T)(auto ref T t) if (hasMember!(T, "hash_of")) {
        return t.hash_of();
    }
}
