
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.testresolver;


import std.file;
import std.string;

import dyaml.testcommon;


/**
 * Implicit tag resolution unittest.
 *
 * Params:  verbose        = Print verbose output?
 *          dataFilename   = TODO 
 *          detectFilename = TODO
 */
void testImplicitResolver(bool verbose, string dataFilename, string detectFilename)
{
    string correctTag;
    Node node;

    scope(exit)
    {
        if(verbose)
        {
            writeln("Correct tag: ", correctTag);
            writeln("Node: ", node.debugString);
            assert(node.isSequence);
            assert(node.tag.get == correctTag);
        }
    }

    correctTag = readText(dataFilename).strip();
    node = yaml.load(dataFilename);
}


unittest
{
    writeln("D:YAML Resolver unittest");
    run("testImplicitResolver", &testImplicitResolver, ["data", "detect"]);
}
