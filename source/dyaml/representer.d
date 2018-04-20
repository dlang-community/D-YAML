
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
        ScalarStyle defaultScalarStyle_ = ScalarStyle.Invalid;
        // Default style for collection nodes.
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

        ///Set default _style for scalars. If style is $(D ScalarStyle.Invalid), the _style is chosen automatically.
        @property void defaultScalarStyle(ScalarStyle style) pure @safe nothrow
        {
            defaultScalarStyle_ = style;
        }

        ///Set default _style for collections. If style is $(D CollectionStyle.Invalid), the _style is chosen automatically.
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
            }

            static Node representMyStruct(ref Node node, Representer representer) @safe
            {
                //The node is guaranteed to be MyStruct as we add representer for MyStruct.
                auto value = node.as!MyStruct;
                //Using custom scalar format, x:y:z.
                auto scalar = format("%s:%s:%s", value.x, value.y, value.z);
                //Representing as a scalar, with custom tag to specify this data type.
                return representer.representScalar("!mystruct.tag", scalar);
            }

            auto dumper = Dumper("example.yaml");
            auto representer = new Representer;
            representer.addRepresenter!MyStruct(&representMyStruct);
            dumper.representer = representer;
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
            }

            //Same as representMyStruct.
            static Node representMyClass(ref Node node, Representer representer) @safe
            {
                //The node is guaranteed to be MyClass as we add representer for MyClass.
                auto value = node.as!MyClass;
                //Using custom scalar format, x:y:z.
                auto scalar = format("%s:%s:%s", value.x, value.y, value.z);
                //Representing as a scalar, with custom tag to specify this data type.
                return representer.representScalar("!myclass.tag", scalar);
            }

            auto dumper = Dumper("example.yaml");
            auto representer = new Representer;
            representer.addRepresenter!MyClass(&representMyClass);
            dumper.representer = representer;
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
                             ScalarStyle style = ScalarStyle.Invalid) @trusted
        {
            if(style == ScalarStyle.Invalid){style = defaultScalarStyle_;}
            return Node.rawNode(Node.Value(scalar), Mark(), tag, style,
                                CollectionStyle.Invalid);
        }
        ///
        @safe unittest
        {
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
            }

            static Node representMyStruct(ref Node node, Representer representer)
            {
                auto value = node.as!MyStruct;
                auto scalar = format("%s:%s:%s", value.x, value.y, value.z);
                return representer.representScalar("!mystruct.tag", scalar);
            }

            auto dumper = Dumper("example.yaml");
            auto representer = new Representer;
            representer.addRepresenter!MyStruct(&representMyStruct);
            dumper.representer = representer;
            dumper.dump(Node(MyStruct(1,2,3)));
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
                               CollectionStyle style = CollectionStyle.Invalid) @trusted
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
            return Node.rawNode(Node.Value(value), Mark(), tag,
                                ScalarStyle.Invalid, style);
        }
        ///
        @safe unittest
        {
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
            }

            static Node representMyStruct(ref Node node, Representer representer)
            {
                auto value = node.as!MyStruct;
                auto nodes = [Node(value.x), Node(value.y), Node(value.z)];
                //use flow style
                return representer.representSequence("!mystruct.tag", nodes,
                    CollectionStyle.Flow);
            }

            auto dumper = Dumper("example.yaml");
            auto representer = new Representer;
            representer.addRepresenter!MyStruct(&representMyStruct);
            dumper.representer = representer;
            dumper.dump(Node(MyStruct(1,2,3)));
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
                              CollectionStyle style = CollectionStyle.Invalid) @trusted
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
            return Node.rawNode(Node.Value(value), Mark(), tag,
                                ScalarStyle.Invalid, style);
        }
        ///
        @safe unittest
        {
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
            }

            static Node representMyStruct(ref Node node, Representer representer)
            {
                auto value = node.as!MyStruct;
                auto pairs = [Node.Pair("x", value.x),
                Node.Pair("y", value.y),
                Node.Pair("z", value.z)];
                return representer.representMapping("!mystruct.tag", pairs);
            }

            auto dumper = Dumper("example.yaml");
            auto representer = new Representer;
            representer.addRepresenter!MyStruct(&representMyStruct);
            dumper.representer = representer;
            dumper.dump(Node(MyStruct(1,2,3)));
        }

    package:
        //Represent a node based on its type, and return the represented result.
        Node representData(ref Node data) @safe
        {
            //User types are wrapped in YAMLObject.
            auto type = data.isUserType ? data.as!YAMLObject.type : data.type;

            enforce((type in representers_) !is null,
                    new RepresenterException("No representer function for type "
                                             ~ type.toString() ~ " , cannot represent."));
            Node result = representers_[type](data, this);

            //Override tag if specified.
            if(data.tag_ !is null){result.tag_ = data.tag_;}

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
        void represent(ref Serializer serializer, ref Node node) @safe
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
                                       ScalarStyle.Literal);
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

//Unittests
//These should really all be encapsulated in unittests.
private:

import dyaml.dumper;

struct MyStruct
{
    int x, y, z;

    int opCmp(ref const MyStruct s) const pure @safe nothrow
    {
        if(x != s.x){return x - s.x;}
        if(y != s.y){return y - s.y;}
        if(z != s.z){return z - s.z;}
        return 0;
    }
}

Node representMyStruct(ref Node node, Representer representer) @safe
{
    //The node is guaranteed to be MyStruct as we add representer for MyStruct.
    auto value = node.as!MyStruct;
    //Using custom scalar format, x:y:z.
    auto scalar = format("%s:%s:%s", value.x, value.y, value.z);
    //Representing as a scalar, with custom tag to specify this data type.
    return representer.representScalar("!mystruct.tag", scalar);
}

Node representMyStructSeq(ref Node node, Representer representer) @safe
{
    auto value = node.as!MyStruct;
    auto nodes = [Node(value.x), Node(value.y), Node(value.z)];
    return representer.representSequence("!mystruct.tag", nodes);
}

Node representMyStructMap(ref Node node, Representer representer) @safe
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

    this(int x, int y, int z) pure @safe nothrow
    {
        this.x = x;
        this.y = y;
        this.z = z;
    }

    override int opCmp(Object o) pure @safe nothrow
    {
        MyClass s = cast(MyClass)o;
        if(s is null){return -1;}
        if(x != s.x){return x - s.x;}
        if(y != s.y){return y - s.y;}
        if(z != s.z){return z - s.z;}
        return 0;
    }

    ///Useful for Node.as!string .
    override string toString() @safe
    {
        return format("MyClass(%s, %s, %s)", x, y, z);
    }
}

//Same as representMyStruct.
Node representMyClass(ref Node node, Representer representer) @safe
{
    //The node is guaranteed to be MyClass as we add representer for MyClass.
    auto value = node.as!MyClass;
    //Using custom scalar format, x:y:z.
    auto scalar = format("%s:%s:%s", value.x, value.y, value.z);
    //Representing as a scalar, with custom tag to specify this data type.
    return representer.representScalar("!myclass.tag", scalar);
}

import dyaml.stream;

@safe unittest
{
    foreach(r; [&representMyStruct,
                &representMyStructSeq,
                &representMyStructMap])
    {
        auto dumper = Dumper(new YMemoryStream());
        auto representer = new Representer;
        representer.addRepresenter!MyStruct(r);
        dumper.representer = representer;
        dumper.dump(Node(MyStruct(1,2,3)));
    }
}

@safe unittest
{
    auto dumper = Dumper(new YMemoryStream());
    auto representer = new Representer;
    representer.addRepresenter!MyClass(&representMyClass);
    dumper.representer = representer;
    dumper.dump(Node(new MyClass(1,2,3)));
}
