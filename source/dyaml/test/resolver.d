
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.resolver;


version(unittest)
{

import std.file;
import std.string;

import dyaml.test.common;


/**
 * Implicit tag resolution unittest.
 *
 * Params:  dataFilename   = File with unittest data.
 *          detectFilename = Dummy filename used to specify which data filenames to use.
 */
void testImplicitResolver(string dataFilename, string detectFilename) @safe
{
    string correctTag;
    Node node;

    scope(failure)
    {
        if(true)
        {
            writeln("Correct tag: ", correctTag);
            writeln("Node: ", node.debugString);
        }
    }

    correctTag = readText(detectFilename).strip();

    node = Loader.fromFile(dataFilename).load();
    assert(node.nodeID == NodeID.sequence);
    foreach(ref Node scalar; node)
    {
        assert(scalar.nodeID == NodeID.scalar);
        assert(scalar.tag == correctTag);
    }
}


@safe unittest
{
    printProgress("D:YAML Resolver unittest");
    run("testImplicitResolver", &testImplicitResolver, ["data", "detect"]);
}

} // version(unittest)
