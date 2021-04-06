module shard.hash;

nothrow:

align (8) struct Hash64 {
    ulong value;
}

Hash64 hash64_of(const(char)[] str) {
    import std.digest.murmurhash: digest, MurmurHash3;

    auto v = digest!(MurmurHash3!128)(str);
    return Hash64(*(cast(ulong*) v.ptr));
}

align (4) struct Hash32 {
    uint value;
}

Hash32 hash32_of(const(char)[] str) {
    import std.digest.murmurhash: digest, MurmurHash3;

    auto v = digest!(MurmurHash3!32)(str);
    return Hash32(*(cast(uint*) v.ptr));
}
