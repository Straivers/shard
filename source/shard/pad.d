module shard.pad;

mixin template pad_bytes(size_t n, size_t line = __LINE__) {
    // mixin(format!"void[n] pad_%s_bytes_%s;"(n, line));
    mixin("void[" ~ n.stringof ~ "] pad_" ~ n.stringof ~ "_bytes_" ~ line.stringof ~ ";");
}
