#!/usr/bin/rdmd

//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

version(unittest)
{
    import dyaml.all;


    import dyaml.testcompare;
    import dyaml.testconstructor;
    import dyaml.testemitter;
    import dyaml.testerrors;
    import dyaml.testinputoutput;
    import dyaml.testreader;
    import dyaml.testrepresenter;
    import dyaml.testresolver;
    import dyaml.testtokens;
}

void main(string[] args)
{
    import std.stdio;
    version(unittest)
    {
        writeln("Done");
    }
    else 
    {
        writeln("This is not a unittest build. Trying to build one.");

        void build(string type)
        {
            import std.process;
            const processArgs = ["dub", "build", "-c=unittest", "-b=" ~ type ~ "-unittest"];
            if(spawnProcess(processArgs).wait() != 0)
            {
                writeln("Build failed!");
            }
        }
        import std.algorithm;
        import std.array;
        args.popFront();
        if(args.empty)
        {
            build("debug");
        }
        else if(["debug", "release", "profile"].canFind(args[0]))
        {
            build(args[0]);
        }
        else 
        {
            writeln("Unknown unittest build type: ", args[0]);
        }
    }
}

