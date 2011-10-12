
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.testinputoutput;


import std.array;
import std.file;
import std.system;

import dyaml.testcommon;


alias std.system.endian endian;

/**
 * Get an UTF-16 byte order mark.
 *
 * Params:  wrong = Get the incorrect BOM for this system.
 *
 * Returns: UTF-16 byte order mark.
 */
wchar bom16(bool wrong = false) pure
{
    wchar little  = *(cast(wchar*)ByteOrderMarks[BOM.UTF16LE]);
    wchar big     = *(cast(wchar*)ByteOrderMarks[BOM.UTF16BE]);
    if(!wrong){return endian == Endian.littleEndian ? little : big;}
    return endian == Endian.littleEndian ? big : little;
}

/**
 * Get an UTF-32 byte order mark.
 *
 * Params:  wrong = Get the incorrect BOM for this system.
 *
 * Returns: UTF-32 byte order mark.
 */
dchar bom32(bool wrong = false) pure
{
    dchar little = *(cast(dchar*)ByteOrderMarks[BOM.UTF32LE]);
    dchar big    = *(cast(dchar*)ByteOrderMarks[BOM.UTF32BE]);
    if(!wrong){return endian == Endian.littleEndian ? little : big;}
    return endian == Endian.littleEndian ? big : little;
}

/**
 * Unicode input unittest. Tests various encodings.
 *
 * Params:  verbose         = Print verbose output?
 *          unicodeFilename = File name to read from.
 */
void testUnicodeInput(bool verbose, string unicodeFilename)
{
    string data     = readText(unicodeFilename);
    string expected = data.split().join(" ");

    Node output = Loader(new MemoryStream(to!(char[])(data))).load();
    assert(output.get!string == expected);

    foreach(stream; [new MemoryStream(cast(byte[])(bom16() ~ to!(wchar[])(data))),
                     new MemoryStream(cast(byte[])(bom32() ~ to!(dchar[])(data)))])    
    {
        output = Loader(stream).load();
        assert(output.get!string == expected);
    }
}

/**
 * Unicode input error unittest. Tests various encodings with incorrect BOMs.
 *
 * Params:  verbose         = Print verbose output?
 *          unicodeFilename = File name to read from.
 */
void testUnicodeInputErrors(bool verbose, string unicodeFilename)
{
    string data = readText(unicodeFilename);
    foreach(stream; [new MemoryStream(cast(byte[])(to!(wchar[])(data))),
                     new MemoryStream(cast(byte[])(to!(wchar[])(data))),
                     new MemoryStream(cast(byte[])(bom16(true) ~ to!(wchar[])(data))),
                     new MemoryStream(cast(byte[])(bom32(true) ~ to!(dchar[])(data)))])
    {
        try{Loader(stream).load();}
        catch(YAMLException e)
        {
            if(verbose){writeln(typeid(e).toString(), "\n", e);}
            continue;
        }
        assert(false, "Expected an exception");
    }
}


unittest
{
    writeln("D:YAML I/O unittest");
    run("testUnicodeInput", &testUnicodeInput, ["unicode"]);
    run("testUnicodeInputErrors", &testUnicodeInputErrors, ["unicode"]);
}
