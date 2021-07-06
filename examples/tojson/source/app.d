module dyaml.tojson;

import mir.timestamp;
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
    final switch (node.type)
    {
        case NodeType.sequence:
            output = JSONValue(string[].init);
            foreach (Node seqNode; node)
            {
                output.array ~= seqNode.toJSON();
            }
            break;
        case NodeType.mapping:
            output = JSONValue(string[string].init);
            foreach (Node keyNode, Node valueNode; node)
            {
                output[keyNode.as!string] = valueNode.toJSON();
            }
            break;
        case NodeType.string:
            output = node.as!string;
            break;
        case NodeType.integer:
            output = node.as!long;
            break;
        case NodeType.decimal:
            output = node.as!double;
            break;
        case NodeType.boolean:
            output = node.as!bool;
            break;
        case NodeType.timestamp:
            output = node.as!Timestamp.toISOExtString;
            break;
        case NodeType.merge:
        case NodeType.null_:
        case NodeType.binary:
    }
    return output;
}
