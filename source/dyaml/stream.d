module dyaml.stream;

enum BOM
{
    UTF8,           /// UTF-8
    UTF16LE,        /// UTF-16 Little Endian
    UTF16BE,        /// UTF-16 Big Endian
    UTF32LE,        /// UTF-32 Little Endian
    UTF32BE,        /// UTF-32 Big Endian
}

import std.system;

private enum int NBOMS = 5;
immutable Endian[NBOMS] BOMEndian =
[
    std.system.endian,
    Endian.littleEndian, Endian.bigEndian,
    Endian.littleEndian, Endian.bigEndian
];

immutable ubyte[][NBOMS] ByteOrderMarks =
[
    [0xEF, 0xBB, 0xBF],
    [0xFF, 0xFE],
    [0xFE, 0xFF],
    [0xFF, 0xFE, 0x00, 0x00],
    [0x00, 0x00, 0xFE, 0xFF]
];

interface YStream
{
    void writeExact(const void* buffer, size_t size);
    void writeExact(const void[] buffer) @safe;
    size_t write(const(ubyte)[] buffer) @safe;
    size_t write(const(char)[] str) @safe;
    void flush() @safe;
    @property bool writeable() @safe;
}

class YMemoryStream : YStream
{
    ubyte[] data;

    void writeExact(const void* buffer, size_t size)
    {
        data ~= cast(ubyte[])buffer[0 .. size];
    }

    void writeExact(const void[] buffer) @trusted
    {
        data ~= cast(ubyte[])buffer;
    }

    size_t write(const(ubyte)[] buffer) @safe
    {
        data ~= buffer;
        return buffer.length;
    }

    size_t write(const(char)[] str) @safe
    {
        return write(cast(const(ubyte)[])str);
    }

    void flush() @safe {}

    @property bool writeable() @safe { return true; }
}

class YFile : YStream
{
    static import std.stdio;
    std.stdio.File file;

    this(string fn) @safe
    {
        this.file = std.stdio.File(fn, "w");
    }

    this(std.stdio.File file) @safe
    {
        this.file = file;
    }

    @system unittest
    {
        import std.stdio : stdout;
        auto stream = new YFile(stdout);
        stream.write("Test writing to stdout through YFile stream\n");
    }

    void writeExact(const void* buffer, size_t size)
    {
        this.file.rawWrite(cast(const) buffer[0 .. size]);
    }

    void writeExact(const void[] buffer) @trusted
    {
        this.file.rawWrite(buffer);
    }

    size_t write(const(ubyte)[] buffer) @trusted
    {
        this.file.rawWrite(buffer);
        return buffer.length;
    }

    size_t write(const(char)[] str) @trusted
    {
        return write(cast(ubyte[])str);
    }

    void flush() @safe
    {
        this.file.flush();
    }

    @property bool writeable() @safe { return true; }
}

@safe unittest
{
    import dyaml.dumper, dyaml.loader, dyaml.node;
    import std.file : readText, remove;

    char[] test =  ("Hello World : [Hello, World]\n" ~
                    "Answer: 42").dup;
    //Read the input.
    Node expected = Loader.fromString(test).load();
    assert(expected["Hello World"][0] == "Hello");
    assert(expected["Hello World"][1] == "World");
    assert(expected["Answer"].as!int == 42);

    //Dump the loaded document to output.yaml.
    Dumper("output.yaml").dump(expected);

    // Load the file and verify that it was saved correctly.
    Node actual = Loader("output.yaml").load();
    assert(actual["Hello World"][0] == "Hello");
    assert(actual["Hello World"][1] == "World");
    assert(actual["Answer"].as!int == 42);
    assert(actual == expected);

    // Clean up.
    remove("output.yaml");
}

@safe unittest // #88, #89
{
    import dyaml.dumper, dyaml.loader;
    import std.file : remove, read;

    enum fn = "output.yaml";
    scope (exit) fn.remove;

    auto dumper = Dumper(fn);
    dumper.YAMLVersion = null; // supress directive
    dumper.dump(Loader.fromString("Hello world".dup).load);

    assert (fn.read()[0..3] == "Hel");
}
