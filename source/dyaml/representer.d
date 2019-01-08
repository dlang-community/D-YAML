
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


///Exception thrown on Representer errors.
class RepresenterException : YAMLException
{
    mixin ExceptionCtors;
}

/**
 * Represents YAML nodes as scalar, sequence and mapping nodes ready for output.
 *
 * This class is used to add support for dumping of custom data types.
 *
 * It can also override default node formatting styles for output.
 */
final class Representer
{
    private:
        // Representer functions indexed by types.
        Node function(ref Node, Representer) @safe[TypeInfo] representers_;
        // Default style for scalar nodes.
        ScalarStyle defaultScalarStyle_ = ScalarStyle.invalid;
        // Default style for collection nodes.
        CollectionStyle defaultCollectionStyle_ = CollectionStyle.invalid;

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
        this(const Flag!"useDefaultRepresenters" useDefaultRepresenters = Yes.useDefaultRepresenters)
            @safe pure
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

        ///Set default _style for scalars. If style is $(D ScalarStyle.invalid), the _style is chosen automatically.
        @property void defaultScalarStyle(ScalarStyle style) pure @safe nothrow
        {
            defaultScalarStyle_ = style;
        }

        ///Set default _style for collections. If style is $(D CollectionStyle.invalid), the _style is chosen automatically.
        @property void defaultCollectionStyle(CollectionStyle style) pure @safe nothrow
        {
            defaultCollectionStyle_ = style;
        }

        /**
         * Add a function to represent nodes with a specific data type.
         *
         * The representer function takes references to a $(D Node) storing the data
         * type and to the $(D Representer). It returns the represented node and may
         * throw a $(D RepresenterException). See the example for more information.
         *
         *
         * Only one function may be specified for one data type. Default data
         * types already have representer functions unless disabled in the
         * $(D Representer) constructor.
         *
         *
         * Structs and classes must implement the $(D opCmp()) operator for D:YAML
         * support. The signature of the operator that must be implemented
         * is $(D const int opCmp(ref const MyStruct s)) for structs where
         * $(I MyStruct) is the struct type, and $(D int opCmp(Object o)) for
         * classes. Note that the class $(D opCmp()) should not alter the compared
         * values - it is not const for compatibility reasons.
         *
         * Params:  representer = Representer function to add.
         */
        void addRepresenter(T)(Node function(ref Node, Representer) @safe representer)
            @safe pure
        {
            assert((typeid(T) in representers_) is null,
                   "Representer function for data type " ~ T.stringof ~
                   " already specified. Can't specify another one");
            representers_[typeid(T)] = representer;
        }
        /// Representing a simple struct:
        unittest {
            import std.string;

            import dyaml;

            struct MyStruct
            {
                int x, y, z;

                //Any D:YAML type must have a custom opCmp operator.
                //This is used for ordering in mappings.
                const int opCmp(ref const MyStruct s)
                {
                    if(x != s.x){return x - s.x;}
                    if(y != s.y){return y - s.y;}
                    if(z != s.z){return z - s.z;}
                    return 0;
                }
                Node opCast(T: Node)() @safe
                {
                    //Using custom scalar format, x:y:z.
                    auto scalar = format("%s:%s:%s", x, y, z);
                    //Representing as a scalar, with custom tag to specify this data type.
                    return Node(scalar, "!mystruct.tag");
                }
            }


            auto dumper = dumper(new Appender!string);
            dumper.dump(Node(MyStruct(1,2,3)));
        }
        /// Representing a class:
        unittest {
            import std.string;

            import dyaml;

            class MyClass
            {
                int x, y, z;

                this(int x, int y, int z)
                {
                    this.x = x;
                    this.y = y;
                    this.z = z;
                }

                //Any D:YAML type must have a custom opCmp operator.
                //This is used for ordering in mappings.
                override int opCmp(Object o)
                {
                    MyClass s = cast(MyClass)o;
                    if(s is null){return -1;}
                    if(x != s.x){return x - s.x;}
                    if(y != s.y){return y - s.y;}
                    if(z != s.z){return z - s.z;}
                    return 0;
                }

                ///Useful for Node.as!string .
                override string toString()
                {
                    return format("MyClass(%s, %s, %s)", x, y, z);
                }

                Node opCast(T: Node)() @safe
                {
                    //Using custom scalar format, x:y:z.
                    auto scalar = format("%s:%s:%s", x, y, z);
                    //Representing as a scalar, with custom tag to specify this data type.
                    return Node(scalar, "!myclass.tag");
                }
            }

            auto dumper = dumper(new Appender!string);
            dumper.dump(Node(new MyClass(1,2,3)));
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
         */
        Node representScalar(string tag, string scalar,
                             ScalarStyle style = ScalarStyle.invalid) @safe
        {
            if(style == ScalarStyle.invalid){style = defaultScalarStyle_;}
            auto newNode = Node(scalar, tag);
            newNode.scalarStyle = style;
            return newNode;
        }
        ///
        @safe unittest
        {
            import dyaml.dumper : dumper;
            struct MyStruct
            {
                int x, y, z;

                //Any D:YAML type must have a custom opCmp operator.
                //This is used for ordering in mappings.
                const int opCmp(ref const MyStruct s)
                {
                    if(x != s.x){return x - s.x;}
                    if(y != s.y){return y - s.y;}
                    if(z != s.z){return z - s.z;}
                    return 0;
                }
                Node opCast(T: Node)()
                {
                    auto scalar = format("%s:%s:%s", x, y, z);
                    return Node(scalar, "!mystruct.tag");
                }
            }

            dumper(new Appender!string).dump(Node(MyStruct(1,2,3)));
        }

        /**
         * Represent a _sequence with specified _tag, representing children first.
         *
         * This is used by representer functions that produce sequences.
         *
         * Params:  tag      = Tag of the _sequence.
         *          sequence = Sequence of nodes.
         *          style    = Style of the _sequence. If invalid, default _style will be used.
         *                     If the node was loaded before, previous _style will always be used.
         *
         * Returns: The represented node.
         *
         * Throws:  $(D RepresenterException) if a child could not be represented.
         */
        Node representSequence(string tag, Node[] sequence,
                               CollectionStyle style = CollectionStyle.invalid) @safe
        {
            Node[] value;
            value.length = sequence.length;

            auto bestStyle = CollectionStyle.flow;
            foreach(idx, ref item; sequence)
            {
                value[idx] = representData(item);
                const isScalar = value[idx].isScalar;
                const s = value[idx].scalarStyle;
                if(!isScalar || (s != ScalarStyle.invalid && s != ScalarStyle.plain))
                {
                    bestStyle = CollectionStyle.block;
                }
            }

            if(style == CollectionStyle.invalid)
            {
                style = defaultCollectionStyle_ != CollectionStyle.invalid
                        ? defaultCollectionStyle_
                        : bestStyle;
            }
            auto newNode = Node(value, tag);
            newNode.collectionStyle = style;
            return newNode;
        }
        ///
        @safe unittest
        {
            import dyaml.dumper : dumper;
            struct MyStruct
            {
                int x, y, z;

                //Any D:YAML type must have a custom opCmp operator.
                //This is used for ordering in mappings.
                const int opCmp(ref const MyStruct s)
                {
                    if(x != s.x){return x - s.x;}
                    if(y != s.y){return y - s.y;}
                    if(z != s.z){return z - s.z;}
                    return 0;
                }
                Node opCast(T: Node)()
                {
                    auto nodes = [Node(x), Node(y), Node(z)];
                    auto node = Node(nodes, "!mystruct.tag");
                    //use flow style
                    node.setStyle(CollectionStyle.flow);
                    return node;
                }
            }


            dumper(new Appender!string).dump(Node(MyStruct(1,2,3)));
        }
        /**
         * Represent a mapping with specified _tag, representing children first.
         *
         * This is used by representer functions that produce mappings.
         *
         * Params:  tag   = Tag of the mapping.
         *          pairs = Key-value _pairs of the mapping.
         *          style = Style of the mapping. If invalid, default _style will be used.
         *                  If the node was loaded before, previous _style will always be used.
         *
         * Returns: The represented node.
         *
         * Throws:  $(D RepresenterException) if a child could not be represented.
         */
        Node representMapping(string tag, Node.Pair[] pairs,
                              CollectionStyle style = CollectionStyle.invalid) @safe
        {
            Node.Pair[] value;
            value.length = pairs.length;

            auto bestStyle = CollectionStyle.flow;
            foreach(idx, ref pair; pairs)
            {
                value[idx] = Node.Pair(representData(pair.key), representData(pair.value));
                const keyScalar = value[idx].key.isScalar;
                const valScalar = value[idx].value.isScalar;
                const keyStyle = value[idx].key.scalarStyle;
                const valStyle = value[idx].value.scalarStyle;
                if(!keyScalar ||
                   (keyStyle != ScalarStyle.invalid && keyStyle != ScalarStyle.plain))
                {
                    bestStyle = CollectionStyle.block;
                }
                if(!valScalar ||
                   (valStyle != ScalarStyle.invalid && valStyle != ScalarStyle.plain))
                {
                    bestStyle = CollectionStyle.block;
                }
            }

            if(style == CollectionStyle.invalid)
            {
                style = defaultCollectionStyle_ != CollectionStyle.invalid
                        ? defaultCollectionStyle_
                        : bestStyle;
            }
            auto newNode = Node(value, tag);
            newNode.collectionStyle = style;
            return newNode;
        }
        ///
        @safe unittest
        {
            import dyaml.dumper : dumper;
            struct MyStruct
            {
                int x, y, z;

                //Any D:YAML type must have a custom opCmp operator.
                //This is used for ordering in mappings.
                const int opCmp(ref const MyStruct s)
                {
                    if(x != s.x){return x - s.x;}
                    if(y != s.y){return y - s.y;}
                    if(z != s.z){return z - s.z;}
                    return 0;
                }
                Node opCast(T: Node)()
                {
                    auto pairs = [Node.Pair("x", x),
                        Node.Pair("y", y),
                        Node.Pair("z", z)];
                    return Node(pairs, "!mystruct.tag");
                }
            }

            dumper(new Appender!string).dump(Node(MyStruct(1,2,3)));
        }

    package:
        //Represent a node based on its type, and return the represented result.
        Node representData(ref Node data) @safe
        {
            auto type = data.type;

            enforce((type in representers_) !is null,
                    new RepresenterException("No representer function for type "
                                             ~ type.toString() ~ " , cannot represent."));
            Node result = representers_[type](data, this);

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

        //Represent a node, serializing with specified Serializer.
        void represent(Range, CharType)(ref Serializer!(Range, CharType) serializer, ref Node node) @safe
        {
            auto data = representData(node);
            serializer.serialize(data);
        }
}


///Represent a _null _node as a _null YAML value.
Node representNull(ref Node node, Representer representer) @safe
{
    return representer.representScalar("tag:yaml.org,2002:null", "null");
}

///Represent a string _node as a string scalar.
Node representString(ref Node node, Representer representer) @safe
{
    string value = node.as!string;
    return value is null
           ? representNull(node, representer)
           : representer.representScalar("tag:yaml.org,2002:str", value);
}

///Represent a bytes _node as a binary scalar.
Node representBytes(ref Node node, Representer representer) @safe
{
    const ubyte[] value = node.as!(ubyte[]);
    if(value is null){return representNull(node, representer);}
    return representer.representScalar("tag:yaml.org,2002:binary",
                                       Base64.encode(value).idup,
                                       ScalarStyle.literal);
}

///Represent a bool _node as a bool scalar.
Node representBool(ref Node node, Representer representer) @safe
{
    return representer.representScalar("tag:yaml.org,2002:bool",
                                       node.as!bool ? "true" : "false");
}

///Represent a long _node as an integer scalar.
Node representLong(ref Node node, Representer representer) @safe
{
    return representer.representScalar("tag:yaml.org,2002:int",
                                       to!string(node.as!long));
}

///Represent a real _node as a floating point scalar.
Node representReal(ref Node node, Representer representer) @safe
{
    real f = node.as!real;
    string value = isNaN(f)                  ? ".nan":
                   f == real.infinity        ? ".inf":
                   f == -1.0 * real.infinity ? "-.inf":
                   {auto a = appender!string();
                    formattedWrite(a, "%12f", f);
                    return a.data.strip();}();

    return representer.representScalar("tag:yaml.org,2002:float", value);
}

///Represent a SysTime _node as a timestamp.
Node representSysTime(ref Node node, Representer representer) @safe
{
    return representer.representScalar("tag:yaml.org,2002:timestamp",
                                       node.as!SysTime.toISOExtString());
}

///Represent a sequence _node as sequence/set.
Node representNodes(ref Node node, Representer representer) @safe
{
    auto nodes = node.as!(Node[]);
    if(node.tag_ == "tag:yaml.org,2002:set")
    {
        ///YAML sets are mapping with null values.
        Node.Pair[] pairs;
        pairs.length = nodes.length;
        Node dummy;
        foreach(idx, ref key; nodes)
        {
            pairs[idx] = Node.Pair(key, representNull(dummy, representer));
        }
        return representer.representMapping(node.tag_, pairs);
    }
    else
    {
        return representer.representSequence("tag:yaml.org,2002:seq", nodes);
    }
}

///Represent a mapping _node as map/ordered map/pairs.
Node representPairs(ref Node node, Representer representer) @safe
{
    auto pairs = node.as!(Node.Pair[]);

    bool hasDuplicates(Node.Pair[] pairs) @safe
    {
        //TODO this should be replaced by something with deterministic memory allocation.
        auto keys = redBlackTree!Node();
        foreach(ref pair; pairs)
        {
            if(pair.key in keys){return true;}
            keys.insert(pair.key);
        }
        return false;
    }

    Node[] mapToSequence(Node.Pair[] pairs) @safe
    {
        Node[] nodes;
        nodes.length = pairs.length;
        foreach(idx, ref pair; pairs)
        {
            nodes[idx] = representer.representMapping("tag:yaml.org,2002:map", [pair]);
        }
        return nodes;
    }

    if(node.tag_ == "tag:yaml.org,2002:omap")
    {
        enforce(!hasDuplicates(pairs),
                new RepresenterException("Duplicate entry in an ordered map"));
        return representer.representSequence(node.tag_, mapToSequence(pairs));
    }
    else if(node.tag_ == "tag:yaml.org,2002:pairs")
    {
        return representer.representSequence(node.tag_, mapToSequence(pairs));
    }
    else
    {
        enforce(!hasDuplicates(pairs),
                new RepresenterException("Duplicate entry in an unordered map"));
        return representer.representMapping("tag:yaml.org,2002:map", pairs);
    }
}
