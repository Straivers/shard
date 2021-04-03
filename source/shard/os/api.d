module shard.os.api;

import shard.os.win32_time;

version (Windows) {
    alias OsClock = Win32Clock;
}
