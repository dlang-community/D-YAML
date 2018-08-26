
//          Copyright Ferdinand Majerech 2011-2014
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.errors;


version(unittest)
{

import std.file;

import dyaml.test.common;


/// Loader error unittest from file stream.
///
/// Params:  errorFilename = File name to read from.
void testLoaderError(string errorFilename) @safe
{
    import std.array : array;
    Node[] nodes;
    try { nodes = Loader.fromFile(errorFilename).array; }
    catch(YAMLException e)
    {
        printException(e);
        return;
    }
    assert(false, "Expected an exception");
}

/// Loader error unittest from string.
///
/// Params:  errorFilename = File name to read from.
void testLoaderErrorString(string errorFilename) @safe
{
    import std.array : array;
    try
    {
        auto nodes = Loader.fromFile(errorFilename).array;
    }
    catch(YAMLException e)
    {
        printException(e);
        return;
    }
    assert(false, "Expected an exception");
}

/// Loader error unittest from filename.
///
/// Params:  errorFilename = File name to read from.
void testLoaderErrorFilename(string errorFilename) @safe
{
    import std.array : array;
    try { auto nodes = Loader.fromFile(errorFilename).array; }
    catch(YAMLException e)
    {
        printException(e);
        return;
    }
    assert(false, "testLoaderErrorSingle(" ~ ", " ~ errorFilename ~
                 ") Expected an exception");
}

/// Loader error unittest loading a single document from a file.
///
/// Params:  errorFilename = File name to read from.
void testLoaderErrorSingle(string errorFilename) @safe
{
    try { auto nodes = Loader.fromFile(errorFilename).load(); }
    catch(YAMLException e)
    {
        printException(e);
        return;
    }
    assert(false, "Expected an exception");
}

@safe unittest
{
    printProgress("D:YAML Errors unittest");
    run("testLoaderError",         &testLoaderError,         ["loader-error"]);
    run("testLoaderErrorString",   &testLoaderErrorString,   ["loader-error"]);
    run("testLoaderErrorFilename", &testLoaderErrorFilename, ["loader-error"]);
    run("testLoaderErrorSingle",   &testLoaderErrorSingle,   ["single-loader-error"]);
}

} // version(unittest)
