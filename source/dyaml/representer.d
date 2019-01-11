
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML node _representer. Prepares YAML nodes for output. A tutorial can be
 * found $(LINK2 ../tutorials/custom_types.html, here).
 *
 * Code based on $(LINK2 http://www.pyyaml.org, PyYAML).
 */
module dyaml.representer;


import std.algorithm;
import std.array;
import std.base64;
import std.container;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.math;
import std.typecons;
import std.string;

import dyaml.exception;
import dyaml.node;
import dyaml.serializer;
import dyaml.style;

package:
///Exception thrown on Representer errors.
class RepresenterException : YAMLException
{
    mixin ExceptionCtors;
}

/**
 * Represents YAML nodes as scalar, sequence and mapping nodes ready for output.
 */
Node representData(const Node data, ScalarStyle defaultScalarStyle, CollectionStyle defaultCollectionStyle) @safe
{
    Node result;
    final switch(data.newType) {
        case NodeType.null_:
            result = representNull();
            break;
        case NodeType.merge:
            break;
        case NodeType.boolean:
            result = representBool(data);
            break;
        case NodeType.integer:
            result = representLong(data);
            break;
        case NodeType.decimal:
            result = representReal(data);
            break;
        case NodeType.binary:
            result = representBytes(data);
            break;
        case NodeType.timestamp:
            result = representSysTime(data);
            break;
        case NodeType.string:
            result = representString(data);
            break;
        case NodeType.mapping:
            result = representPairs(data, defaultScalarStyle, defaultCollectionStyle);
            break;
        case NodeType.sequence:
            result = representNodes(data, defaultScalarStyle, defaultCollectionStyle);
            break;
    }

    if (result.isScalar && (result.scalarStyle == ScalarStyle.invalid))
    {
        result.scalarStyle = defaultScalarStyle;
    }

    if ((result.isSequence || result.isMapping) && (defaultCollectionStyle != CollectionStyle.invalid))
    {
        result.collectionStyle = defaultCollectionStyle;
    }

    //Override tag if specified.
    if(data.tag_ !is null){result.tag_ = data.tag_;}

    //Remember style if this was loaded before.
    if(data.scalarStyle != ScalarStyle.invalid)
    {
        result.scalarStyle = data.scalarStyle;
    }
    if(data.collectionStyle != CollectionStyle.invalid)
    {
        result.collectionStyle = data.collectionStyle;
    }
    return result;
}

private:

//Represent a _null _node as a _null YAML value.
Node representNull() @safe
{
    return Node("null", "tag:yaml.org,2002:null");
}

//Represent a string _node as a string scalar.
Node representString(const Node node) @safe
{
    string value = node.as!string;
    return value is null
           ? Node("null", "tag:yaml.org,2002:null")
           : Node(value, "tag:yaml.org,2002:str");
}

//Represent a bytes _node as a binary scalar.
Node representBytes(const Node node) @safe
{
    const ubyte[] value = node.as!(ubyte[]);
    if(value is null){return Node("null", "tag:yaml.org,2002:null");}

    auto newNode = Node(Base64.encode(value).idup, "tag:yaml.org,2002:binary");
    newNode.scalarStyle = ScalarStyle.literal;
    return newNode;
}

//Represent a bool _node as a bool scalar.
Node representBool(const Node node) @safe
{
    return Node(node.as!bool ? "true" : "false", "tag:yaml.org,2002:bool");
}

//Represent a long _node as an integer scalar.
Node representLong(const Node node) @safe
{
    return Node(node.as!long.to!string, "tag:yaml.org,2002:int");
}

//Represent a real _node as a floating point scalar.
Node representReal(const Node node) @safe
{
    real f = node.as!real;
    string value = isNaN(f)                  ? ".nan":
                   f == real.infinity        ? ".inf":
                   f == -1.0 * real.infinity ? "-.inf":
                   {auto a = appender!string();
                    formattedWrite(a, "%12f", f);
                    return a.data.strip();}();

    return Node(value, "tag:yaml.org,2002:float");
}

//Represent a SysTime _node as a timestamp.
Node representSysTime(const Node node) @safe
{
    return Node(node.as!SysTime.toISOExtString(), "tag:yaml.org,2002:timestamp");
}

//Represent a sequence _node as sequence/set.
Node representNodes(const Node node, ScalarStyle defaultScalarStyle, CollectionStyle defaultCollectionStyle) @safe
{
    auto nodes = node.as!(Node[]);
    if(node.tag_ == "tag:yaml.org,2002:set")
    {
        //YAML sets are mapping with null values.
        Node.Pair[] pairs;
        pairs.length = nodes.length;
        Node dummy;
        foreach(idx, key; nodes)
        {
            pairs[idx] = Node.Pair(key, Node("null", "tag:yaml.org,2002:null"));
        }
        Node.Pair[] value;
        value.length = pairs.length;

        auto bestStyle = CollectionStyle.flow;
        foreach(idx, pair; pairs)
        {
            value[idx] = Node.Pair(representData(pair.key, defaultScalarStyle, defaultCollectionStyle), representData(pair.value, defaultScalarStyle, defaultCollectionStyle));
            if(value[idx].shouldUseBlockStyle)
            {
                bestStyle = CollectionStyle.block;
            }
        }

        auto newNode = Node(value, node.tag_);
        newNode.collectionStyle = bestStyle;
        return newNode;
    }
    else
    {
        Node[] value;
        value.length = nodes.length;

        auto bestStyle = CollectionStyle.flow;
        foreach(idx, item; nodes)
        {
            value[idx] = representData(item, defaultScalarStyle, defaultCollectionStyle);
            const isScalar = value[idx].isScalar;
            const s = value[idx].scalarStyle;
            if(!isScalar || (s != ScalarStyle.invalid && s != ScalarStyle.plain))
            {
                bestStyle = CollectionStyle.block;
            }
        }

        auto newNode = Node(value, "tag:yaml.org,2002:seq");
        newNode.collectionStyle = bestStyle;
        return newNode;
    }
}

bool shouldUseBlockStyle(const Node value) @safe
{
    const isScalar = value.isScalar;
    const s = value.scalarStyle;
    return (!isScalar || (s != ScalarStyle.invalid && s != ScalarStyle.plain));
}
bool shouldUseBlockStyle(const Node.Pair value) @safe
{
    const keyScalar = value.key.isScalar;
    const valScalar = value.value.isScalar;
    const keyStyle = value.key.scalarStyle;
    const valStyle = value.value.scalarStyle;
    if(!keyScalar ||
       (keyStyle != ScalarStyle.invalid && keyStyle != ScalarStyle.plain))
    {
        return true;
    }
    if(!valScalar ||
       (valStyle != ScalarStyle.invalid && valStyle != ScalarStyle.plain))
    {
        return true;
    }
    return false;
}

//Represent a mapping _node as map/ordered map/pairs.
Node representPairs(const Node node, ScalarStyle defaultScalarStyle, CollectionStyle defaultCollectionStyle) @safe
{
    auto pairs = node.as!(Node.Pair[]);

    bool hasDuplicates(const Node.Pair[] pairs) @safe
    {
        //TODO this should be replaced by something with deterministic memory allocation.
        auto keys = redBlackTree!Node();
        foreach(pair; pairs)
        {
            if(pair.key in keys){return true;}
            keys.insert(pair.key);
        }
        return false;
    }

    Node[] mapToSequence(const Node.Pair[] pairs) @safe
    {
        Node[] nodes;
        nodes.length = pairs.length;
        foreach(idx, pair; pairs)
        {
            Node.Pair value;

            auto bestStyle = value.shouldUseBlockStyle ? CollectionStyle.block : CollectionStyle.flow;
            value = Node.Pair(representData(pair.key, defaultScalarStyle, defaultCollectionStyle), representData(pair.value, defaultScalarStyle, defaultCollectionStyle));

            auto newNode = Node([value], "tag:yaml.org,2002:map");
            newNode.collectionStyle = bestStyle;
            nodes[idx] = newNode;
        }
        return nodes;
    }

    if(node.tag_ == "tag:yaml.org,2002:omap")
    {
        enforce(!hasDuplicates(pairs),
                new RepresenterException("Duplicate entry in an ordered map"));
        auto sequence = mapToSequence(pairs);
        Node[] value;
        value.length = sequence.length;

        auto bestStyle = CollectionStyle.flow;
        foreach(idx, item; sequence)
        {
            value[idx] = representData(item, defaultScalarStyle, defaultCollectionStyle);
            if(value[idx].shouldUseBlockStyle)
            {
                bestStyle = CollectionStyle.block;
            }
        }

        auto newNode = Node(value, node.tag_);
        newNode.collectionStyle = bestStyle;
        return newNode;
    }
    else if(node.tag_ == "tag:yaml.org,2002:pairs")
    {
        auto sequence = mapToSequence(pairs);
        Node[] value;
        value.length = sequence.length;

        auto bestStyle = CollectionStyle.flow;
        foreach(idx, item; sequence)
        {
            value[idx] = representData(item, defaultScalarStyle, defaultCollectionStyle);
            if(value[idx].shouldUseBlockStyle)
            {
                bestStyle = CollectionStyle.block;
            }
        }

        auto newNode = Node(value, node.tag_);
        newNode.collectionStyle = bestStyle;
        return newNode;
    }
    else
    {
        enforce(!hasDuplicates(pairs),
                new RepresenterException("Duplicate entry in an unordered map"));
        Node.Pair[] value;
        value.length = pairs.length;

        auto bestStyle = CollectionStyle.flow;
        foreach(idx, pair; pairs)
        {
            value[idx] = Node.Pair(representData(pair.key, defaultScalarStyle, defaultCollectionStyle), representData(pair.value, defaultScalarStyle, defaultCollectionStyle));
            if(value[idx].shouldUseBlockStyle)
            {
                bestStyle = CollectionStyle.block;
            }
        }

        auto newNode = Node(value, "tag:yaml.org,2002:map");
        newNode.collectionStyle = bestStyle;
        return newNode;
    }
}
