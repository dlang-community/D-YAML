
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.testcompare;


import dyaml.testcommon;
import dyaml.token;


/**
 * Test parser by comparing output from parsing two equivalent YAML files.
 *
 * Params:  verbose           = Print verbose output?
 *          dataFilename      = YAML file to parse.
 *          canonicalFilename = Another file to parse, in canonical YAML format.
 */
void testParser(bool verbose, string dataFilename, string canonicalFilename)
{
    auto dataEvents = Loader(dataFilename).parse();
    auto canonicalEvents = Loader(canonicalFilename).parse();

    assert(dataEvents.length == canonicalEvents.length);
           

    foreach(e; 0 .. dataEvents.length)
    {
        assert(dataEvents[e].id == canonicalEvents[e].id);
    }
}


/**
 * Test loader by comparing output from loading two equivalent YAML files.
 *
 * Params:  verbose           = Print verbose output?
 *          dataFilename      = YAML file to load.
 *          canonicalFilename = Another file to load, in canonical YAML format.
 */
void testLoader(bool verbose, string dataFilename, string canonicalFilename)
{
    auto data = loadAll(dataFilename);
    auto canonical = loadAll(canonicalFilename);

    assert(data.length == canonical.length);
    foreach(n; 0 .. data.length)
    {
        assert(data[n] == canonical[n]);
    }
}


unittest
{
    writeln("D:YAML comparison unittest");
    run("testParser", &testParser, ["data", "canonical"]);
    run("testLoader", &testLoader, ["data", "canonical"], ["test_loader_skip"]);
}
