
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.representer;


version(unittest)
{

import std.array;
import std.exception;
import std.meta;
import std.path;
import std.typecons;
import std.utf;

import dyaml.test.common;
import dyaml.test.constructor;


/// Representer unittest.
///
/// Params:  codeFilename = File name to determine test case from.
///                         Nothing is read from this file, it only exists
///                         to specify that we need a matching unittest.
void testRepresenterTypes(string codeFilename) @safe
{
    string baseName = codeFilename.baseName.stripExtension;
    enforce((baseName in dyaml.test.constructor.expected) !is null,
            new Exception("Unimplemented representer test: " ~ baseName));

    Node[] expectedNodes = expected[baseName];
    foreach(encoding; AliasSeq!(char, wchar, dchar))
    {
        immutable(encoding)[] output;
        Node[] readNodes;

        scope(failure)
        {
            static if(verbose)
            {
                writeln("Expected nodes:");
                foreach(ref n; expectedNodes){writeln(n.debugString, "\n---\n");}
                writeln("Read nodes:");
                foreach(ref n; readNodes){writeln(n.debugString, "\n---\n");}
                () @trusted {
                    writeln("OUTPUT:\n", cast(string)output);
                }();
            }
        }

        auto emitStream  = new Appender!(immutable(encoding)[]);
        auto dumper = dumper();
        dumper.dump!encoding(emitStream, expectedNodes);

        output = emitStream.data;

        auto loader        = Loader.fromString(emitStream.data.toUTF8);
        loader.name        = "TEST";
        readNodes          = loader.array;

        assert(expectedNodes.length == readNodes.length);
        foreach(n; 0 .. expectedNodes.length)
        {
            assert(expectedNodes[n] == readNodes[n]);
        }
    }
}

@safe unittest
{
    printProgress("D:YAML Representer unittest");
    run("testRepresenterTypes", &testRepresenterTypes, ["code"]);
}

} // version(unittest)
