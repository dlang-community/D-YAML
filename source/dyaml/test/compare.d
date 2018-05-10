
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.compare;


version(unittest)
{

import dyaml.test.common;
import dyaml.token;


/// Test parser by comparing output from parsing two equivalent YAML files.
///
/// Params:  dataFilename      = YAML file to parse.
///          canonicalFilename = Another file to parse, in canonical YAML format.
void testParser(string dataFilename, string canonicalFilename) @safe
{
    auto dataEvents = Loader(dataFilename).parse();
    auto canonicalEvents = Loader(canonicalFilename).parse();

    assert(dataEvents.length == canonicalEvents.length);

    foreach(e; 0 .. dataEvents.length)
    {
        assert(dataEvents[e].id == canonicalEvents[e].id);
    }
}


/// Test loader by comparing output from loading two equivalent YAML files.
///
/// Params:  dataFilename      = YAML file to load.
///          canonicalFilename = Another file to load, in canonical YAML format.
void testLoader(string dataFilename, string canonicalFilename) @safe
{
    auto data = Loader(dataFilename).loadAll();
    auto canonical = Loader(canonicalFilename).loadAll();

    assert(data.length == canonical.length, "Unequal node count");
    foreach(n; 0 .. data.length)
    {
        if(data[n] != canonical[n])
        {
            static if(verbose)
            {
                writeln("Normal value:");
                writeln(data[n].debugString);
                writeln("\n");
                writeln("Canonical value:");
                writeln(canonical[n].debugString);
            }
            assert(false, "testLoader(" ~ dataFilename ~ ", " ~ canonicalFilename ~ ") failed");
        }
    }
}


@safe unittest
{
    printProgress("D:YAML comparison unittest");
    run("testParser", &testParser, ["data", "canonical"]);
    run("testLoader", &testLoader, ["data", "canonical"], ["test_loader_skip"]);
}

} // version(unittest)
