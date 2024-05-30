
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.representer;

@safe unittest
{
    import std.array : Appender, array;
    import std.conv : text;
    import std.meta : AliasSeq;
    import std.path : baseName, stripExtension;
    import std.utf : toUTF8;

    import dyaml : dumper, Loader, Node;
    import dyaml.test.constructor : expected;

    /**
    Representer unittest. Dumps nodes, then loads them again.

    Params:
        baseName = Nodes in dyaml.test.constructor.expected for roundtripping.
    */
    static void testRepresenterTypes(string baseName) @safe
    {
        assert((baseName in expected) !is null, "Unimplemented representer test: " ~ baseName);

        Node[] expectedNodes = expected[baseName];
        foreach (encoding; AliasSeq!(char, wchar, dchar))
        {
            auto emitStream = new Appender!(immutable(encoding)[]);
            auto dumper = dumper();
            dumper.dump!encoding(emitStream, expectedNodes);

            immutable output = emitStream.data;

            auto loader = Loader.fromString(emitStream.data.toUTF8);
            loader.name = "TEST";
            auto readNodes = loader.array;

            assert(expectedNodes == readNodes, text("Got '", readNodes, "', expected '", expectedNodes, "'"));
        }
    }
    foreach (key, _; expected)
    {
        testRepresenterTypes(key);
    }
}
