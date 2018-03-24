
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.reader;


version(unittest)
{

import dyaml.test.common;
import dyaml.reader;


// Try reading entire file through Reader, expecting an error (the file is invalid).
//
// Params:  verbose = Print verbose output?
//          data    = Stream to read.
void runReader(const bool verbose, ubyte[] fileData) @safe
{
    try
    {
        auto reader = new Reader(cast(ubyte[])fileData);
        while(reader.peek() != '\0') { reader.forward(); }
    }
    catch(ReaderException e)
    {
        printException(e, verbose);
        return;
    }
    assert(false, "Expected an exception");
}


/// Stream error unittest. Tries to read invalid input files, expecting errors.
///
/// Params:  verbose       = Print verbose output?
///          errorFilename = File name to read from.
void testStreamError(bool verbose, string errorFilename) @safe
{
    runReader(verbose, readData(errorFilename));
}

// TODO: remove when a @safe ubyte[] file read can be done.
ubyte[] readData(string filename) @trusted
{
    import std.file;
    return cast(ubyte[])std.file.read(filename);
}

@safe unittest
{
    writeln("D:YAML Reader unittest");
    run("testStreamError", &testStreamError, ["stream-error"]);
}

} // version(unittest)
