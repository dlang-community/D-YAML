
module dyaml.yaml_bench;
//Benchmark that loads, and optionally extracts data from and/or emits a YAML file.

import std.algorithm;
import std.conv;
import std.datetime.systime;
import std.datetime.stopwatch;
import std.file;
import std.getopt;
import std.range;
import std.stdio;
import std.string;
import dyaml;

///Get data out of every node.
void extract(ref Node document) @safe
{
    void crawl(ref Node root) @safe
    {
        if(root.isScalar) switch(root.tag)
        {
            case "tag:yaml.org,2002:null":      auto value = root.as!YAMLNull;  break;
            case "tag:yaml.org,2002:bool":      auto value = root.as!bool;      break;
            case "tag:yaml.org,2002:int":       auto value = root.as!long;      break;
            case "tag:yaml.org,2002:float":     auto value = root.as!real;      break;
            case "tag:yaml.org,2002:binary":    auto value = root.as!(ubyte[]); break;
            case "tag:yaml.org,2002:timestamp": auto value = root.as!SysTime;   break;
            case "tag:yaml.org,2002:str":       auto value = root.as!string;    break;
            default: writeln("Unrecognozed tag: ", root.tag);
        }
        else if(root.isSequence) foreach(ref Node node; root)
        {
            crawl(node);
        }
        else if(root.isMapping) foreach(ref Node key, ref Node value; root)
        {
            crawl(key);
            crawl(value);
        }
    }

    crawl(document);
}

void main(string[] args) //@safe
{
    bool get = false;
    bool dump = false;
    bool reload = false;
    bool quiet = false;
    bool verbose = false;
    bool scanOnly = false;
    uint runs = 1;

    auto help = getopt(
        args,
        "get|g", "Extract data from the file (using Node.as()).", &get,
        "dump|d", "Dump the loaded data (to YAML_FILE.dump).", &dump,
        "runs|r", "Repeat parsing the file NUM times.", &runs,
        "reload", "Reload the file from the diskl on every repeat By default,"~
            " the file is loaded to memory once and repeatedly parsed from memory.", &reload,
        "quiet|q", "Don't print anything.", &quiet,
        "verbose|v", "Print even more.", &verbose,
        "scan-only|s", "Do not execute the entire parsing process, only scanning. Overrides '--dump'", &scanOnly
    );

    if (help.helpWanted || (args.length < 2))
    {
        defaultGetoptPrinter(
            "D:YAML benchmark\n"~
            "Copyright (C) 2011-2018 Ferdinand Majerech, Cameron \"Herringway\" Ross\n"~
            "Usage: yaml_bench [OPTION ...] [YAML_FILE]\n\n"~
            "Loads and optionally extracts data and/or dumps a YAML file.\n",
            help.options
        );
        return;
    }

    string file = args[1];

    auto stopWatch = StopWatch(AutoStart.yes);
    void[] fileInMemory;
    if(!reload) { fileInMemory = std.file.read(file); }
    void[] fileWorkingCopy = fileInMemory.dup;
    auto loadTime = stopWatch.peek();
    stopWatch.reset();
    try
    {
        // Instead of constructing a resolver/constructor with each Loader,
        // construct them once to remove noise when profiling.
        auto resolver    = new Resolver();
        auto constructor = new Constructor();

        auto constructTime = stopWatch.peek();

        Node[] nodes;

        void runLoaderBenchmark() //@safe
        {
            // Loading the file rewrites the loaded buffer, so if we don't reload from
            // disk, we need to use a copy of the originally loaded file.
            if(reload) { fileInMemory = std.file.read(file); }
            else       { fileWorkingCopy[] = fileInMemory[]; }
            void[] fileToLoad = reload ? fileInMemory : fileWorkingCopy;

            auto loader        = Loader.fromBuffer(fileToLoad);
            if(scanOnly)
            {
                loader.scanBench();
                return;
            }

            loader.resolver    = resolver;
            loader.constructor = constructor;
            nodes = loader.loadAll();
        }
        void runDumpBenchmark() @safe
        {
            if(dump)
            {
                dumper(File(file ~ ".dump", "w").lockingTextWriter).dump(nodes);
            }
        }
        void runGetBenchmark() @safe
        {
            if(get) foreach(ref node; nodes)
            {
                extract(node);
            }
        }
        auto totalTime = benchmark!(runLoaderBenchmark, runDumpBenchmark, runGetBenchmark)(runs);
        if (!quiet)
        {
            auto enabledOptions =
                only(
                    get ? "Get" : "",
                    dump ? "Dump" : "",
                    reload ? "Reload" : "",
                    scanOnly ? "Scan Only":  ""
                ).filter!(x => x != "");
            if (!enabledOptions.empty)
            {
                writefln!"Options enabled: %-(%s, %)"(enabledOptions);
            }
            if (verbose)
            {
                if (!reload)
                {
                    writeln("Time to load file: ", loadTime);
                }
                writeln("Time to set up resolver & constructor: ", constructTime);
            }
            writeln("Runs: ", runs);
            foreach(time, func, enabled; lockstep(totalTime[], only("Loader", "Dumper", "Get"), only(true, dump, get)))
            {
                if (enabled)
                {
                    writeln("Average time spent on ", func, ": ", time / runs);
                    writeln("Total time spent on ", func, ": ", time);
                }
            }
        }
    }
    catch(YAMLException e)
    {
        writeln("ERROR: ", e.msg);
    }
}
