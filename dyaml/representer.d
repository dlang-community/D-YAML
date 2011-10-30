
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
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.math;
import std.stream;

import dyaml.exception;
import dyaml.node;
import dyaml.serializer;
import dyaml.style;
import dyaml.tag;


///Exception thrown on Representer errors.
class RepresenterException : YAMLException
{
    mixin ExceptionCtors;
}

/**
 * Represents YAML nodes of various data types as scalar, sequence and mapping nodes ready for output.
 *
 * This class is used to add support for dumping of custom data types.
 *
 * It can also override default node formatting styles for output.
 */
final class Representer
{
    private:
        ///Representer functions indexed by types.
        Node function(ref Node, Representer)[TypeInfo] representers_;
        ///Default style for scalar nodes.
        ScalarStyle defaultScalarStyle_ = ScalarStyle.Invalid;
        ///Default style for collection nodes.
        CollectionStyle defaultCollectionStyle_ = CollectionStyle.Invalid;

    public:
        @disable bool opEquals(ref Representer);
        @disable int opCmp(ref Representer);

        /**
         * Construct a Representer.
         * 
         * Params:  useDefaultRepresenters = Use default representer functions
         *                                   for default YAML types? This can be
         *                                   disabled to use custom representer
         *                                   functions for default types.
         */
        this(in bool useDefaultRepresenters = true)
        {
            if(!useDefaultRepresenters){return;}
            addRepresenter!YAMLNull(&representNull);
            addRepresenter!string(&representString);
            addRepresenter!(ubyte[])(&representBytes);
            addRepresenter!bool(&representBool);
            addRepresenter!long(&representLong);
            addRepresenter!real(&representReal);
            addRepresenter!(Node[])(&representNodes);
            addRepresenter!(Node.Pair[])(&representPairs);
            addRepresenter!SysTime(&representSysTime);
        }

        ///Destroy the Representer.
        ~this()
        {
            clear(representers_);
            representers_ = null;
        }

        ///Set default _style for scalars. Invalid means the _style is chosen automatically.
        @property void defaultScalarStyle(in ScalarStyle style)
        {
            defaultScalarStyle_ = style;
        }

        ///Set default _style for collections. Invalid means the _style is chosen automatically. 
        @property void defaultCollectionStyle(in CollectionStyle style)
        {
            defaultCollectionStyle_ = style;
        }

        /**
         * Add a function to represent nodes with a specific data type.
         *
         * The representer function takes references to a Node storing the data
         * type and to the Representer. It returns the represented node and may
         * throw a RepresenterException. See the example for more information.
         * 
         * Only one function may be specified for one data type. Default data 
         * types already have representer functions unless disabled in the
         * Representer constructor.
         *
         * Params:  representer = Representer function to add.
         *
         * Examples:
         *
         * Representing a simple struct:
         * --------------------
         * import std.string;
         *
         * import yaml;
         *
         * struct MyStruct
         * {
         *     int x, y, z;
         * }
         *
         * Node representMyStruct(ref Node node, Representer representer)
         * { 
         *     //The node is guaranteed to be MyStruct as we add representer for MyStruct.
         *     auto value = node.as!MyStruct;
         *     //Using custom scalar format, x:y:z.
         *     auto scalar = format(value.x, ":", value.y, ":", value.z);
         *     //Representing as a scalar, with custom tag to specify this data type.
         *     return representer.representScalar("!mystruct.tag", scalar);
         * }
         *
         * void main()
         * {
         *     auto dumper = Dumper("file.yaml");
         *     auto representer = new Representer;
         *     representer.addRepresenter!MyStruct(&representMyStruct);
         *     dumper.representer = representer;
         *     dumper.dump(Node(MyStruct(1,2,3)));
         * }
         * --------------------
         *
         * Representing a class:
         * --------------------
         * import std.string;
         *
         * import yaml;
         *
         * class MyClass
         * {
         *     int x, y, z;
         *
         *     this(int x, int y, int z)
         *     {
         *         this.x = x; 
         *         this.y = y; 
         *         this.z = z;
         *     }
         *
         *     ///We need custom opEquals for node equality, as default opEquals compares references.
         *     override bool opEquals(Object rhs)
         *     {
         *         if(typeid(rhs) != typeid(MyClass)){return false;}
         *         auto t = cast(MyClass)rhs;
         *         return x == t.x && y == t.y && z == t.z;
         *     }
         *
         *     ///Useful for Node.as!string .
         *     override string toString()
         *     {
         *         return format("MyClass(", x, ", ", y, ", ", z, ")");
         *     }
         * }
         *
         * //Same as representMyStruct.
         * Node representMyClass(ref Node node, Representer representer)
         * { 
         *     //The node is guaranteed to be MyClass as we add representer for MyClass.
         *     auto value = node.as!MyClass;
         *     //Using custom scalar format, x:y:z.
         *     auto scalar = format(value.x, ":", value.y, ":", value.z);
         *     //Representing as a scalar, with custom tag to specify this data type.
         *     return representer.representScalar("!myclass.tag", scalar);
         * }
         *
         * void main()
         * {
         *     auto dumper = Dumper("file.yaml");
         *     auto representer = new Representer;
         *     representer.addRepresenter!MyClass(&representMyClass);
         *     dumper.representer = representer;
         *     dumper.dump(Node(new MyClass(1,2,3)));
         * }
         * --------------------
         */
        void addRepresenter(T)(Node function(ref Node, Representer) representer)
        {
            assert((typeid(T) in representers_) is null, 
                   "Representer function for data type " ~ typeid(T).toString() ~
                   " already specified. Can't specify another one");
            representers_[typeid(T)] = representer;
        }

        //If profiling shows a bottleneck on tag construction in these 3 methods,
        //we'll need to take Tag directly and have string based wrappers for 
        //user code.

        /**
         * Represent a _scalar with specified _tag.
         *
         * This is used by representer functions that produce scalars.
         *
         * Params:  tag    = Tag of the _scalar.
         *          scalar = Scalar value.
         *          style  = Style of the _scalar. If invalid, default _style will be used.
         *                   If the node was loaded before, previous _style will always be used.
         *
         * Returns: The represented node.
         *
         * Example:
         * --------------------
         * struct MyStruct
         * {
         *     int x, y, z;
         * }
         *
         * Node representMyStruct(ref Node node, Representer representer)
         * { 
         *     auto value = node.as!MyStruct;
         *     auto scalar = format(value.x, ":", value.y, ":", value.z);
         *     return representer.representScalar("!mystruct.tag", scalar);
         *
         * }
         * --------------------
         */
        Node representScalar(in string tag, string scalar, 
                             ScalarStyle style = ScalarStyle.Invalid)
        {
            if(style == ScalarStyle.Invalid){style = defaultScalarStyle_;}
            return Node.rawNode(Node.Value(scalar), Mark(), Tag(tag), style,
                                CollectionStyle.Invalid);
        }

        /**
         * Represent a _sequence with specified _tag, representing children first.
         *
         * This is used by representer functions that produce sequences.
         *
         * Params:  tag      = Tag of the sequence.
         *          sequence = Sequence of nodes.
         *          style    = Style of the _sequence. If invalid, default _style will be used.
         *                     If the node was loaded before, previous _style will always be used.
         *
         * Returns: The represented node.
         *
         * Throws:  RepresenterException if a child could not be represented.
         *
         * Example:
         * --------------------
         * struct MyStruct
         * {
         *     int x, y, z;
         * }
         *
         * Node representMyStruct(ref Node node, Representer representer)
         * { 
         *     auto value = node.as!MyStruct;
         *     auto nodes = [Node(value.x), Node(value.y), Node(value.z)];
         *     //use flow style
         *     return representer.representSequence("!mystruct.tag", nodes,
         *                                          CollectionStyle.Flow);
         * }
         * --------------------
         */
        Node representSequence(in string tag, Node[] sequence, 
                               CollectionStyle style = CollectionStyle.Invalid)
        {
            Node[] value;
            value.length = sequence.length;

            auto bestStyle = CollectionStyle.Flow;
            foreach(idx, ref item; sequence)
            {
                value[idx] = representData(item);
                const isScalar = value[idx].isScalar;
                const s = value[idx].scalarStyle;
                if(!isScalar || (s != ScalarStyle.Invalid && s != ScalarStyle.Plain))
                {
                    bestStyle = CollectionStyle.Block;
                }
            }

            if(style == CollectionStyle.Invalid)
            {
                style = defaultCollectionStyle_ != CollectionStyle.Invalid 
                        ? defaultCollectionStyle_
                        : bestStyle;
            }
            return Node.rawNode(Node.Value(value), Mark(), Tag(tag), 
                                ScalarStyle.Invalid, style);
        }

        /**
         * Represent a mapping with specified _tag, representing children first.
         *
         * This is used by representer functions that produce mappings.
         *
         * Params:  tag   = Tag of the mapping.
         *          pairs = Key-value _pairs of the mapping.
         *          style = Style of the _mapping. If invalid, default _style will be used.
         *                  If the node was loaded before, previous _style will always be used.
         *
         * Returns: The represented node.
         *
         * Throws:  RepresenterException if a child could not be represented.
         *
         * Example:
         * --------------------
         * struct MyStruct
         * {
         *     int x, y, z;
         * }
         *
         * Node representMyStruct(ref Node node, Representer representer)
         * { 
         *     auto value = node.as!MyStruct;
         *     auto pairs = [Node.Pair("x", value.x), 
         *                   Node.Pair("y", value.y), 
         *                   Node.Pair("z", value.z)];
         *     return representer.representMapping("!mystruct.tag", pairs);
         * }
         * --------------------
         */
        Node representMapping(in string tag, Node.Pair[] pairs,
                              CollectionStyle style = CollectionStyle.Invalid)
        {
            Node.Pair[] value;
            value.length = pairs.length;

            auto bestStyle = CollectionStyle.Flow;
            foreach(idx, ref pair; pairs)
            {
                value[idx] = Node.Pair(representData(pair.key), representData(pair.value));
                const keyScalar = value[idx].key.isScalar;
                const valScalar = value[idx].value.isScalar;
                const keyStyle = value[idx].key.scalarStyle;
                const valStyle = value[idx].value.scalarStyle;
                if(!keyScalar ||
                   (keyStyle != ScalarStyle.Invalid && keyStyle != ScalarStyle.Plain))
                {
                    bestStyle = CollectionStyle.Block;
                }
                if(!valScalar ||
                   (valStyle != ScalarStyle.Invalid && valStyle != ScalarStyle.Plain))
                {
                    bestStyle = CollectionStyle.Block;
                }
            }
            
            if(style == CollectionStyle.Invalid)
            {
                style = defaultCollectionStyle_ != CollectionStyle.Invalid 
                        ? defaultCollectionStyle_
                        : bestStyle;
            }
            return Node.rawNode(Node.Value(value), Mark(), Tag(tag), 
                                ScalarStyle.Invalid, style);
        }

    package:
        //Represent a node based on its type, and return the represented result.
        Node representData(ref Node data)
        {
            //User types are wrapped in YAMLObject.
            auto type = data.isUserType ? data.as!YAMLObject.type : data.type;

            enforce((type in representers_) !is null,
                    new RepresenterException("No representer function for type " 
                                             ~ type.toString() ~ " , cannot represent."));
            Node result = representers_[type](data, this);

            //Override tag if specified.
            if(!data.tag_.isNull()){result.tag_ = data.tag_;}

            //Remember style if this was loaded before.
            if(data.scalarStyle != ScalarStyle.Invalid)
            {
                result.scalarStyle = data.scalarStyle;
            }
            if(data.collectionStyle != CollectionStyle.Invalid)
            {
                result.collectionStyle = data.collectionStyle;
            }
            return result;
        }

        //Represent a node, serializing with specified Serializer.
        void represent(ref Serializer serializer, ref Node node)
        {
            auto data = representData(node);
            serializer.serialize(data);
        }
}


///Represent a _null _node as a _null YAML value.
Node representNull(ref Node node, Representer representer)
{
    return representer.representScalar("tag:yaml.org,2002:null", "null");
}

///Represent a string _node as a string scalar.
Node representString(ref Node node, Representer representer)
{
    string value = node.as!string;
    return value is null 
           ? representNull(node, representer) 
           : representer.representScalar("tag:yaml.org,2002:str", value);
}

///Represent a bytes _node as a binary scalar.
Node representBytes(ref Node node, Representer representer)
{
    const ubyte[] value = node.as!(ubyte[]);
    if(value is null){return representNull(node, representer);}
    return representer.representScalar("tag:yaml.org,2002:binary", 
                                       cast(string)Base64.encode(value),
                                       ScalarStyle.Literal);
}

///Represent a bool _node as a bool scalar.
Node representBool(ref Node node, Representer representer)
{
    return representer.representScalar("tag:yaml.org,2002:bool", 
                                       node.as!bool ? "true" : "false");
}

///Represent a long _node as an integer scalar.
Node representLong(ref Node node, Representer representer)
{
    return representer.representScalar("tag:yaml.org,2002:int", 
                                       to!string(node.as!long));
}

///Represent a real _node as a floating point scalar.
Node representReal(ref Node node, Representer representer)
{
    real f = node.as!real;
    string value = isNaN(f)                  ? ".nan":
                   f == real.infinity        ? ".inf":
                   f == -1.0 * real.infinity ? "-.inf":
                   {auto a = appender!string;
                    formattedWrite(a, "%12f", f);
                    return a.data;}();

    return representer.representScalar("tag:yaml.org,2002:float", value);
}

///Represent a SysTime _node as a timestamp.
Node representSysTime(ref Node node, Representer representer)
{
    return representer.representScalar("tag:yaml.org,2002:timestamp", 
                                       node.as!SysTime.toISOExtString());
}

///Represent a sequence _node as sequence/set.
Node representNodes(ref Node node, Representer representer)
{
    auto nodes = node.as!(Node[]);
    if(node.tag_ == Tag("tag:yaml.org,2002:set"))
    {
        ///YAML sets are mapping with null values.
        Node.Pair[] pairs;
        pairs.length = nodes.length;
        Node dummy;
        foreach(idx, ref key; nodes)
        {
            pairs[idx] = Node.Pair(key, representNull(dummy, representer));
        }
        return representer.representMapping(node.tag_.get, pairs);
    }
    else
    {
        return representer.representSequence("tag:yaml.org,2002:seq", nodes);
    }
}

///Represent a mapping _node as map/ordered map/pairs.
Node representPairs(ref Node node, Representer representer)
{
    auto pairs = node.as!(Node.Pair[]);

    bool hasDuplicates(Node.Pair[] pairs)
    {
        //TODO The map here should be replaced with something with deterministic.
        //memory allocation if possible.
        bool[Node] map;
        scope(exit){clear(map);}
        foreach(ref pair; pairs)
        {
            if((pair.key in map) !is null){return true;}
            map[pair.key] = true;
        }
        return false;
    }

    Node[] mapToSequence(Node.Pair[] pairs)
    {
        Node[] nodes;
        nodes.length = pairs.length;
        foreach(idx, ref pair; pairs)
        {
            nodes[idx] = representer.representMapping("tag:yaml.org,2002:map", [pair]);
        }
        return nodes;
    }

    if(node.tag_ == Tag("tag:yaml.org,2002:omap"))
    {
        enforce(!hasDuplicates(pairs),
                new RepresenterException("Duplicate entry in an ordered map"));
        return representer.representSequence(node.tag_.get, mapToSequence(pairs));
    }
    else if(node.tag_ == Tag("tag:yaml.org,2002:pairs"))
    {
        return representer.representSequence(node.tag_.get, mapToSequence(pairs));
    }
    else
    {
        enforce(!hasDuplicates(pairs),
                new RepresenterException("Duplicate entry in an unordered map"));
        return representer.representMapping("tag:yaml.org,2002:map", pairs);
    }
}

//Unittests
private:

import std.string;

import dyaml.dumper;

struct MyStruct
{
    int x, y, z;
}

Node representMyStruct(ref Node node, Representer representer)
{ 
    //The node is guaranteed to be MyStruct as we add representer for MyStruct.
    auto value = node.as!MyStruct;
    //Using custom scalar format, x:y:z.
    auto scalar = format(value.x, ":", value.y, ":", value.z);
    //Representing as a scalar, with custom tag to specify this data type.
    return representer.representScalar("!mystruct.tag", scalar);
}

Node representMyStructSeq(ref Node node, Representer representer)
{ 
    auto value = node.as!MyStruct;
    auto nodes = [Node(value.x), Node(value.y), Node(value.z)];
    return representer.representSequence("!mystruct.tag", nodes);
}

Node representMyStructMap(ref Node node, Representer representer)
{ 
    auto value = node.as!MyStruct;
    auto pairs = [Node.Pair("x", value.x), 
                  Node.Pair("y", value.y), 
                  Node.Pair("z", value.z)];
    return representer.representMapping("!mystruct.tag", pairs);
}

class MyClass
{
    int x, y, z;

    this(int x, int y, int z)
    {
        this.x = x; 
        this.y = y; 
        this.z = z;
    }

    ///We need custom opEquals for node equality, as default opEquals compares references.
    override bool opEquals(Object rhs)
    {
        if(typeid(rhs) != typeid(MyClass)){return false;}
        auto t = cast(MyClass)rhs;
        return x == t.x && y == t.y && z == t.z;
    }

    ///Useful for Node.as!string .
    override string toString()
    {
        return format("MyClass(", x, ", ", y, ", ", z, ")");
    }
}

//Same as representMyStruct.
Node representMyClass(ref Node node, Representer representer)
{ 
    //The node is guaranteed to be MyClass as we add representer for MyClass.
    auto value = node.as!MyClass;
    //Using custom scalar format, x:y:z.
    auto scalar = format(value.x, ":", value.y, ":", value.z);
    //Representing as a scalar, with custom tag to specify this data type.
    return representer.representScalar("!myclass.tag", scalar);
}

unittest
{
    foreach(r; [&representMyStruct, 
                &representMyStructSeq, 
                &representMyStructMap])
    {
        auto dumper = Dumper(new MemoryStream());
        auto representer = new Representer;
        representer.addRepresenter!MyStruct(r);
        dumper.representer = representer;
        dumper.dump(Node(MyStruct(1,2,3)));
    }
}

unittest
{
    auto dumper = Dumper(new MemoryStream());
    auto representer = new Representer;
    representer.addRepresenter!MyClass(&representMyClass);
    dumper.representer = representer;
    dumper.dump(Node(new MyClass(1,2,3)));
}
