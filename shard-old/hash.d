module shard.hash;

import std.digest.murmurhash: digest, MurmurHash3;
import core.stdc.string : memcpy;
import shard.math_util : ilog2;
import std.traits : isPointer;

nothrow:

alias Hash32 = Hash!32;
alias Hash64 = Hash!64;

struct Hash(size_t N) {
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

    this(ubyte[] v) nothrow {
        bytes[] = v[0 .. bytes.sizeof];
    }

    this(IntType v) nothrow {
        int_value = v;
    }

    static Hash of(T : const(char)[])(T str) {
        return Hash(digest!Hasher(str)[0 .. hash_bytes]);
    }

    static Hash of(T)(T p) if (isPointer!T) {
        enum size_t shift = ilog2(1 + T.sizeof);
        const v8 = (cast(size_t) p) >> shift;
        return Hash((cast(ubyte*) &v8)[0 .. hash_bytes]);
    }
}
