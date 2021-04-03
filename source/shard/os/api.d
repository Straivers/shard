module shard.os.api;

import shard.os.time;

OsClock os_clock;

version (Windows) {
    import shard.os.win32_time;

    private Win32Clock win32_impl;
    private void[__traits(classInstanceSize, Win32Clock)] win32_impl_raw;

    static this() {
        import std.conv : emplace;
        win32_impl = cast(Win32Clock) win32_impl_raw.ptr;
        emplace(win32_impl);
    }

    static ~this() {
        destroy(os_clock);
    }
}
