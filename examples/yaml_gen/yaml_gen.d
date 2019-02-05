
///Random YAML generator. Used to generate benchmarking inputs.

import std.algorithm;
import std.conv;
import std.datetime;
import std.math;
import std.random;
import std.stdio;
import std.string;
import dyaml;


Node config;
Node function(bool)[string] generators;
auto typesScalar     = ["string", "int", "float", "bool", "timestamp", "binary"];
auto typesScalarKey  = ["string", "int", "float", "timestamp"];
auto typesCollection = ["map","omap", "pairs", "seq", "set"];
ulong minNodesDocument;
ulong totalNodes;

static this()
{
    generators["string"]    = &genString;
    generators["int"]       = &genInt;
    generators["float"]     = &genFloat;
    generators["bool"]      = &genBool;
    generators["timestamp"] = &genTimestamp;
    generators["binary"]    = &genBinary;
    generators["map"]       = &genMap;
    generators["omap"]      = &genOmap;
    generators["pairs"]     = &genPairs;
    generators["seq"]       = &genSeq;
    generators["set"]       = &genSet;
}

real randomNormalized(const string distribution = "linear")
{
    auto generator = Random(unpredictableSeed());
    const r = uniform!"[]"(0.0L, 1.0L, generator);
    switch(distribution)
    {
        case "linear":
            return r;
        case "quadratic":
            return r * r;
        case "cubic":
            return r * r * r;
        default:
            writeln("Unknown random distribution: ", distribution,
                    ", falling back to linear");
            return randomNormalized("linear");
    }
}

long randomLong(const long min, const long max, const string distribution = "linear")
{
    return min + cast(long)round((max - min) * randomNormalized(distribution));
}

real randomReal(const real min, const real max, const string distribution = "linear")
{
    return min + (max - min) * randomNormalized(distribution);
}

dchar randomChar(const dstring chars)
{
    return chars[randomLong(0, chars.length - 1)];
}

string randomType(string[] types)
{
    auto probabilities = new uint[types.length];
    foreach(index, type; types)
    {
        probabilities[index] = config[type]["probability"].as!uint;
    }
    return types[dice(probabilities)];
}

Node genString(bool root = false)
{
    auto range = config["string"]["range"];

    auto alphabet = config["string"]["alphabet"].as!dstring;

    const chars = randomLong(range["min"].as!uint, range["max"].as!uint,
                             range["dist"].as!string);

    dchar[] result = new dchar[chars];
    result[0] = randomChar(alphabet);
    foreach(i; 1 .. chars)
    {
        result[i] = randomChar(alphabet);
    }

    return Node(result.to!string);
}

Node genInt(bool root = false)
{
    auto range = config["int"]["range"];

    const result = randomLong(range["min"].as!int, range["max"].as!int,
                              range["dist"].as!string);

    return Node(result);
}

Node genFloat(bool root = false)
{
    auto range = config["float"]["range"];

    const result = randomReal(range["min"].as!real, range["max"].as!real,
                              range["dist"].as!string);

    return Node(result);
}

Node genBool(bool root = false)
{
    return Node([true, false][randomLong(0, 1)]);
}

Node genTimestamp(bool root = false)
{
    auto range = config["timestamp"]["range"];

    auto hnsecs = randomLong(range["min"].as!ulong, range["max"].as!ulong,
                             range["dist"].as!string);

    if(randomNormalized() <= config["timestamp"]["round-chance"].as!real)
    {
        hnsecs -= hnsecs % 10000000;
    }

    return Node(SysTime(hnsecs));
}

Node genBinary(bool root = false)
{
    auto range = config["binary"]["range"];

    const bytes = randomLong(range["min"].as!uint, range["max"].as!uint,
                             range["dist"].as!string);

    ubyte[] result = new ubyte[bytes];
    foreach(i; 0 .. bytes)
    {
        result[i] = cast(ubyte)randomLong(0, 255);
    }

    return Node(result);
}

Node nodes(const bool root, Node range, const string tag, const bool set = false)
{
    auto types = config["collection-keys"].as!bool ? typesCollection : [];
    types ~= (set ? typesScalarKey : typesScalar);

    Node[] nodes;
    if(root)
    {
        while(!(totalNodes >= minNodesDocument))
        {
            nodes.assumeSafeAppend;
            nodes ~= generateNode(randomType(types));
        }
    }
    else
    {
        const elems = randomLong(range["min"].as!uint, range["max"].as!uint,
                                 range["dist"].as!string);

        nodes = new Node[elems];
        foreach(i; 0 .. elems)
        {
            nodes[i] = generateNode(randomType(types));
        }
    }

    return Node(nodes, tag);
}

Node genSeq(bool root = false)
{
    return nodes(root, config["seq"]["range"], "tag:yaml.org,2002:seq");
}

Node genSet(bool root = false)
{
    return nodes(root, config["seq"]["range"], "tag:yaml.org,2002:set", true);
}

Node pairs(bool root, bool complex, Node range, string tag)
{
    Node[] keys, values;

    if(root)
    {
        while(!(totalNodes >= minNodesDocument))
        {
            const key = generateNode(randomType(typesScalarKey ~ (complex ? typesCollection : [])));
            // Maps can't contain duplicate keys
            if(tag.endsWith("map") && keys.canFind(key)) { continue; }
            keys.assumeSafeAppend;
            values.assumeSafeAppend;
            keys ~= key;
            values ~= generateNode(randomType(typesScalar ~ typesCollection));
        }
    }
    else
    {
        const pairs = randomLong(range["min"].as!uint, range["max"].as!uint,
                                 range["dist"].as!string);

        keys = new Node[pairs];
        values = new Node[pairs];
        outer: foreach(i; 0 .. pairs)
        {
            auto key = generateNode(randomType(typesScalarKey ~ (complex ? typesCollection : [])));
            // Maps can't contain duplicate keys
            while(tag.endsWith("map") && keys[0 .. i].canFind(key))
            {
                key = generateNode(randomType(typesScalarKey ~ (complex ? typesCollection : [])));
            }
            keys[i]   = key;
            values[i] = generateNode(randomType(typesScalar ~ typesCollection));
        }
    }

    return Node(keys, values, tag);
}

Node genMap(bool root = false)
{
    Node range = config["map"]["range"];
    const complex = config["complex-keys"].as!bool;

    return pairs(root, complex, range, "tag:yaml.org,2002:map");
}

Node genOmap(bool root = false)
{
    Node range = config["omap"]["range"];
    const complex = config["complex-keys"].as!bool;

    return pairs(root, complex, range, "tag:yaml.org,2002:omap");
}

Node genPairs(bool root = false)
{
    Node range = config["pairs"]["range"];
    const complex = config["complex-keys"].as!bool;

    return pairs(root, complex, range, "tag:yaml.org,2002:pairs");
}

Node generateNode(const string type, bool root = false)
{
    ++totalNodes;
    return generators[type](root);
}

Node[] generate(const string configFileName)
{
    config = Loader.fromFile(configFileName).load();

    minNodesDocument = config["min-nodes-per-document"].as!long;

    Node[] result;
    foreach(i; 0 .. config["documents"].as!uint)
    {
        result ~= generateNode(config["root-type"].as!string, true);
        totalNodes = 0;
    }

    return result;
}


void main(string[] args)
{
    //Help message.
    if(args.length == 1)
    {
        writeln("Usage: yaml_gen FILE [CONFIG_FILE]\n");
        writeln("Generates a random YAML file and writes it to FILE.");
        writeln("If provided, CONFIG_FILE overrides the default config file.");
        return;
    }

    string configFile = args.length >= 3 ? args[2] : "config.yaml";

    try
    {
        //Generate and dump the nodes.
        Node[] generated = generate(configFile);

        auto dumper     = dumper();
        auto encoding   = config["encoding"];

        dumper.indent = config["indent"].as!uint;
        dumper.textWidth = config["text-width"].as!uint;
        switch(encoding.as!string)
        {
            case "utf-16": dumper.dump!wchar(File(args[1], "w").lockingTextWriter, generated); break;
            case "utf-32": dumper.dump!dchar(File(args[1], "w").lockingTextWriter, generated); break;
            default: dumper.dump!char(File(args[1], "w").lockingTextWriter, generated); break;
        }
    }
    catch(YAMLException e)
    {
        writeln("ERROR: ", e.msg);
    }
}
