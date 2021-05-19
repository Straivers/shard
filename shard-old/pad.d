module shard.pad;

mixin template pad_bytes(size_t n, size_t line = __LINE__) {
    import std.format: format;

    mixin(format!"void[n] pad_%s_bytes_%s;"(n, line));
}
