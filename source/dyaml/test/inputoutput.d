
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.inputoutput;

@safe unittest
{
    import std.array : join, split;
    import std.conv : to;
    import std.exception : assertThrown;
    import std.file : readText;
    import std.system : endian, Endian;

    import dyaml : Loader, Node, YAMLException;
    import dyaml.test.common : run;

    /**
    Get an UTF-16 byte order mark.

    Params:  wrong = Get the incorrect BOM for this system.

    Returns: UTF-16 byte order mark.
    */
    static wchar bom16(bool wrong = false) pure @safe
    {
        wchar little = '\uFEFF';
        wchar big = '\uFFFE';
        if (!wrong)
        {
            return endian == Endian.littleEndian ? little : big;
        }
        return endian == Endian.littleEndian ? big : little;
    }
    /**
    Get an UTF-32 byte order mark.

    Params:  wrong = Get the incorrect BOM for this system.

    Returns: UTF-32 byte order mark.
    */
    static dchar bom32(bool wrong = false) pure @safe
    {
        dchar little = '\uFEFF';
        dchar big = '\uFFFE';
        if (!wrong)
        {
            return endian == Endian.littleEndian ? little : big;
        }
        return endian == Endian.littleEndian ? big : little;
    }
    /**
    Unicode input unittest. Tests various encodings.

    Params:  unicodeFilename = File name to read from.
    */
    static void testUnicodeInput(string unicodeFilename) @safe
    {
        string data = readText(unicodeFilename);
        string expected = data.split().join(" ");

        Node output = Loader.fromString(data).load();
        assert(output.as!string == expected);

        foreach (buffer; [cast(ubyte[]) (bom16() ~ data.to!(wchar[])),
             cast(ubyte[]) (bom32() ~ data.to!(dchar[]))])
        {
            output = Loader.fromBuffer(buffer).load();
            assert(output.as!string == expected);
        }
    }
    /**
    Unicode input error unittest. Tests various encodings with incorrect BOMs.

    Params:  unicodeFilename = File name to read from.
    */
    static void testUnicodeInputErrors(string unicodeFilename) @safe
    {
        string data = readText(unicodeFilename);
        foreach (buffer; [cast(ubyte[]) (data.to!(wchar[])),
             cast(ubyte[]) (data.to!(dchar[])),
             cast(ubyte[]) (bom16(true) ~ data.to!(wchar[])),
             cast(ubyte[]) (bom32(true) ~ data.to!(dchar[]))])
        {
            assertThrown(Loader.fromBuffer(buffer).load());
        }
    }
    run(&testUnicodeInput, ["unicode"]);
    run(&testUnicodeInputErrors, ["unicode"]);
}
