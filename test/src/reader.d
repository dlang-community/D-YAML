
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.testreader;


import dyaml.testcommon;
import dyaml.reader;


// Try reading entire stream through Reader, expecting an error (the stream is invalid).
//
// Params:  verbose = Print verbose output?
//          data    = Stream to read.
void runReader(const bool verbose, Stream stream)
{
    try
    {
        auto reader = new Reader(stream);
        while(reader.peek() != '\0') { reader.forward(); }
    }
    catch(ReaderException e)
    {
        if(verbose) { writeln(typeid(e).toString(), "\n", e); }
        return;
    }
    assert(false, "Expected an exception");
}


/// Stream error unittest. Tries to read invalid input streams, expecting errors.
///
/// Params:  verbose       = Print verbose output?
///          errorFilename = File name to read from.
void testStreamError(bool verbose, string errorFilename)
{
    auto file = new File(errorFilename);
    scope(exit) { file.close(); }
    runReader(verbose, file);
}

unittest
{
    writeln("D:YAML Reader unittest");
    run("testStreamError", &testStreamError, ["stream-error"]);
}
