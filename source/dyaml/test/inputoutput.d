
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.inputoutput;


version(unittest)
{

import std.array;
import std.file;
import std.system;

import dyaml.test.common;
import dyaml.stream;


alias std.system.endian endian;

/// Get an UTF-16 byte order mark.
///
/// Params:  wrong = Get the incorrect BOM for this system.
///
/// Returns: UTF-16 byte order mark.
wchar bom16(bool wrong = false) pure
{
    wchar little  = *(cast(wchar*)ByteOrderMarks[BOM.UTF16LE]);
    wchar big     = *(cast(wchar*)ByteOrderMarks[BOM.UTF16BE]);
    if(!wrong){return endian == Endian.littleEndian ? little : big;}
    return endian == Endian.littleEndian ? big : little;
}

/// Get an UTF-32 byte order mark.
///
/// Params:  wrong = Get the incorrect BOM for this system.
///
/// Returns: UTF-32 byte order mark.
dchar bom32(bool wrong = false) pure
{
    dchar little = *(cast(dchar*)ByteOrderMarks[BOM.UTF32LE]);
    dchar big    = *(cast(dchar*)ByteOrderMarks[BOM.UTF32BE]);
    if(!wrong){return endian == Endian.littleEndian ? little : big;}
    return endian == Endian.littleEndian ? big : little;
}

/// Unicode input unittest. Tests various encodings.
///
/// Params:  verbose         = Print verbose output?
///          unicodeFilename = File name to read from.
void testUnicodeInput(bool verbose, string unicodeFilename)
{
    string data     = readText(unicodeFilename);
    string expected = data.split().join(" ");

    Node output = Loader(cast(void[])data.to!(char[])).load();
    assert(output.as!string == expected);

    foreach(buffer; [cast(void[])(bom16() ~ data.to!(wchar[])),
                     cast(void[])(bom32() ~ data.to!(dchar[]))])
    {
        output = Loader(buffer).load();
        assert(output.as!string == expected);
    }
}

/// Unicode input error unittest. Tests various encodings with incorrect BOMs.
///
/// Params:  verbose         = Print verbose output?
///          unicodeFilename = File name to read from.
void testUnicodeInputErrors(bool verbose, string unicodeFilename)
{
    string data = readText(unicodeFilename);
    foreach(buffer; [cast(void[])(data.to!(wchar[])),
                     cast(void[])(data.to!(dchar[])),
                     cast(void[])(bom16(true) ~ data.to!(wchar[])),
                     cast(void[])(bom32(true) ~ data.to!(dchar[]))])
    {
        try { Loader(buffer).load(); }
        catch(YAMLException e)
        {
            if(verbose) { writeln(typeid(e).toString(), "\n", e); }
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

} // version(unittest)
