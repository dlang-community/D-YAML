
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.common;

version(unittest)
{

public import std.conv;
public import std.stdio;
public import dyaml;

import core.exception;
import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.path;
import std.traits;
import std.typecons;

package:

debug(verbose)
{
    enum verbose = true;
    enum quiet = false;
}
else
{
    enum verbose = false;
    debug(noisy) enum quiet = false;
    else enum quiet = true;
}

/**
 * Run an unittest.
 *
 * Params:  testName     = Name of the unittest.
 *          testFunction = Unittest function.
 *          unittestExt  = Extensions of data files needed for the unittest.
 *          skipExt      = Extensions that must not be used for the unittest.
 */
void run(D)(string testName, D testFunction,
                string[] unittestExt, string[] skipExt = [])
{
    immutable string dataDir = __FILE_FULL_PATH__.dirName ~  "/../../../test/data";
    auto testFilenames = findTestFilenames(dataDir);

    Result[] results;
    if(unittestExt.length > 0)
    {
        outer: foreach(base, extensions; testFilenames)
        {
            string[] filenames;
            foreach(ext; unittestExt)
            {
                if(!extensions.canFind(ext)){continue outer;}
                filenames ~= base ~ '.' ~ ext;
            }
            foreach(ext; skipExt)
            {
                if(extensions.canFind(ext)){continue outer;}
            }

            results ~= execute(testName, testFunction, filenames);
        }
    }
    else
    {
        results ~= execute(testName, testFunction, string[].init);
    }
    display(results);
}

/**
 * Prints an exception if verbosity is turned on.
 * Params:  e     = Exception to print.
 */
void printException(YAMLException e) @trusted
{
        static if(verbose) { writeln(typeid(e).toString(), "\n", e); }
}

void printProgress(T...)(T params) @safe
{
    static if(!quiet)
    {
        writeln(params);
    }
}

private:

///Unittest status.
enum TestStatus
{
    success, //Unittest passed.
    failure, //Unittest failed.
    error    //There's an error in the unittest.
}

///Unittest result.
alias Result = Tuple!(string, "name", string[], "filenames", TestStatus, "kind", string, "info");

/**
 * Find unittest input filenames.
 *
 * Params:  dir = Directory to look in.
 *
 * Returns: Test input base filenames and their extensions.
 */
string[][string] findTestFilenames(const string dir) @trusted
{
    //Groups of extensions indexed by base names.
    string[][string] names;
    foreach(string name; dirEntries(dir, SpanMode.shallow))
    {
        if(isFile(name))
        {
            string base = name.stripExtension();
            string ext  = name.extension();
            if(ext is null){ext = "";}
            if(ext[0] == '.'){ext = ext[1 .. $];}

            //If the base name doesn't exist yet, add it; otherwise add new extension.
            names[base] = ((base in names) is null) ? [ext] : names[base] ~ ext;
        }
    }
    return names;
}

/**
 * Recursively copy an array of strings to a tuple to use for unittest function input.
 *
 * Params:  index   = Current index in the array/tuple.
 *          tuple   = Tuple to copy to.
 *          strings = Strings to copy.
 */
void stringsToTuple(uint index, F ...)(ref F tuple, const string[] strings)
in{assert(F.length == strings.length);}
do
{
    tuple[index] = strings[index];
    static if(index > 0){stringsToTuple!(index - 1, F)(tuple, strings);}
}

/**
 * Execute an unittest on specified files.
 *
 * Params:  testName     = Name of the unittest.
 *          testFunction = Unittest function.
 *          filenames    = Names of input files to test with.
 *
 * Returns: Information about the results of the unittest.
 */
Result execute(D)(const string testName, D testFunction,
                      string[] filenames) @trusted
{
    static if(verbose)
    {
        writeln("===========================================================================");
        writeln(testName ~ "(" ~ filenames.join(", ") ~ ")...");
    }

    auto kind = TestStatus.success;
    string info = "";
    try
    {
        //Convert filenames to parameters tuple and call the test function.
        alias F = Parameters!D[0..$];
        F parameters;
        stringsToTuple!(F.length - 1, F)(parameters, filenames);
        testFunction(parameters);
        static if (!quiet){write(".");}
    }
    catch(Throwable e)
    {
        info = to!string(typeid(e)) ~ "\n" ~ to!string(e);
        kind = (typeid(e) is typeid(AssertError)) ? TestStatus.failure : TestStatus.error;
        write((verbose ? to!string(e) : to!string(kind)) ~ " ");
    }

    stdout.flush();

    return Result(testName, filenames, kind, info);
}

/**
 * Display unittest results.
 *
 * Params:  results = Unittest results.
 */
void display(Result[] results) @safe
{
    if(results.length > 0 && !verbose && !quiet){write("\n");}

    size_t failures, errors;

    static if(verbose)
    {
        writeln("===========================================================================");
    }
    //Results of each test.
    foreach(result; results)
    {
        static if(verbose)
        {
            writeln(result.name, "(" ~ result.filenames.join(", ") ~ "): ",
                    to!string(result.kind));
        }

        if(result.kind == TestStatus.success){continue;}

        if(result.kind == TestStatus.failure){++failures;}
        else if(result.kind == TestStatus.error){++errors;}
        writeln(result.info);
        writeln("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    }

    //Totals.
    printProgress("===========================================================================");
    printProgress("TESTS: ", results.length);
    if(failures > 0){writeln("FAILURES: ", failures);}
    if(errors > 0)  {writeln("ERRORS: ", errors);}
}

} // version(unittest)
