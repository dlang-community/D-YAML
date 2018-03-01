
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Node of a YAML document. Used to read YAML data once it's loaded,
/// and to prepare data to emit.
module dyaml.node;


import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.math;
import std.range;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;
import std.variant;

import dyaml.event;
import dyaml.exception;
import dyaml.style;

/// Exception thrown at node related errors.
class NodeException : YAMLException
{
    package:
        // Construct a NodeException.
        //
        // Params:  msg   = Error message.
        //          start = Start position of the node.
        this(string msg, Mark start, string file = __FILE__, int line = __LINE__)
            @safe
        {
            super(msg ~ "\nNode at: " ~ start.toString(), file, line);
        }
}

private alias NodeException Error;

// Node kinds.
package enum NodeID : ubyte
{
    Scalar,
    Sequence,
    Mapping
}

package enum YAMLType
{
    Boolean,
    Binary,
    Integer,
    Float,
    String,
    Time,
    Merge,
    Null,
    Mapping,
    Sequence,
    UserType
}

/// Null YAML type. Used in nodes with _null values.
struct YAMLNull
{
    /// Used for string conversion.
    string toString() const pure @safe nothrow {return "null";}
}

// Merge YAML type, used to support "tag:yaml.org,2002:merge".
package struct YAMLMerge{}

// Base class for YAMLContainer - used for user defined YAML types.
package abstract class YAMLObject
{
    public:
        // Get type of the stored value.
        @property TypeInfo type() const pure @safe nothrow {assert(false);}

    protected:
        // Compare with another YAMLObject.
        int cmp(const YAMLObject rhs) const @system {assert(false);};
}

// Stores a user defined YAML data type.
package class YAMLContainer(T) if (!Node.allowed!T): YAMLObject
{
    private:
        // Stored value.
        T value_;

    public:
        // Get type of the stored value.
        @property override TypeInfo type() const pure @safe nothrow {return typeid(T);}

        // Get string representation of the container.
        override string toString() @system
        {
            static if(!hasMember!(T, "toString"))
            {
                return super.toString();
            }
            else
            {
                return format("YAMLContainer(%s)", value_.toString());
            }
        }

    protected:
        // Compare with another YAMLObject.
        override int cmp(const YAMLObject rhs) const @system
        {
            const typeCmp = type.opCmp(rhs.type);
            if(typeCmp != 0){return typeCmp;}

            // Const-casting here as Object opCmp is not const.
            T* v1 = cast(T*)&value_;
            T* v2 = cast(T*)&((cast(YAMLContainer)rhs).value_);
            return (*v1).opCmp(*v2);
        }

    private:
        // Construct a YAMLContainer holding specified value.
        this(T value) @trusted {value_ = value;}
}


// Key-value pair of YAML nodes, used in mappings.
private struct Pair
{
    public:
        /// Key node.
        Node key;
        /// Value node.
        Node value;

    public:
        /// Construct a Pair from two values. Will be converted to Nodes if needed.
        this(K, V)(K key, V value) @safe
        {
            static if(is(Unqual!K == Node)){this.key = key;}
            else                           {this.key = Node(key);}
            static if(is(Unqual!V == Node)){this.value = value;}
            else                           {this.value = Node(value);}
        }

        /// Equality test with another Pair.
        bool opEquals(const ref Pair rhs) const @safe
        {
            return cmp!(Yes.useTag)(rhs) == 0;
        }

        /// Assignment (shallow copy) by value.
        void opAssign(Pair rhs) @safe nothrow
        {
            opAssign(rhs);
        }

        /// Assignment (shallow copy) by reference.
        void opAssign(ref Pair rhs) @safe nothrow
        {
            key   = rhs.key;
            value = rhs.value;
        }

    private:
        // Comparison with another Pair.
        //
        // useTag determines whether or not we consider node tags
        // in the comparison.
        int cmp(Flag!"useTag" useTag)(ref const(Pair) rhs) const @safe
        {
            const keyCmp = key.cmp!useTag(rhs.key);
            return keyCmp != 0 ? keyCmp
                                : value.cmp!useTag(rhs.value);
        }

        // @disable causes a linker error with DMD 2.054, so we temporarily use
        // a private opCmp. Apparently this must also match the attributes of
        // the Node's opCmp to avoid a linker error.
        @disable int opCmp(ref Pair);
        int opCmp(ref const(Pair) pair) const @safe
        {
            assert(false, "This should never be called");
        }
}

/** YAML node.
 *
 * This is a pseudo-dynamic type that can store any YAML value, including a
 * sequence or mapping of nodes. You can get data from a Node directly or
 * iterate over it if it's a collection.
 */
struct Node
{
    public:
        alias Pair = .Pair;

    package:
        // YAML value type.
        alias Algebraic!(YAMLNull, YAMLMerge, bool, long, real, ubyte[], SysTime, string,
                         Node.Pair[], Node[], YAMLObject) Value;

        // Can Value hold this type without wrapping it in a YAMLObject?
        template allowed(T)
        {
            enum allowed = isIntegral!T ||
                           isFloatingPoint!T ||
                           isSomeString!T ||
                           is(Unqual!T == bool) ||
                           Value.allowed!T;
        }

    private:
        // Stored value.
        Value value_;
        // Start position of the node.
        Mark startMark_;

    package:
        // Tag of the node.
        string tag_;
        // Node scalar style. Used to remember style this node was loaded with.
        ScalarStyle scalarStyle = ScalarStyle.Invalid;
        // Node collection style. Used to remember style this node was loaded with.
        CollectionStyle collectionStyle = CollectionStyle.Invalid;

        static assert(Value.sizeof <= 24, "Unexpected YAML value size");
        static assert(Node.sizeof <= 56, "Unexpected YAML node size");

        // If scalarCtorNothrow!T is true, scalar node ctor from T can be nothrow.
        //
        // TODO
        // Eventually we should simplify this and make all Node constructors except from
        // user values nothrow (and think even about those user values). 2014-08-28
        enum scalarCtorNothrow(T) =
            (is(Unqual!T == string) || isIntegral!T || isFloatingPoint!T) || is(Unqual!T == bool) ||
            (Value.allowed!T && (!is(Unqual!T == Value) && !isSomeString!T && !isArray!T && !isAssociativeArray!T));
    public:
        /** Construct a Node from a value.
         *
         * Any type except for Node can be stored in a Node, but default YAML
         * types (integers, floats, strings, timestamps, etc.) will be stored
         * more efficiently. To create a node representing a null value,
         * construct it from YAMLNull.
         *
         *
         * Note that to emit any non-default types you store
         * in a node, you need a Representer to represent them in YAML -
         * otherwise emitting will fail.
         *
         * Params:  value = Value to store in the node.
         *          tag   = Overrides tag of the node when emitted, regardless
         *                  of tag determined by Representer. Representer uses
         *                  this to determine YAML data type when a D data type
         *                  maps to multiple different YAML data types. Tag must
         *                  be in full form, e.g. "tag:yaml.org,2002:int", not
         *                  a shortcut, like "!!int".
         */
        this(T)(T value, const string tag = null) @trusted
            if(!scalarCtorNothrow!T && (!isArray!T && !isAssociativeArray!T))
        {
            tag_ = tag;

            // No copyconstruction.
            static assert(!is(Unqual!T == Node));

            enum unexpectedType = "Unexpected type in the non-nothrow YAML node constructor";
            static if(isSomeString!T)             { value_ = Value(value.to!string); }
            else static if(is(Unqual!T == Value)) { value_ = Value(value); }
            else static if(Value.allowed!T)       { static assert(false, unexpectedType); }
            // User defined type.
            else                                  { value_ = userValue(value); }
        }
        /// Ditto.
        // Overload for types where we can make this nothrow.
        this(T)(T value, const string tag = null) @trusted pure nothrow
            if(scalarCtorNothrow!T)
        {
            tag_   = tag;
            // We can easily store ints, floats, strings.
            static if(isIntegral!T)           { value_ = Value(cast(long)value); }
            else static if(is(Unqual!T==bool)){ value_ = Value(cast(bool)value); }
            else static if(isFloatingPoint!T) { value_ = Value(cast(real)value); }
            // User defined type or plain string.
            else                              { value_ = Value(value);}
        }
        unittest
        {
            {
                auto node = Node(42);
                assert(node.isScalar && !node.isSequence &&
                       !node.isMapping && !node.isUserType);
                assert(node.as!int == 42 && node.as!float == 42.0f && node.as!string == "42");
                assert(!node.isUserType);
            }

            {
                auto node = Node(new class{int a = 5;});
                assert(node.isUserType);
            }
            {
                auto node = Node("string");
                assert(node.as!string == "string");
            }
        }

        /** Construct a node from an _array.
         *
         * If _array is an _array of nodes or pairs, it is stored directly.
         * Otherwise, every value in the array is converted to a node, and
         * those nodes are stored.
         *
         * Params:  array = Values to store in the node.
         *          tag   = Overrides tag of the node when emitted, regardless
         *                  of tag determined by Representer. Representer uses
         *                  this to determine YAML data type when a D data type
         *                  maps to multiple different YAML data types.
         *                  This is used to differentiate between YAML sequences
         *                  ("!!seq") and sets ("!!set"), which both are
         *                  internally represented as an array_ of nodes. Tag
         *                  must be in full form, e.g. "tag:yaml.org,2002:set",
         *                  not a shortcut, like "!!set".
         *
         * Examples:
         * --------------------
         * // Will be emitted as a sequence (default for arrays)
         * auto seq = Node([1, 2, 3, 4, 5]);
         * // Will be emitted as a set (overriden tag)
         * auto set = Node([1, 2, 3, 4, 5], "tag:yaml.org,2002:set");
         * --------------------
         */
        this(T)(T[] array, const string tag = null) @trusted
            if (!isSomeString!(T[]))
        {
            tag_ = tag;

            // Construction from raw node or pair array.
            static if(is(Unqual!T == Node) || is(Unqual!T == Node.Pair))
            {
                value_ = Value(array);
            }
            // Need to handle byte buffers separately.
            else static if(is(Unqual!T == byte) || is(Unqual!T == ubyte))
            {
                value_ = Value(cast(ubyte[]) array);
            }
            else
            {
                Node[] nodes;
                foreach(ref value; array){nodes ~= Node(value);}
                value_ = Value(nodes);
            }
        }
        unittest
        {
            with(Node([1, 2, 3]))
            {
                assert(!isScalar() && isSequence && !isMapping && !isUserType);
                assert(length == 3);
                assert(opIndex(2).as!int == 3);
            }

            // Will be emitted as a sequence (default for arrays)
            auto seq = Node([1, 2, 3, 4, 5]);
            // Will be emitted as a set (overriden tag)
            auto set = Node([1, 2, 3, 4, 5], "tag:yaml.org,2002:set");
        }

        /** Construct a node from an associative _array.
         *
         * If keys and/or values of _array are nodes, they stored directly.
         * Otherwise they are converted to nodes and then stored.
         *
         * Params:  array = Values to store in the node.
         *          tag   = Overrides tag of the node when emitted, regardless
         *                  of tag determined by Representer. Representer uses
         *                  this to determine YAML data type when a D data type
         *                  maps to multiple different YAML data types.
         *                  This is used to differentiate between YAML unordered
         *                  mappings ("!!map"), ordered mappings ("!!omap"), and
         *                  pairs ("!!pairs") which are all internally
         *                  represented as an _array of node pairs. Tag must be
         *                  in full form, e.g. "tag:yaml.org,2002:omap", not a
         *                  shortcut, like "!!omap".
         *
         * Examples:
         * --------------------
         * // Will be emitted as an unordered mapping (default for mappings)
         * auto map   = Node([1 : "a", 2 : "b"]);
         * // Will be emitted as an ordered map (overriden tag)
         * auto omap  = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:omap");
         * // Will be emitted as pairs (overriden tag)
         * auto pairs = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:pairs");
         * --------------------
         */
        this(K, V)(V[K] array, const string tag = null) @trusted
        {
            tag_ = tag;

            Node.Pair[] pairs;
            foreach(key, ref value; array){pairs ~= Pair(key, value);}
            value_ = Value(pairs);
        }
        unittest
        {
            int[string] aa;
            aa["1"] = 1;
            aa["2"] = 2;
            with(Node(aa))
            {
                assert(!isScalar() && !isSequence && isMapping && !isUserType);
                assert(length == 2);
                assert(opIndex("2").as!int == 2);
            }

            // Will be emitted as an unordered mapping (default for mappings)
            auto map   = Node([1 : "a", 2 : "b"]);
            // Will be emitted as an ordered map (overriden tag)
            auto omap  = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:omap");
            // Will be emitted as pairs (overriden tag)
            auto pairs = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:pairs");
        }

        /** Construct a node from arrays of _keys and _values.
         *
         * Constructs a mapping node with key-value pairs from
         * _keys and _values, keeping their order. Useful when order
         * is important (ordered maps, pairs).
         *
         *
         * keys and values must have equal length.
         *
         *
         * If _keys and/or _values are nodes, they are stored directly/
         * Otherwise they are converted to nodes and then stored.
         *
         * Params:  keys   = Keys of the mapping, from first to last pair.
         *          values = Values of the mapping, from first to last pair.
         *          tag    = Overrides tag of the node when emitted, regardless
         *                   of tag determined by Representer. Representer uses
         *                   this to determine YAML data type when a D data type
         *                   maps to multiple different YAML data types.
         *                   This is used to differentiate between YAML unordered
         *                   mappings ("!!map"), ordered mappings ("!!omap"), and
         *                   pairs ("!!pairs") which are all internally
         *                   represented as an array of node pairs. Tag must be
         *                   in full form, e.g. "tag:yaml.org,2002:omap", not a
         *                   shortcut, like "!!omap".
         *
         * Examples:
         * --------------------
         * // Will be emitted as an unordered mapping (default for mappings)
         * auto map   = Node([1, 2], ["a", "b"]);
         * // Will be emitted as an ordered map (overriden tag)
         * auto omap  = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:omap");
         * // Will be emitted as pairs (overriden tag)
         * auto pairs = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:pairs");
         * --------------------
         */
        this(K, V)(K[] keys, V[] values, const string tag = null) @trusted
            if(!(isSomeString!(K[]) || isSomeString!(V[])))
        in
        {
            assert(keys.length == values.length,
                   "Lengths of keys and values arrays to construct " ~
                   "a YAML node from don't match");
        }
        body
        {
            tag_ = tag;

            Node.Pair[] pairs;
            foreach(i; 0 .. keys.length){pairs ~= Pair(keys[i], values[i]);}
            value_ = Value(pairs);
        }
        unittest
        {
            with(Node(["1", "2"], [1, 2]))
            {
                assert(!isScalar() && !isSequence && isMapping && !isUserType);
                assert(length == 2);
                assert(opIndex("2").as!int == 2);
            }

            // Will be emitted as an unordered mapping (default for mappings)
            auto map   = Node([1, 2], ["a", "b"]);
            // Will be emitted as an ordered map (overriden tag)
            auto omap  = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:omap");
            // Will be emitted as pairs (overriden tag)
            auto pairs = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:pairs");
        }

        /// Is this node valid (initialized)?
        @property bool isValid()    const @safe pure nothrow
        {
            return value_.hasValue;
        }

        /// Is this node a scalar value?
        @property bool isScalar()   const @safe nothrow
        {
            return !(isMapping || isSequence);
        }

        /// Is this node a sequence?
        @property bool isSequence() const @safe nothrow
        {
            return type == YAMLType.Sequence;
        }

        /// Is this node a mapping?
        @property bool isMapping()  const @safe nothrow
        {
            return type == YAMLType.Mapping;
        }

        /// Is this node a user defined type?
        @property bool isUserType() const @safe nothrow
        {
            return type == YAMLType.UserType;
        }

        /// Is this node null?
        @property bool isNull()     const @safe nothrow
        {
            return type == YAMLType.Null;
        }

        /// Return tag of the node.
        @property string tag()      const @safe nothrow {return tag_;}

        /** Equality test.
         *
         * If T is Node, recursively compares all subnodes.
         * This might be quite expensive if testing entire documents.
         *
         * If T is not Node, gets a value of type T from the node and tests
         * equality with that.
         *
         * To test equality with a null YAML value, use YAMLNull.
         *
         * Params:  rhs = Variable to test equality with.
         *
         * Returns: true if equal, false otherwise.
         */
        bool opEquals(T)(const auto ref T rhs) const @safe
        {
            return equals!(Yes.useTag)(rhs);
        }
        ///
        unittest
        {
            auto node = Node(42);

            assert(node == 42);
            assert(node != "42");
            assert(node != "43");

            auto node2 = Node(YAMLNull());
            assert(node2 == YAMLNull());
        }

        /// Shortcut for get().
        alias get as;

        /** Get the value of the node as specified type.
         *
         * If the specifed type does not match type in the node,
         * conversion is attempted. The stringConversion template
         * parameter can be used to disable conversion from non-string
         * types to strings.
         *
         * Numeric values are range checked, throwing if out of range of
         * requested type.
         *
         * Timestamps are stored as std.datetime.SysTime.
         * Binary values are decoded and stored as ubyte[].
         *
         * To get a null value, use get!YAMLNull . This is to
         * prevent getting null values for types such as strings or classes.
         *
         * $(BR)$(B Mapping default values:)
         *
         * $(PBR
         * The '=' key can be used to denote the default value of a mapping.
         * This can be used when a node is scalar in early versions of a program,
         * but is replaced by a mapping later. Even if the node is a mapping, the
         * get method can be used as if it was a scalar if it has a default value.
         * This way, new YAML files where the node is a mapping can still be read
         * by old versions of the program, which expect the node to be a scalar.
         * )
         *
         * Examples:
         *
         * Automatic type conversion:
         * --------------------
         * auto node = Node(42);
         *
         * assert(node.as!int == 42);
         * assert(node.as!string == "42");
         * assert(node.as!double == 42.0);
         * --------------------
         *
         * Returns: Value of the node as specified type.
         *
         * Throws:  NodeException if unable to convert to specified type, or if
         *          the value is out of range of requested type.
         */
        @property T get(T, Flag!"stringConversion" stringConversion = Yes.stringConversion)()
            @trusted if(!is(T == const))
        {
            if(isType!T){return value_.get!T;}

            /// Must go before others, as even string/int/etc could be stored in a YAMLObject.
            static if(!allowed!T) if(isUserType)
            {
                auto object = as!YAMLObject;
                if(auto casted = cast(YAMLContainer!T)object)
                {
                    return casted.value_;
                }
                throw new Error("Node stores unexpected type: " ~ object.type.text ~
                                ". Expected: " ~ typeid(T).toString, startMark_);
            }

            // If we're getting from a mapping and we're not getting Node.Pair[],
            // we're getting the default value.
            if(isMapping){return this["="].as!(T, stringConversion);}

            static if(isSomeString!T)
            {
                static if(!stringConversion)
                {
                    if(isString){return to!T(value_.get!string);}
                    throw new Error("Node stores unexpected type: " ~ type.text ~
                                    ". Expected: " ~ typeid(T).toString, startMark_);
                }
                else
                {
                    // Try to convert to string.
                    try
                    {
                        return value_.coerce!T();
                    }
                    catch(VariantException e)
                    {
                        throw new Error("Unable to convert node value to string", startMark_);
                    }
                }
            }
            else
            {
                static if(isFloatingPoint!T)
                {
                    /// Can convert int to float.
                    if(isInt())       {return to!T(value_.get!(const long));}
                    else if(isFloat()){return to!T(value_.get!(const real));}
                }
                else static if(is(Unqual!T == bool))
                {
                    const temp = value_.get!(const bool);
                    return to!bool(temp);
                }
                else static if(isIntegral!T)
                {
                    if(isInt())
                    {
                        const temp = value_.get!(const long);
                        enforce(temp >= T.min && temp <= T.max,
                            new Error("Integer value of type " ~ typeid(T).toString() ~
                                      " out of range. Value: " ~ to!string(temp), startMark_));
                        return to!T(temp);
                    }
                    throw new Error("Node stores unexpected type: " ~ type.text ~
                        ". Expected: " ~ typeid(T).toString(), startMark_);
                }
                else throw new Error("Node stores unexpected type: " ~ type.text ~
                                ". Expected: " ~ typeid(T).toString(), startMark_);
            }
            assert(false, "This code should never be reached");
        }
        unittest
        {
            assertThrown!NodeException(Node("42").get!int);
            Node(YAMLNull()).get!YAMLNull;
        }

        /// Ditto.
        @property T get(T, Flag!"stringConversion" stringConversion = Yes.stringConversion)() const
            @trusted if(is(T == const))
        {
            if(isType!(Unqual!T)){return value_.get!T;}

            /// Must go before others, as even string/int/etc could be stored in a YAMLObject.
            static if(!allowed!(Unqual!T)) if(isUserType)
            {
                auto object = as!(const YAMLObject);
                if(object.type is typeid(T))
                {
                    return (cast(const YAMLContainer!(Unqual!T))object).value_;
                }
                throw new Error("Node has unexpected type: " ~ object.type.toString() ~
                                ". Expected: " ~ typeid(T).toString, startMark_);
            }

            // If we're getting from a mapping and we're not getting Node.Pair[],
            // we're getting the default value.
            if(isMapping){return indexConst("=").as!( T, stringConversion);}

            static if(isSomeString!T)
            {
                static if(!stringConversion)
                {
                    if(isString){return to!T(value_.get!(const string));}
                    throw new Error("Node stores unexpected type: " ~ type.text ~
                                    ". Expected: " ~ typeid(T).toString(), startMark_);
                }
                else
                {
                    // Try to convert to string.
                    try
                    {
                        // NOTE: We are casting away const here
                        return (cast(Value)value_).coerce!T();
                    }
                    catch(VariantException e)
                    {
                        throw new Error("Unable to convert node value to string", startMark_);
                    }
                }
            }
            else
            {
                static if(isFloatingPoint!T)
                {
                    /// Can convert int to float.
                    if(isInt())       {return to!T(value_.get!(const long));}
                    else if(isFloat()){return to!T(value_.get!(const real));}
                }
                else static if(is(Unqual!T == bool))
                {
                    const temp = value_.get!(const bool);
                    return to!bool(temp);
                }
                else static if(isIntegral!T) if(isInt())
                {
                    const temp = value_.get!(const long);
                    enforce(temp >= T.min && temp <= T.max,
                            new Error("Integer value of type " ~ typeid(T).toString() ~
                                      " out of range. Value: " ~ to!string(temp), startMark_));
                    return to!T(temp);
                }
                throw new Error("Node stores unexpected type: " ~ type.text ~
                                ". Expected: " ~ typeid(T).toString, startMark_);
            }
        }

        /** If this is a collection, return its _length.
         *
         * Otherwise, throw NodeException.
         *
         * Returns: Number of elements in a sequence or key-value pairs in a mapping.
         *
         * Throws: NodeException if this is not a sequence nor a mapping.
         */
        @property size_t length() const @trusted
        {
            if(isSequence)    {return value_.get!(const Node[]).length;}
            else if(isMapping){return value_.get!(const Pair[]).length;}
            throw new Error("Trying to get length of a " ~ nodeTypeString ~ " node",
                            startMark_);
        }

        /** Get the element at specified index.
         *
         * If the node is a sequence, index must be integral.
         *
         *
         * If the node is a mapping, return the value corresponding to the first
         * key equal to index. containsKey() can be used to determine if a mapping
         * has a specific key.
         *
         * To get element at a null index, use YAMLNull for index.
         *
         * Params:  index = Index to use.
         *
         * Returns: Value corresponding to the index.
         *
         * Throws:  NodeException if the index could not be found,
         *          non-integral index is used with a sequence or the node is
         *          not a collection.
         */
        ref Node opIndex(T)(T index) @trusted
        {
            if(isSequence)
            {
                checkSequenceIndex(index);
                static if(isIntegral!T || is(Unqual!T == bool))
                {
                    return cast(Node)value_.get!(Node[])[index];
                }
                assert(false);
            }
            else if(isMapping)
            {
                auto idx = findPair(index);
                if(idx >= 0)
                {
                    return cast(Node)value_.get!(Pair[])[idx].value;
                }

                string msg = "Mapping index not found" ~ (isSomeString!T ? ": " ~ to!string(index) : "");
                throw new Error(msg, startMark_);
            }
            throw new Error("Trying to index a " ~ nodeTypeString ~ " node", startMark_);
        }
        ///
        unittest
        {
            writeln("D:YAML Node opIndex unittest");
            alias Node.Value Value;
            alias Node.Pair Pair;

            Node narray = Node([11, 12, 13, 14]);
            Node nmap   = Node(["11", "12", "13", "14"], [11, 12, 13, 14]);

            assert(narray[0].as!int == 11);
            assert(null !is collectException(narray[42]));
            assert(nmap["11"].as!int == 11);
            assert(nmap["14"].as!int == 14);
        }
        unittest
        {
            writeln("D:YAML Node opIndex unittest");
            alias Node.Value Value;
            alias Node.Pair Pair;

            Node narray = Node([11, 12, 13, 14]);
            Node nmap   = Node(["11", "12", "13", "14"], [11, 12, 13, 14]);

            assert(narray[0].as!int == 11);
            assert(null !is collectException(narray[42]));
            assert(nmap["11"].as!int == 11);
            assert(nmap["14"].as!int == 14);
            assert(null !is collectException(nmap["42"]));

            narray.add(YAMLNull());
            nmap.add(YAMLNull(), "Nothing");
            assert(narray[4].as!YAMLNull == YAMLNull());
            assert(nmap[YAMLNull()].as!string == "Nothing");

            assertThrown!NodeException(nmap[11]);
            assertThrown!NodeException(nmap[14]);
        }

        /** Determine if a collection contains specified value.
         *
         * If the node is a sequence, check if it contains the specified value.
         * If it's a mapping, check if it has a value that matches specified value.
         *
         * Params:  rhs = Item to look for. Use YAMLNull to check for a null value.
         *
         * Returns: true if rhs was found, false otherwise.
         *
         * Throws:  NodeException if the node is not a collection.
         */
        bool contains(T)(T rhs) const @safe
        {
            return contains_!(T, No.key, "contains")(rhs);
        }


        /** Determine if a mapping contains specified key.
         *
         * Params:  rhs = Key to look for. Use YAMLNull to check for a null key.
         *
         * Returns: true if rhs was found, false otherwise.
         *
         * Throws:  NodeException if the node is not a mapping.
         */
        bool containsKey(T)(T rhs) const @safe
        {
            return contains_!(T, Yes.key, "containsKey")(rhs);
        }

        // Unittest for contains() and containsKey().
        unittest
        {
            writeln("D:YAML Node contains/containsKey unittest");
            auto seq = Node([1, 2, 3, 4, 5]);
            assert(seq.contains(3));
            assert(seq.contains(5));
            assert(!seq.contains("5"));
            assert(!seq.contains(6));
            assert(!seq.contains(float.nan));
            assertThrown!NodeException(seq.containsKey(5));

            auto seq2 = Node(["1", "2"]);
            assert(seq2.contains("1"));
            assert(!seq2.contains(1));

            auto map = Node(["1", "2", "3", "4"], [1, 2, 3, 4]);
            assert(map.contains(1));
            assert(!map.contains("1"));
            assert(!map.contains(5));
            assert(!map.contains(float.nan));
            assert(map.containsKey("1"));
            assert(map.containsKey("4"));
            assert(!map.containsKey(1));
            assert(!map.containsKey("5"));

            assert(!seq.contains(YAMLNull()));
            assert(!map.contains(YAMLNull()));
            assert(!map.containsKey(YAMLNull()));
            seq.add(YAMLNull());
            map.add("Nothing", YAMLNull());
            assert(seq.contains(YAMLNull()));
            assert(map.contains(YAMLNull()));
            assert(!map.containsKey(YAMLNull()));
            map.add(YAMLNull(), "Nothing");
            assert(map.containsKey(YAMLNull()));

            auto map2 = Node([1, 2, 3, 4], [1, 2, 3, 4]);
            assert(!map2.contains("1"));
            assert(map2.contains(1));
            assert(!map2.containsKey("1"));
            assert(map2.containsKey(1));

            // scalar
            assertThrown!NodeException(Node(1).contains(4));
            assertThrown!NodeException(Node(1).containsKey(4));

            auto mapNan = Node([1.0, 2, double.nan], [1, double.nan, 5]);

            assert(mapNan.contains(double.nan));
            assert(mapNan.containsKey(double.nan));
        }

        /// Assignment (shallow copy) by value.
        void opAssign(Node rhs) @safe nothrow
        {
            opAssign(rhs);
        }

        /// Assignment (shallow copy) by reference.
        void opAssign(ref Node rhs) @trusted nothrow
        {
            // Value opAssign doesn't really throw, so force it to nothrow.
            alias Value delegate(Value) nothrow valueAssignNothrow;
            (cast(valueAssignNothrow)&value_.opAssign!Value)(rhs.value_);
            startMark_      = rhs.startMark_;
            tag_            = rhs.tag_;
            scalarStyle     = rhs.scalarStyle;
            collectionStyle = rhs.collectionStyle;
        }
        // Unittest for opAssign().
        unittest
        {
            auto seq = Node([1, 2, 3, 4, 5]);
            auto assigned = seq;
            assert(seq == assigned,
                   "Node.opAssign() doesn't produce an equivalent copy");
        }

        /** Set element at specified index in a collection.
         *
         * This method can only be called on collection nodes.
         *
         * If the node is a sequence, index must be integral.
         *
         * If the node is a mapping, sets the _value corresponding to the first
         * key matching index (including conversion, so e.g. "42" matches 42).
         *
         * If the node is a mapping and no key matches index, a new key-value
         * pair is added to the mapping. In sequences the index must be in
         * range. This ensures behavior siilar to D arrays and associative
         * arrays.
         *
         * To set element at a null index, use YAMLNull for index.
         *
         * Params:  index = Index of the value to set.
         *
         * Throws:  NodeException if the node is not a collection, index is out
         *          of range or if a non-integral index is used on a sequence node.
         */
        void opIndexAssign(K, V)(V value, K index) @trusted
        {
            if(isSequence())
            {
                // This ensures K is integral.
                checkSequenceIndex(index);
                static if(isIntegral!K || is(Unqual!K == bool))
                {
                    auto nodes = value_.get!(Node[]);
                    static if(is(Unqual!V == Node)){nodes[index] = value;}
                    else                           {nodes[index] = Node(value);}
                    value_ = Value(nodes);
                    return;
                }
                assert(false);
            }
            else if(isMapping())
            {
                const idx = findPair(index);
                if(idx < 0){add(index, value);}
                else
                {
                    auto pairs = as!(Node.Pair[])();
                    static if(is(Unqual!V == Node)){pairs[idx].value = value;}
                    else                           {pairs[idx].value = Node(value);}
                    value_ = Value(pairs);
                }
                return;
            }

            throw new Error("Trying to index a " ~ nodeTypeString ~ " node", startMark_);
        }
        unittest
        {
            writeln("D:YAML Node opIndexAssign unittest");

            with(Node([1, 2, 3, 4, 3]))
            {
                opIndexAssign(42, 3);
                assert(length == 5);
                assert(opIndex(3).as!int == 42);

                opIndexAssign(YAMLNull(), 0);
                assert(opIndex(0) == YAMLNull());
            }
            with(Node(["1", "2", "3"], [4, 5, 6]))
            {
                opIndexAssign(42, "3");
                opIndexAssign(123, 456);
                assert(length == 4);
                assert(opIndex("3").as!int == 42);
                assert(opIndex(456).as!int == 123);

                opIndexAssign(43, 3);
                //3 and "3" should be different
                assert(length == 5);
                assert(opIndex("3").as!int == 42);
                assert(opIndex(3).as!int == 43);

                opIndexAssign(YAMLNull(), "2");
                assert(opIndex("2") == YAMLNull());
            }
        }

        /** Return a range object iterating over a sequence, getting each
          * element as T.
          * 
          * If T is Node, simply iterate over the nodes in the sequence.
          * Otherwise, convert each node to T during iteration.
          *
          * Throws: NodeException if the node is not a sequence or an element
          *         could not be converted to specified type.
          */
        auto sequence(T = Node)() @trusted
        {
            enforce(isSequence,
                    new Error("Trying to 'sequence'-iterate over a " ~ nodeTypeString ~ " node",
                        startMark_));
            struct Range
            {
                Node[] subnodes;
                size_t position;

                this(Node[] nodes)
                {
                    subnodes = nodes;
                    position = 0;
                }

                /* Input range functionality. */
                bool empty() @property { return position >= subnodes.length; }

                void popFront() 
                { 
                    enforce(!empty, "Attempted to popFront an empty sequence");
                    position++; 
                }

                T front() @property
                {
                    enforce(!empty, "Attempted to take the front of an empty sequence");
                    static if (is(Unqual!T == Node))
                        return subnodes[position];
                    else
                        return subnodes[position].as!T;
                }

                /* Forward range functionality. */
                Range save() { return this; }

                /* Bidirectional range functionality. */
                void popBack() 
                { 
                    enforce(!empty, "Attempted to popBack an empty sequence");
                    subnodes = subnodes[0 .. $ - 1]; 
                }

                T back() 
                {  
                    enforce(!empty, "Attempted to take the back of an empty sequence");
                    static if (is(Unqual!T == Node))
                        return subnodes[$ - 1];
                    else
                        return subnodes[$ - 1].as!T;
                }

                /* Random-access range functionality. */
                size_t length() const @property { return subnodes.length; }
                T opIndex(size_t index)
                {
                    static if (is(Unqual!T == Node))
                        return subnodes[index];
                    else
                        return subnodes[index].as!T;
                }

                static assert(isInputRange!Range);
                static assert(isForwardRange!Range);
                static assert(isBidirectionalRange!Range);
                static assert(isRandomAccessRange!Range);
            }
            return Range(get!(Node[]));
        }
        unittest
        {
            writeln("D:YAML Node sequence unittest");

            Node n1 = Node([1, 2, 3, 4]);
            int[int] array;
            Node n2 = Node(array);

            auto r = n1.sequence!int.map!(x => x * 10);
            assert(r.equal([10, 20, 30, 40]));

            assertThrown(n2.sequence);
        }

        /** Return a range object iterating over mapping's pairs.
          *
          * Throws: NodeException if the node is not a mapping.
          *
          */
        auto mapping() @trusted
        {
            enforce(isMapping,
                    new Error("Trying to 'mapping'-iterate over a " 
                        ~ nodeTypeString ~ " node", startMark_));
            struct Range
            {
                Node.Pair[] pairs;
                size_t position;

                this(Node.Pair[] pairs)
                {
                    this.pairs = pairs;
                    position = 0;
                }

                /* Input range functionality. */
                bool empty() { return position >= pairs.length; }

                void popFront() 
                { 
                    enforce(!empty, "Attempted to popFront an empty mapping");
                    position++; 
                }

                Pair front() 
                { 
                    enforce(!empty, "Attempted to take the front of an empty mapping");
                    return pairs[position]; 
                }

                /* Forward range functionality. */
                Range save() { return this; }

                /* Bidirectional range functionality. */
                void popBack() 
                { 
                    enforce(!empty, "Attempted to popBack an empty mapping");
                    pairs = pairs[0 .. $ - 1]; 
                }

                Pair back() 
                { 
                    enforce(!empty, "Attempted to take the back of an empty mapping");
                    return pairs[$ - 1]; 
                }

                /* Random-access range functionality. */
                size_t length() const @property { return pairs.length; }
                Pair opIndex(size_t index) { return pairs[index]; }

                static assert(isInputRange!Range);
                static assert(isForwardRange!Range);
                static assert(isBidirectionalRange!Range);
                static assert(isRandomAccessRange!Range);
            }
            return Range(get!(Node.Pair[]));
        }
        unittest
        {
            writeln("D:YAML Node mapping unittest");

            int[int] array;
            Node n = Node(array);
            n[1] = "foo";
            n[2] = "bar";
            n[3] = "baz";

            string[int] test;
            foreach (pair; n.mapping)
                test[pair.key.as!int] = pair.value.as!string;

            assert(test[1] == "foo");
            assert(test[2] == "bar");
            assert(test[3] == "baz");
        }

        /** Return a range object iterating over mapping's keys.
          *
          * If K is Node, simply iterate over the keys in the mapping.
          * Otherwise, convert each key to T during iteration.
          *
          * Throws: NodeException if the nodes is not a mapping or an element
          *         could not be converted to specified type.
          */
        auto mappingKeys(K = Node)() @trusted
        {
            enforce(isMapping,
                    new Error("Trying to 'mappingKeys'-iterate over a " 
                        ~ nodeTypeString ~ " node", startMark_));
            static if (is(Unqual!K == Node))
                return mapping.map!(pair => pair.key);
            else
                return mapping.map!(pair => pair.key.as!K);
        }
        unittest
        {
            writeln("D:YAML Node mappingKeys unittest");

            int[int] array;
            Node m1 = Node(array);
            m1["foo"] = 2;
            m1["bar"] = 3;

            assert(m1.mappingKeys.equal(["foo", "bar"]));
        }

        /** Return a range object iterating over mapping's values.
          *
          * If V is Node, simply iterate over the values in the mapping.
          * Otherwise, convert each key to V during iteration.
          *
          * Throws: NodeException if the nodes is not a mapping or an element
          *         could not be converted to specified type.
          */
        auto mappingValues(V = Node)() @trusted
        {
            enforce(isMapping,
                    new Error("Trying to 'mappingValues'-iterate over a " 
                        ~ nodeTypeString ~ " node", startMark_));
            static if (is(Unqual!V == Node))
                return mapping.map!(pair => pair.value);
            else
                return mapping.map!(pair => pair.value.as!V);
        }
        unittest
        {
            writeln("D:YAML Node mappingValues unittest");

            int[int] array;
            Node m1 = Node(array);
            m1["foo"] = 2;
            m1["bar"] = 3;

            assert(m1.mappingValues.equal([2, 3]));
        }

        /** Foreach over a sequence, getting each element as T.
         *
         * If T is Node, simply iterate over the nodes in the sequence.
         * Otherwise, convert each node to T during iteration.
         *
         * Throws:  NodeException if the node is not a sequence or an
         *          element could not be converted to specified type.
         */
        int opApply(T)(int delegate(ref T) dg) @trusted
        {
            enforce(isSequence,
                    new Error("Trying to sequence-foreach over a " ~ nodeTypeString ~ " node",
                              startMark_));

            int result = 0;
            foreach(ref node; get!(Node[]))
            {
                static if(is(Unqual!T == Node))
                {
                    result = dg(node);
                }
                else
                {
                    T temp = node.as!T;
                    result = dg(temp);
                }
                if(result){break;}
            }
            return result;
        }
        unittest
        {
            writeln("D:YAML Node opApply unittest 1");

            alias Node.Value Value;
            alias Node.Pair Pair;

            Node n1 = Node(Value(cast(long)11));
            Node n2 = Node(Value(cast(long)12));
            Node n3 = Node(Value(cast(long)13));
            Node n4 = Node(Value(cast(long)14));
            Node narray = Node([n1, n2, n3, n4]);

            int[] array, array2;
            foreach(int value; narray)
            {
                array ~= value;
            }
            foreach(Node node; narray)
            {
                array2 ~= node.as!int;
            }
            assert(array == [11, 12, 13, 14]);
            assert(array2 == [11, 12, 13, 14]);
        }

        /** Foreach over a mapping, getting each key/value as K/V.
         *
         * If the K and/or V is Node, simply iterate over the nodes in the mapping.
         * Otherwise, convert each key/value to T during iteration.
         *
         * Throws:  NodeException if the node is not a mapping or an
         *          element could not be converted to specified type.
         */
        int opApply(K, V)(int delegate(ref K, ref V) dg) @trusted
        {
            enforce(isMapping,
                    new Error("Trying to mapping-foreach over a " ~ nodeTypeString ~ " node",
                              startMark_));

            int result = 0;
            foreach(ref pair; get!(Node.Pair[]))
            {
                static if(is(Unqual!K == Node) && is(Unqual!V == Node))
                {
                    result = dg(pair.key, pair.value);
                }
                else static if(is(Unqual!K == Node))
                {
                    V tempValue = pair.value.as!V;
                    result = dg(pair.key, tempValue);
                }
                else static if(is(Unqual!V == Node))
                {
                    K tempKey   = pair.key.as!K;
                    result = dg(tempKey, pair.value);
                }
                else
                {
                    K tempKey   = pair.key.as!K;
                    V tempValue = pair.value.as!V;
                    result = dg(tempKey, tempValue);
                }

                if(result){break;}
            }
            return result;
        }
        unittest
        {
            writeln("D:YAML Node opApply unittest 2");

            alias Node.Value Value;
            alias Node.Pair Pair;

            Node n1 = Node(cast(long)11);
            Node n2 = Node(cast(long)12);
            Node n3 = Node(cast(long)13);
            Node n4 = Node(cast(long)14);

            Node k1 = Node("11");
            Node k2 = Node("12");
            Node k3 = Node("13");
            Node k4 = Node("14");

            Node nmap1 = Node([Pair(k1, n1),
                               Pair(k2, n2),
                               Pair(k3, n3),
                               Pair(k4, n4)]);

            int[string] expected = ["11" : 11,
                                    "12" : 12,
                                    "13" : 13,
                                    "14" : 14];
            int[string] array;
            foreach(string key, int value; nmap1)
            {
                array[key] = value;
            }
            assert(array == expected);

            Node nmap2 = Node([Pair(k1, Node(cast(long)5)),
                               Pair(k2, Node(true)),
                               Pair(k3, Node(cast(real)1.0)),
                               Pair(k4, Node("yarly"))]);

            foreach(string key, Node value; nmap2)
            {
                switch(key)
                {
                    case "11": assert(value.as!int    == 5      ); break;
                    case "12": assert(value.as!bool   == true   ); break;
                    case "13": assert(value.as!float  == 1.0    ); break;
                    case "14": assert(value.as!string == "yarly"); break;
                    default:   assert(false);
                }
            }
        }

        /** Add an element to a sequence.
         *
         * This method can only be called on sequence nodes.
         *
         * If value is a node, it is copied to the sequence directly. Otherwise
         * value is converted to a node and then stored in the sequence.
         *
         * $(P When emitting, all values in the sequence will be emitted. When
         * using the !!set tag, the user needs to ensure that all elements in
         * the sequence are unique, otherwise $(B invalid) YAML code will be
         * emitted.)
         *
         * Params:  value = Value to _add to the sequence.
         */
        void add(T)(T value) @trusted
        {
            enforce(isSequence(),
                    new Error("Trying to add an element to a " ~ nodeTypeString ~ " node", startMark_));

            auto nodes = get!(Node[])();
            static if(is(Unqual!T == Node)){nodes ~= value;}
            else                           {nodes ~= Node(value);}
            value_ = Value(nodes);
        }
        unittest
        {
            writeln("D:YAML Node add unittest 1");

            with(Node([1, 2, 3, 4]))
            {
                add(5.0f);
                assert(opIndex(4).as!float == 5.0f);
            }
        }

        /** Add a key-value pair to a mapping.
         *
         * This method can only be called on mapping nodes.
         *
         * If key and/or value is a node, it is copied to the mapping directly.
         * Otherwise it is converted to a node and then stored in the mapping.
         *
         * $(P It is possible for the same key to be present more than once in a
         * mapping. When emitting, all key-value pairs will be emitted.
         * This is useful with the "!!pairs" tag, but will result in
         * $(B invalid) YAML with "!!map" and "!!omap" tags.)
         *
         * Params:  key   = Key to _add.
         *          value = Value to _add.
         */
        void add(K, V)(K key, V value) @trusted
        {
            enforce(isMapping(),
                    new Error("Trying to add a key-value pair to a " ~
                              nodeTypeString ~ " node",
                              startMark_));

            auto pairs = get!(Node.Pair[])();
            pairs ~= Pair(key, value);
            value_ = Value(pairs);
        }
        unittest
        {
            writeln("D:YAML Node add unittest 2");
            with(Node([1, 2], [3, 4]))
            {
                add(5, "6");
                assert(opIndex(5).as!string == "6");
            }
        }

        /** Determine whether a key is in a mapping, and access its value.
         *
         * This method can only be called on mapping nodes.
         *
         * Params:   key = Key to search for.
         *
         * Returns:  A pointer to the value (as a Node) corresponding to key,
         *           or null if not found.
         *
         * Note:     Any modification to the node can invalidate the returned
         *           pointer.
         *
         * See_Also: contains
         */
        Node* opBinaryRight(string op, K)(K key) @system
            if (op == "in")
        {
            enforce(isMapping, new Error("Trying to use 'in' on a " ~
                                         nodeTypeString ~ " node", startMark_));

            auto idx = findPair(key);
            if(idx < 0)
            {
                return null;
            }
            else
            {
                return &(get!(Node.Pair[])[idx].value);
            }
        }
        unittest
        {
            writeln(`D:YAML Node opBinaryRight!"in" unittest`);
            auto mapping = Node(["foo", "baz"], ["bar", "qux"]);
            assert("bad" !in mapping && ("bad" in mapping) is null);
            Node* foo = "foo" in mapping;
            assert(foo !is null);
            assert(*foo == Node("bar"));
            assert(foo.get!string == "bar");
            *foo = Node("newfoo");
            assert(mapping["foo"] == Node("newfoo"));
        }

        /** Remove first (if any) occurence of a value in a collection.
         *
         * This method can only be called on collection nodes.
         *
         * If the node is a sequence, the first node matching value is removed.
         * If the node is a mapping, the first key-value pair where _value
         * matches specified value is removed.
         *
         * Params:  rhs = Value to _remove.
         *
         * Throws:  NodeException if the node is not a collection.
         */
        void remove(T)(T rhs) @trusted
        {
            remove_!(T, No.key, "remove")(rhs);
        }
        unittest
        {
            writeln("D:YAML Node remove unittest");
            with(Node([1, 2, 3, 4, 3]))
            {
                remove(3);
                assert(length == 4);
                assert(opIndex(2).as!int == 4);
                assert(opIndex(3).as!int == 3);

                add(YAMLNull());
                assert(length == 5);
                remove(YAMLNull());
                assert(length == 4);
            }
            with(Node(["1", "2", "3"], [4, 5, 6]))
            {
                remove(4);
                assert(length == 2);
                add("nullkey", YAMLNull());
                assert(length == 3);
                remove(YAMLNull());
                assert(length == 2);
            }
        }

        /** Remove element at the specified index of a collection.
         *
         * This method can only be called on collection nodes.
         *
         * If the node is a sequence, index must be integral.
         *
         * If the node is a mapping, remove the first key-value pair where
         * key matches index.
         *
         * If the node is a mapping and no key matches index, nothing is removed
         * and no exception is thrown. This ensures behavior siilar to D arrays
         * and associative arrays.
         *
         * Params:  index = Index to remove at.
         *
         * Throws:  NodeException if the node is not a collection, index is out
         *          of range or if a non-integral index is used on a sequence node.
         */
        void removeAt(T)(T index) @trusted
        {
            remove_!(T, Yes.key, "removeAt")(index);
        }
        unittest
        {
            writeln("D:YAML Node removeAt unittest");
            with(Node([1, 2, 3, 4, 3]))
            {
                removeAt(3);
                assertThrown!NodeException(removeAt("3"));
                assert(length == 4);
                assert(opIndex(3).as!int == 3);
            }
            with(Node(["1", "2", "3"], [4, 5, 6]))
            {
                // no integer 2 key, so don't remove anything
                removeAt(2);
                assert(length == 3);
                removeAt("2");
                assert(length == 2);
                add(YAMLNull(), "nullval");
                assert(length == 3);
                removeAt(YAMLNull());
                assert(length == 2);
            }
        }

        /// Compare with another _node.
        int opCmp(ref const Node node) const @safe
        {
            return cmp!(Yes.useTag)(node);
        }

        // Compute hash of the node.
        hash_t toHash() nothrow const
        {
            const tagHash = (tag_ is null) ? 0 : tag_.hashOf();
            // Variant toHash is not const at the moment, so we need to const-cast.
            return tagHash + value_.toHash();
        }
        unittest
        {
            writeln("Node(42).toHash(): ", Node(42).toHash());
        }

    package:
        // Construct a node from raw data.
        //
        // Params:  value           = Value of the node.
        //          startMark       = Start position of the node in file.
        //          tag             = Tag of the node.
        //          scalarStyle     = Scalar style of the node.
        //          collectionStyle = Collection style of the node.
        //
        // Returns: Constructed node.
        static Node rawNode(Value value, const Mark startMark, const string tag,
                            const ScalarStyle scalarStyle,
                            const CollectionStyle collectionStyle) @trusted
        {
            Node node;
            node.value_          = value;
            node.startMark_      = startMark;
            node.tag_            = tag;
            node.scalarStyle     = scalarStyle;
            node.collectionStyle = collectionStyle;

            return node;
        }

        // Construct Node.Value from user defined type.
        static Value userValue(T)(T value) @trusted nothrow
        {
            return Value(cast(YAMLObject)new YAMLContainer!T(value));
        }

        // Construct Node.Value from a type it can store directly (after casting if needed)
        static Value value(T)(T value) @system nothrow if(allowed!T)
        {
            static if(Value.allowed!T)
            {
                return Value(value);
            }
            else static if(isIntegral!T)
            {
                return Value(cast(long)(value));
            }
            else static if (is(Unqual!T == bool))
            {
                return Value(cast(bool)(value));
            }
            else static if(isFloatingPoint!T)
            {
                return Value(cast(real)(value));
            }
            else static if(isSomeString!T)
            {
                return Value(to!string(value));
            }
            else static assert(false, "Unknown value type. Is value() in sync with allowed()?");
        }

        // Equality test with any value.
        //
        // useTag determines whether or not to consider tags in node-node comparisons.
        bool equals(Flag!"useTag" useTag, T)(ref T rhs) const @safe
        {
            static if(is(Unqual!T == Node))
            {
                return cmp!useTag(rhs) == 0;
            }
            else
            {
                try
                {
                    auto stored = get!(const(Unqual!T), No.stringConversion);
                    // Need to handle NaNs separately.
                    static if(isFloatingPoint!T)
                    {
                        return rhs == stored || (isNaN(rhs) && isNaN(stored));
                    }
                    else
                    {
                        return rhs == get!(const(Unqual!T));
                    }
                }
                catch(NodeException e){return false;}
            }
        }

        // Comparison with another node.
        //
        // Used for ordering in mappings and for opEquals.
        //
        // useTag determines whether or not to consider tags in the comparison.
        int cmp(Flag!"useTag" useTag)(const ref Node rhs) const @trusted
        {
            // Compare tags - if equal or both null, we need to compare further.
            static if(useTag)
            {
                const tagCmp = (tag_ is null) ? (rhs.tag_ is null) ? 0 : -1
                                           : (rhs.tag_ is null) ? 1 : std.algorithm.comparison.cmp(tag_, rhs.tag_);
                if(tagCmp != 0){return tagCmp;}
            }

            static int cmp(T1, T2)(T1 a, T2 b)
            {
                return a > b ? 1  :
                       a < b ? -1 :
                               0;
            }

            // Compare validity: if both valid, we have to compare further.
            const v1 = isValid;
            const v2 = rhs.isValid;
            if(!v1){return v2 ? -1 : 0;}
            if(!v2){return 1;}

            if(type != rhs.type){return type - rhs.type;}

            static int compareCollections(T)(const ref Node lhs, const ref Node rhs)
            {
                const c1 = lhs.value_.get!(const T);
                const c2 = rhs.value_.get!(const T);
                if(c1 is c2){return 0;}
                if(c1.length != c2.length)
                {
                    return cmp(c1.length, c2.length);
                }
                // Equal lengths, compare items.
                foreach(i; 0 .. c1.length)
                {
                    const itemCmp = c1[i].cmp!useTag(c2[i]);
                    if(itemCmp != 0){return itemCmp;}
                }
                return 0;
            }

            final switch(type) {
                case YAMLType.Boolean:
                    const b1 = value_.get!(const bool);
                    const b2 = rhs.value_.get!(const bool);
                    return b1 ? b2 ? 0 : 1
                              : b2 ? -1 : 0;
                case YAMLType.Sequence:
                    return compareCollections!(Node[])(this, rhs);
                case YAMLType.Mapping:
                    return compareCollections!(Pair[])(this, rhs);
                case YAMLType.String:
                    return std.algorithm.cmp(value_.get!(const string),
                                             rhs.value_.get!(const string));
                case YAMLType.Integer:
                    return cmp(value_.get!(const long), rhs.value_.get!(const long));
                case YAMLType.Binary:
                    const b1 = value_.get!(const ubyte[]);
                    const b2 = rhs.value_.get!(const ubyte[]);
                    return std.algorithm.cmp(b1, b2);
                case YAMLType.Null:
                    return 0;
                case YAMLType.Merge:
                    assert(0, "Something has gone terribly wrong.");
                case YAMLType.Float:
                    const r1 = value_.get!(const real);
                    const r2 = rhs.value_.get!(const real);
                    if(isNaN(r1))
                    {
                        return isNaN(r2) ? 0 : -1;
                    }
                    if(isNaN(r2))
                    {
                        return 1;
                    }
                    // Fuzzy equality.
                    if(r1 <= r2 + real.epsilon && r1 >= r2 - real.epsilon)
                    {
                        return 0;
                    }
                    return cmp(r1, r2);
                case YAMLType.Time:
                    const t1 = value_.get!(const SysTime);
                    const t2 = rhs.value_.get!(const SysTime);
                    return cmp(t1, t2);
                case YAMLType.UserType:
                    return value_.get!(const YAMLObject).cmp(rhs.value_.get!(const YAMLObject));
            }
        }

        // Get a string representation of the node tree. Used for debugging.
        //
        // Params:  level = Level of the node in the tree.
        //
        // Returns: String representing the node tree.
        @property string debugString(uint level = 0) @trusted
        {
            string indent;
            foreach(i; 0 .. level){indent ~= " ";}

            if(!isValid){return indent ~ "invalid";}

            if(isSequence)
            {
                string result = indent ~ "sequence:\n";
                foreach(ref node; get!(Node[]))
                {
                    result ~= node.debugString(level + 1);
                }
                return result;
            }
            if(isMapping)
            {
                string result = indent ~ "mapping:\n";
                foreach(ref pair; get!(Node.Pair[]))
                {
                    result ~= indent ~ " pair\n";
                    result ~= pair.key.debugString(level + 2);
                    result ~= pair.value.debugString(level + 2);
                }
                return result;
            }
            if(isScalar)
            {
                return indent ~ "scalar(" ~
                       (convertsTo!string ? get!string : type.text) ~ ")\n";
            }
            assert(false);
        }

        // Get type of the node value (YAMLObject for user types).
        @property YAMLType type() const @trusted nothrow
        {
            try
            {
                if (value_.type == typeid(YAMLNull)) return YAMLType.Null;
                else if (value_.type == typeid(YAMLMerge)) return YAMLType.Merge;
                else if (value_.type == typeid(bool)) return YAMLType.Boolean;
                else if (value_.type == typeid(long)) return YAMLType.Integer;
                else if (value_.type == typeid(real)) return YAMLType.Float;
                else if (value_.type == typeid(ubyte[])) return YAMLType.Binary;
                else if (value_.type == typeid(SysTime)) return YAMLType.Time;
                else if (value_.type == typeid(string)) return YAMLType.String;
                else if (value_.type == typeid(Node.Pair[])) return YAMLType.Mapping;
                else if (value_.type == typeid(Node[])) return YAMLType.Sequence;
                else if (value_.type == typeid(YAMLObject)) return YAMLType.UserType;
                else assert(0, "Unknown type");
            }
            catch (Exception)
            {
                assert(0, "This should never happen.");
            }
        }

    public:
        // Determine if the value stored by the node is of specified type.
        //
        // This only works for default YAML types, not for user defined types.
        @property bool isType(T)() const @trusted nothrow
        {
            try {
                final switch(YAMLTypeOf!T)
                {
                    case YAMLType.Integer: return isInt();
                    case YAMLType.Boolean: return isBool();
                    case YAMLType.Float: return isFloat();
                    case YAMLType.String: return isString();
                    case YAMLType.Merge: return type == YAMLType.Merge;
                    case YAMLType.Null: return isNull();
                    case YAMLType.Binary: return isBinary();
                    case YAMLType.Sequence: return isSequence();
                    case YAMLType.Mapping: return isMapping();
                    case YAMLType.Time: return isTime();
                    case YAMLType.UserType: return (type == YAMLType.UserType) && (value_.type == typeid(T));
                }
            }
            catch (Exception)
            {
                assert(0, "This should never happen.");
            }
        }

        // Is the value a bool?
        @property bool isBool() const @safe nothrow
        {
            return type == YAMLType.Boolean;
        }

        // Is the value a raw binary buffer?
        @property bool isBinary() const @safe nothrow
        {
            return type == YAMLType.Binary;
        }

        // Is the value an integer?
        @property bool isInt() const @safe nothrow
        {
            return type == YAMLType.Integer;
        }

        // Is the value a floating point number?
        @property bool isFloat() const @safe nothrow
        {
            return type == YAMLType.Float;
        }

        // Is the value a string?
        @property bool isString() const @safe nothrow
        {
            return type == YAMLType.String;
        }

        // Is the value a timestamp?
        @property bool isTime() const @safe nothrow
        {
            return type == YAMLType.Time;
        }

        // Does given node have the same type as this node?
        bool hasEqualType(const ref Node node) const @safe nothrow
        {
            return type == node.type;
        }

        // Return a string describing node type (sequence, mapping or scalar)
        @property string nodeTypeString() const @safe nothrow
        {
            assert(isScalar || isSequence || isMapping, "Unknown node type");
            return isScalar   ? "scalar"   :
                   isSequence ? "sequence" :
                   isMapping  ? "mapping" : "";
        }

        // Determine if the value can be converted to specified type.
        @property bool convertsTo(T)() const @safe nothrow
        {
            if(isType!T){return true;}

            // Every type allowed in Value should be convertible to string.
            static if(isSomeString!T)        {return true;}
            else static if(isFloatingPoint!T){return isInt() || isFloat();}
            else static if(isIntegral!T)     {return isInt();}
            else static if(is(Unqual!T==bool)){return isBool();}
            else                             {return false;}
        }

    private:
        // Implementation of contains() and containsKey().
        bool contains_(T, Flag!"key" key, string func)(T rhs) const @trusted
        {
            static if(!key) if(isSequence)
            {
                foreach(ref node; value_.get!(const Node[]))
                {
                    if(node == rhs){return true;}
                }
                return false;
            }

            if(isMapping)
            {
                return findPair!(T, key)(rhs) >= 0;
            }

            throw new Error("Trying to use " ~ func ~ "() on a " ~ nodeTypeString ~ " node",
                            startMark_);
        }

        // Implementation of remove() and removeAt()
        void remove_(T, Flag!"key" key, string func)(T rhs) @system
        {
            enforce(isSequence || isMapping,
                    new Error("Trying to " ~ func ~ "() from a " ~ nodeTypeString ~ " node",
                              startMark_));

            static void removeElem(E, I)(ref Node node, I index)
            {
                auto elems = node.value_.get!(E[]);
                moveAll(elems[cast(size_t)index + 1 .. $], elems[cast(size_t)index .. $ - 1]);
                elems.length = elems.length - 1;
                node.value_ = Value(elems);
            }

            if(isSequence())
            {
                static long getIndex(ref Node node, ref T rhs)
                {
                    foreach(idx, ref elem; node.get!(Node[]))
                    {
                        if(elem.convertsTo!T && elem.as!(T, No.stringConversion) == rhs)
                        {
                            return idx;
                        }
                    }
                    return -1;
                }

                const index = select!key(rhs, getIndex(this, rhs));

                // This throws if the index is not integral.
                checkSequenceIndex(index);

                static if(isIntegral!(typeof(index))){removeElem!Node(this, index);}
                else                                 {assert(false, "Non-integral sequence index");}
            }
            else if(isMapping())
            {
                const index = findPair!(T, key)(rhs);
                if(index >= 0){removeElem!Pair(this, index);}
            }
        }

        // Get index of pair with key (or value, if key is false) matching index.
        sizediff_t findPair(T, Flag!"key" key = Yes.key)(const ref T index) const @trusted
        {
            const pairs = value_.get!(const Pair[])();
            const(Node)* node;
            foreach(idx, ref const(Pair) pair; pairs)
            {
                static if(key){node = &pair.key;}
                else          {node = &pair.value;}


                bool typeMatch = (isFloatingPoint!T && (node.isInt || node.isFloat)) ||
                                 (isIntegral!T && node.isInt) ||
                                 (is(Unqual!T==bool) && node.isBool) ||
                                 (isSomeString!T && node.isString) ||
                                 (node.isType!T);
                if(typeMatch && *node == index)
                {
                    return idx;
                }
            }
            return -1;
        }

        // Check if index is integral and in range.
        void checkSequenceIndex(T)(T index) const @trusted
        {
            assert(isSequence,
                   "checkSequenceIndex() called on a " ~ nodeTypeString ~ " node");

            static if(!isIntegral!T)
            {
                throw new Error("Indexing a sequence with a non-integral type.", startMark_);
            }
            else
            {
                enforce(index >= 0 && index < value_.get!(const Node[]).length,
                        new Error("Sequence index out of range: " ~ to!string(index),
                                  startMark_));
            }
        }

        // Const version of opIndex.
        ref const(Node) indexConst(T)(T index) const @trusted
        {
            if(isSequence)
            {
                checkSequenceIndex(index);
                static if(isIntegral!T)
                {
                    return value_.get!(const Node[])[index];
                }
                assert(false);
            }
            else if(isMapping)
            {
                auto idx = findPair(index);
                if(idx >= 0)
                {
                    return value_.get!(const Pair[])[idx].value;
                }

                string msg = "Mapping index not found" ~ (isSomeString!T ? ": " ~ to!string(index) : "");
                throw new Error(msg, startMark_);
            }
            throw new Error("Trying to index a " ~ nodeTypeString ~ " node", startMark_);
        }
}

package:
// Merge a pair into an array of pairs based on merge rules in the YAML spec.
//
// The new pair will only be added if there is not already a pair
// with the same key.
//
// Params:  pairs   = Appender managing the array of pairs to merge into.
//          toMerge = Pair to merge.
void merge(ref Appender!(Node.Pair[]) pairs, ref Node.Pair toMerge) @trusted
{
    foreach(ref pair; pairs.data)
    {
        if(pair.key == toMerge.key){return;}
    }
    pairs.put(toMerge);
}

// Merge pairs into an array of pairs based on merge rules in the YAML spec.
//
// Any new pair will only be added if there is not already a pair
// with the same key.
//
// Params:  pairs   = Appender managing the array of pairs to merge into.
//          toMerge = Pairs to merge.
void merge(ref Appender!(Node.Pair[]) pairs, Node.Pair[] toMerge) @trusted
{
    bool eq(ref Node.Pair a, ref Node.Pair b){return a.key == b.key;}

    foreach(ref pair; toMerge) if(!canFind!eq(pairs.data, pair))
    {
        pairs.put(pair);
    }
}


template YAMLTypeOf(T) {
    static if (is(Unqual!T == long))
    {
        enum YAMLTypeOf = YAMLType.Integer;
    }
    else static if (is(Unqual!T == real))
    {
        enum YAMLTypeOf = YAMLType.Float;
    }
    else static if (is(Unqual!T == string))
    {
        enum YAMLTypeOf = YAMLType.String;
    }
    else static if (is(Unqual!T == Node.Pair[]))
    {
        enum YAMLTypeOf = YAMLType.Mapping;
    }
    else static if (is(Unqual!T == Node[]))
    {
        enum YAMLTypeOf = YAMLType.Sequence;
    }
    else static if (is(Unqual!T == ubyte[]))
    {
        enum YAMLTypeOf = YAMLType.Binary;
    }
    else static if (is(Unqual!T == bool))
    {
        enum YAMLTypeOf = YAMLType.Boolean;
    }
    else static if (is(Unqual!T == SysTime))
    {
        enum YAMLTypeOf = YAMLType.Time;
    }
    else static if (is(Unqual!T == YAMLNull))
    {
        enum YAMLTypeOf = YAMLType.Null;
    }
    else static if (is(Unqual!T == YAMLMerge))
    {
        enum YAMLTypeOf = YAMLType.Merge;
    }
    else
    {
        enum YAMLTypeOf = YAMLType.UserType;
    }
}
