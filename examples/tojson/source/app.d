import std.datetime;
import std.json;
import std.stdio;
import dyaml;

void main()
{
    auto doc = Loader.fromFile(stdin).load();
    auto json = doc.toJSON;
    writeln(json.toPrettyString);
}

JSONValue toJSON(Node node)
{
    JSONValue output;
    if (node.isSequence)
    {
        output = JSONValue(string[].init);
        foreach (Node seqNode; node)
        {
            output.array ~= seqNode.toJSON();
        }
    }
    else if (node.isMapping)
    {
        output = JSONValue(string[string].init);
        foreach (Node keyNode, Node valueNode; node)
        {
            output[keyNode.as!string] = valueNode.toJSON();
        }
    }
    else if (node.isString)
    {
        output = node.as!string;
    }
    else if (node.isInt)
    {
        output = node.as!long;
    }
    else if (node.isFloat)
    {
        output = node.as!real;
    }
    else if (node.isBool)
    {
        output = node.as!bool;
    }
    else if (node.isTime)
    {
        output = node.as!SysTime.toISOExtString();
    }
    return output;
}
