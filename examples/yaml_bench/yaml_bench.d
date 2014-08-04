
module dyaml.yaml_bench;
//Benchmark that loads, and optionally extracts data from and/or emits a YAML file. 

import std.conv;
import std.datetime;
import std.stdio;
import std.string;
import dyaml.all;

///Print help information.
void help()
{
    string help =
        "D:YAML benchmark\n"
        "Copyright (C) 2011-2014 Ferdinand Majerech\n"
        "Usage: yaml_bench [OPTION ...] [YAML_FILE]\n"
        "\n"
        "Loads and optionally extracts data and/or dumps a YAML file.\n"
        "\n"
        "Available options:\n"
        " -h --help          Show this help information.\n"
        " -g --get           Extract data from the file (using Node.as()).\n"
        " -d --dump          Dump the loaded data (to YAML_FILE.dump).\n"
        " -r --runs=NUM      Repeat parsing the file NUM times.\n"
        "    --reload        Reload the file from the diskl on every repeat\n"
        "                    By default, the file is loaded to memory once\n"
        "                    and repeatedly parsed from memory.\n"
        " -s --scan-only    Do not execute the entire parsing process, only\n"
        "                    scanning. Overrides '--dump'.\n";
    writeln(help);
}

///Get data out of every node.
void extract(ref Node document)
{
    void crawl(ref Node root)
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

void main(string[] args)
{
    bool get      = false;
    bool dump     = false;
    bool reload   = false;
    bool scanOnly = false;
    uint runs = 1;
    string file = null;

    //Parse command line args
    foreach(arg; args[1 .. $]) 
    {
        auto parts = arg.split("=");
        if(arg[0] == '-') switch(parts[0]) 
        {
            case "--help", "-h":      help(); return;
            case "--get",  "-g":      get      = true; break;
            case "--dump", "-d":      dump     = true; break;
            case "--reload":          reload   = true; break;
            case "--scan-only", "-s": scanOnly = true; break;
            case "--runs", "-r":      runs     = parts[1].to!uint; break;
            default: writeln("\nUnknown argument: ", arg, "\n\n"); help(); return;
        }
        else
        {
            if(file !is null)
            {
                writeln("\nUnknown argument or file specified twice: ", arg, "\n\n"); 
                help(); 
                return;
            }

            file = arg;
        }
    }
    if(file is null)
    {
        writeln("\nFile not specified.\n\n"); 
        help(); 
        return;
    }

    try
    {
        import std.file;
        void[] fileInMemory;
        if(!reload) { fileInMemory = std.file.read(file); }
        while(runs--)
        {
            if(reload) { fileInMemory = std.file.read(file); }
            if(scanOnly)
            {
                Loader(fileInMemory).scanBench();
                continue;
            }
            auto nodes = Loader(fileInMemory).loadAll();
            if(dump)
            {
                Dumper(file ~ ".dump").dump(nodes);
            }
            if(get) foreach(ref node; nodes)
            {
                extract(node);
            }
        }
    }
    catch(YAMLException e)
    {
        writeln("ERROR: ", e.msg);
    }
}
