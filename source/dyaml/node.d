
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

// Node kinds.
package enum NodeID : ubyte
{
    Scalar,
    Sequence,
    Mapping
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
        this(T value) @safe {value_ = value;}
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
        this(K, V)(K key, V value)
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
        // Note: @safe isn't properly inferred in single-file builds due to a bug.
        int cmp(Flag!"useTag" useTag)(ref const(Pair) rhs) const @safe
        {
            const keyCmp = key.cmp!useTag(rhs.key);
            return keyCmp != 0 ? keyCmp
                                : value.cmp!useTag(rhs.value);
        }
        @disable int opCmp(ref Pair);
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
        enum allowed(T) = isIntegral!T ||
                       isFloatingPoint!T ||
                       isSomeString!T ||
                       is(Unqual!T == bool) ||
                       Value.allowed!T;

    package:
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
        this(T)(T value, const string tag = null)
            if(!scalarCtorNothrow!T && (!isArray!T && !isAssociativeArray!T))
        {
            tag_ = tag;

            // No copyconstruction.
            static assert(!is(Unqual!T == Node));

            enum unexpectedType = "Unexpected type in the non-nothrow YAML node constructor";
            static if(isSomeString!T)             { setValue(value.to!string); }
            else static if(is(Unqual!T == Value)) { setValue(value); }
            else static if(Value.allowed!T)       { static assert(false, unexpectedType); }
            // User defined type.
            else                                  { setValue(value); }
        }
        /// Ditto.
        // Overload for types where we can make this nothrow.
        this(T)(T value, const string tag = null)
            if(scalarCtorNothrow!T)
        {
            tag_   = tag;
            // We can easily store ints, floats, strings.
            static if(isIntegral!T)           { setValue(cast(long)value); }
            else static if(is(Unqual!T==bool)){ setValue(cast(bool)value); }
            else static if(isFloatingPoint!T) { setValue(cast(real)value); }
            // User defined type or plain string.
            else                              { setValue(value);}
        }
        @safe unittest
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
         */
        this(T)(T[] array, const string tag = null)
            if (!isSomeString!(T[]))
        {
            tag_ = tag;

            // Construction from raw node or pair array.
            static if(is(Unqual!T == Node) || is(Unqual!T == Node.Pair))
            {
                setValue(array);
            }
            // Need to handle byte buffers separately.
            else static if(is(Unqual!T == byte) || is(Unqual!T == ubyte))
            {
                setValue(cast(ubyte[]) array);
            }
            else
            {
                Node[] nodes;
                foreach(ref value; array){nodes ~= Node(value);}
                setValue(nodes);
            }
        }
        ///
        @safe unittest
        {
            // Will be emitted as a sequence (default for arrays)
            auto seq = Node([1, 2, 3, 4, 5]);
            // Will be emitted as a set (overriden tag)
            auto set = Node([1, 2, 3, 4, 5], "tag:yaml.org,2002:set");
        }
        @safe unittest
        {
            with(Node([1, 2, 3]))
            {
                assert(!isScalar() && isSequence && !isMapping && !isUserType);
                assert(length == 3);
                assert(opIndex(2).as!int == 3);
            }

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
         */
        this(K, V)(V[K] array, const string tag = null)
        {
            tag_ = tag;

            Node.Pair[] pairs;
            foreach(key, ref value; array){pairs ~= Pair(key, value);}
            setValue(pairs);
        }
        ///
        @safe unittest
        {
            // Will be emitted as an unordered mapping (default for mappings)
            auto map   = Node([1 : "a", 2 : "b"]);
            // Will be emitted as an ordered map (overriden tag)
            auto omap  = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:omap");
            // Will be emitted as pairs (overriden tag)
            auto pairs = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:pairs");
        }
        @safe unittest
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
         */
        this(K, V)(K[] keys, V[] values, const string tag = null)
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
            setValue(pairs);
        }
        ///
        @safe unittest
        {
            // Will be emitted as an unordered mapping (default for mappings)
            auto map   = Node([1, 2], ["a", "b"]);
            // Will be emitted as an ordered map (overridden tag)
            auto omap  = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:omap");
            // Will be emitted as pairs (overriden tag)
            auto pairs = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:pairs");
        }
        @safe unittest
        {
            with(Node(["1", "2"], [1, 2]))
            {
                assert(!isScalar() && !isSequence && isMapping && !isUserType);
                assert(length == 2);
                assert(opIndex("2").as!int == 2);
            }

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
            return isType!(Node[]);
        }

        /// Is this node a mapping?
        @property bool isMapping()  const @safe nothrow
        {
            return isType!(Pair[]);
        }

        /// Is this node a user defined type?
        @property bool isUserType() const @safe nothrow
        {
            return isType!YAMLObject;
        }

        /// Is this node null?
        @property bool isNull()     const @safe nothrow
        {
            return isType!YAMLNull;
        }

        /// Return tag of the node.
        @property string tag()      const @safe nothrow
        {
            return tag_;
        }

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
        bool opEquals(T)(const auto ref T rhs) const
        {
            return equals!(Yes.useTag)(rhs);
        }
        ///
        @safe unittest
        {
            auto node = Node(42);

            assert(node == 42);
            assert(node != "42");
            assert(node != "43");

            auto node2 = Node(YAMLNull());
            assert(node2 == YAMLNull());

            const node3 = Node(42);
            assert(node3 == 42);
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
         * Returns: Value of the node as specified type.
         *
         * Throws:  NodeException if unable to convert to specified type, or if
         *          the value is out of range of requested type.
         */
        inout(T) get(T, Flag!"stringConversion" stringConversion = Yes.stringConversion)() inout
        {
            if(isType!(Unqual!T)){return getValue!T;}

            /// Must go before others, as even string/int/etc could be stored in a YAMLObject.
            static if(!allowed!(Unqual!T)) if(isUserType)
            {
                auto object = getValue!YAMLObject();
                enforce(object.type is typeid(T),
                    new NodeException("Node has unexpected type: " ~ object.type.toString() ~
                        ". Expected: " ~ typeid(T).toString, startMark_));
                return (cast(inout YAMLContainer!(Unqual!T))(object)).value_;
            }

            // If we're getting from a mapping and we're not getting Node.Pair[],
            // we're getting the default value.
            if(isMapping){return this["="].get!( T, stringConversion);}

            static if(isSomeString!T)
            {
                static if(!stringConversion)
                {
                    if(isString){return to!T(getValue!string);}
                    throw new NodeException("Node stores unexpected type: " ~ type.toString() ~
                        ". Expected: " ~ typeid(T).toString(), startMark_);
                }
                else
                {
                    // Try to convert to string.
                    try
                    {
                        return coerceValue!T();
                    }
                    catch(VariantException e)
                    {
                        throw new NodeException("Unable to convert node value to string", startMark_);
                    }
                }
            }
            else static if(isFloatingPoint!T)
            {
                /// Can convert int to float.
                if(isInt())       {return to!T(getValue!long);}
                else if(isFloat()){return to!T(getValue!real);}
                else throw new NodeException("Node stores unexpected type: " ~ type.toString() ~
                    ". Expected: " ~ typeid(T).toString, startMark_);
            }
            else static if(isIntegral!T)
            {
                enforce(isInt(), new NodeException("Node stores unexpected type: " ~ type.toString() ~
                                ". Expected: " ~ typeid(T).toString, startMark_));
                immutable temp = getValue!long;
                enforce(temp >= T.min && temp <= T.max,
                    new NodeException("Integer value of type " ~ typeid(T).toString() ~
                        " out of range. Value: " ~ to!string(temp), startMark_));
                return temp.to!T;
            }
            else throw new NodeException("Node stores unexpected type: " ~ type.toString() ~
                ". Expected: " ~ typeid(T).toString, startMark_);
        }
        /// Automatic type conversion
        @safe unittest
        {
            auto node = Node(42);

            assert(node.get!int == 42);
            assert(node.get!string == "42");
            assert(node.get!double == 42.0);
        }
        @safe unittest
        {
            assertThrown!NodeException(Node("42").get!int);
            assertThrown!NodeException(Node("42").get!double);
            assertThrown!NodeException(Node(long.max).get!ushort);
            Node(YAMLNull()).get!YAMLNull;
        }
        @safe unittest
        {
            const node = Node(42);
            assert(node.get!int == 42);
            assert(node.get!string == "42");
            assert(node.get!double == 42.0);

            immutable node2 = Node(42);
            assert(node2.get!int == 42);
            assert(node2.get!(const int) == 42);
            assert(node2.get!(immutable int) == 42);
            assert(node2.get!string == "42");
            assert(node2.get!(const string) == "42");
            assert(node2.get!(immutable string) == "42");
            assert(node2.get!double == 42.0);
            assert(node2.get!(const double) == 42.0);
            assert(node2.get!(immutable double) == 42.0);
        }

        /** If this is a collection, return its _length.
         *
         * Otherwise, throw NodeException.
         *
         * Returns: Number of elements in a sequence or key-value pairs in a mapping.
         *
         * Throws: NodeException if this is not a sequence nor a mapping.
         */
        @property size_t length() const @safe
        {
            if(isSequence)    { return getValue!(Node[]).length; }
            else if(isMapping) { return getValue!(Pair[]).length; }
            throw new NodeException("Trying to get length of a " ~ nodeTypeString ~ " node",
                            startMark_);
        }
        @safe unittest
        {
            auto node = Node([1,2,3]);
            assert(node.length == 3);
            const cNode = Node([1,2,3]);
            assert(cNode.length == 3);
            immutable iNode = Node([1,2,3]);
            assert(iNode.length == 3);
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
        ref inout(Node) opIndex(T)(T index) inout @safe
        {
            if(isSequence)
            {
                checkSequenceIndex(index);
                static if(isIntegral!T)
                {
                    return getValue!(Node[])[index];
                }
                assert(false);
            }
            else if(isMapping)
            {
                auto idx = findPair(index);
                if(idx >= 0)
                {
                    return getValue!(Pair[])[idx].value;
                }

                string msg = "Mapping index not found" ~ (isSomeString!T ? ": " ~ to!string(index) : "");
                throw new NodeException(msg, startMark_);
            }
            throw new NodeException("Trying to index a " ~ nodeTypeString ~ " node", startMark_);
        }
        ///
        @safe unittest
        {
            alias Node.Value Value;
            alias Node.Pair Pair;

            Node narray = Node([11, 12, 13, 14]);
            Node nmap   = Node(["11", "12", "13", "14"], [11, 12, 13, 14]);

            assert(narray[0].as!int == 11);
            assert(null !is collectException(narray[42]));
            assert(nmap["11"].as!int == 11);
            assert(nmap["14"].as!int == 14);
        }
        @safe unittest
        {
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
        bool contains(T)(T rhs) const
        {
            return contains_!(T, No.key, "contains")(rhs);
        }
        @safe unittest
        {
            auto mNode = Node(["1", "2", "3"]);
            assert(mNode.contains("2"));
            const cNode = Node(["1", "2", "3"]);
            assert(cNode.contains("2"));
            immutable iNode = Node(["1", "2", "3"]);
            assert(iNode.contains("2"));
        }


        /** Determine if a mapping contains specified key.
         *
         * Params:  rhs = Key to look for. Use YAMLNull to check for a null key.
         *
         * Returns: true if rhs was found, false otherwise.
         *
         * Throws:  NodeException if the node is not a mapping.
         */
        bool containsKey(T)(T rhs) const
        {
            return contains_!(T, Yes.key, "containsKey")(rhs);
        }

        // Unittest for contains() and containsKey().
        @safe unittest
        {
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
        void opAssign(ref Node rhs) @safe nothrow
        {
            assumeWontThrow(setValue(rhs.value_));
            startMark_      = rhs.startMark_;
            tag_            = rhs.tag_;
            scalarStyle     = rhs.scalarStyle;
            collectionStyle = rhs.collectionStyle;
        }
        // Unittest for opAssign().
        @safe unittest
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
         * Params:
         *          value = Value to assign.
         *          index = Index of the value to set.
         *
         * Throws:  NodeException if the node is not a collection, index is out
         *          of range or if a non-integral index is used on a sequence node.
         */
        void opIndexAssign(K, V)(V value, K index)
        {
            if(isSequence())
            {
                // This ensures K is integral.
                checkSequenceIndex(index);
                static if(isIntegral!K || is(Unqual!K == bool))
                {
                    auto nodes = getValue!(Node[]);
                    static if(is(Unqual!V == Node)){nodes[index] = value;}
                    else                           {nodes[index] = Node(value);}
                    setValue(nodes);
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
                    setValue(pairs);
                }
                return;
            }

            throw new NodeException("Trying to index a " ~ nodeTypeString ~ " node", startMark_);
        }
        @safe unittest
        {
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
        template sequence(T = Node)
        {
            struct Range(N)
            {
                N subnodes;
                size_t position;

                this(N nodes)
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
            auto sequence()
            {
                enforce(isSequence,
                        new NodeException("Trying to 'sequence'-iterate over a " ~ nodeTypeString ~ " node",
                            startMark_));
                return Range!(Node[])(get!(Node[]));
            }
            auto sequence() const
            {
                enforce(isSequence,
                        new NodeException("Trying to 'sequence'-iterate over a " ~ nodeTypeString ~ " node",
                            startMark_));
                return Range!(const(Node)[])(get!(Node[]));
            }
        }
        @safe unittest
        {
            Node n1 = Node([1, 2, 3, 4]);
            int[int] array;
            Node n2 = Node(array);
            const n3 = Node([1, 2, 3, 4]);

            auto r = n1.sequence!int.map!(x => x * 10);
            assert(r.equal([10, 20, 30, 40]));

            assertThrown(n2.sequence);

            auto r2 = n3.sequence!int.map!(x => x * 10);
            assert(r2.equal([10, 20, 30, 40]));
        }

        /** Return a range object iterating over mapping's pairs.
          *
          * Throws: NodeException if the node is not a mapping.
          *
          */
        template mapping()
        {
            struct Range(T)
            {
                T pairs;
                size_t position;

                this(T pairs) @safe
                {
                    this.pairs = pairs;
                    position = 0;
                }

                /* Input range functionality. */
                bool empty() @safe { return position >= pairs.length; }

                void popFront() @safe
                {
                    enforce(!empty, "Attempted to popFront an empty mapping");
                    position++;
                }

                auto front() @safe
                {
                    enforce(!empty, "Attempted to take the front of an empty mapping");
                    return pairs[position];
                }

                /* Forward range functionality. */
                Range save() @safe  { return this; }

                /* Bidirectional range functionality. */
                void popBack() @safe
                {
                    enforce(!empty, "Attempted to popBack an empty mapping");
                    pairs = pairs[0 .. $ - 1];
                }

                auto back() @safe
                {
                    enforce(!empty, "Attempted to take the back of an empty mapping");
                    return pairs[$ - 1];
                }

                /* Random-access range functionality. */
                size_t length() const @property @safe { return pairs.length; }
                auto opIndex(size_t index) @safe { return pairs[index]; }

                static assert(isInputRange!Range);
                static assert(isForwardRange!Range);
                static assert(isBidirectionalRange!Range);
                static assert(isRandomAccessRange!Range);
            }

            auto mapping()
            {
                enforce(isMapping,
                        new NodeException("Trying to 'mapping'-iterate over a "
                            ~ nodeTypeString ~ " node", startMark_));
                return Range!(Node.Pair[])(get!(Node.Pair[]));
            }
            auto mapping() const
            {
                enforce(isMapping,
                        new NodeException("Trying to 'mapping'-iterate over a "
                            ~ nodeTypeString ~ " node", startMark_));
                return Range!(const(Node.Pair)[])(get!(Node.Pair[]));
            }
        }
        @safe unittest
        {
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

            int[int] constArray = [1: 2, 3: 4];
            const x = Node(constArray);
            foreach (pair; x.mapping)
                assert(pair.value == constArray[pair.key.as!int]);
        }

        /** Return a range object iterating over mapping's keys.
          *
          * If K is Node, simply iterate over the keys in the mapping.
          * Otherwise, convert each key to T during iteration.
          *
          * Throws: NodeException if the nodes is not a mapping or an element
          *         could not be converted to specified type.
          */
        auto mappingKeys(K = Node)() const
        {
            enforce(isMapping,
                    new NodeException("Trying to 'mappingKeys'-iterate over a "
                        ~ nodeTypeString ~ " node", startMark_));
            static if (is(Unqual!K == Node))
                return mapping.map!(pair => pair.key);
            else
                return mapping.map!(pair => pair.key.as!K);
        }
        @safe unittest
        {
            int[int] array;
            Node m1 = Node(array);
            m1["foo"] = 2;
            m1["bar"] = 3;

            assert(m1.mappingKeys.equal(["foo", "bar"]) || m1.mappingKeys.equal(["bar", "foo"]));

            const cm1 = Node(["foo": 2, "bar": 3]);

            assert(cm1.mappingKeys.equal(["foo", "bar"]) || cm1.mappingKeys.equal(["bar", "foo"]));
        }

        /** Return a range object iterating over mapping's values.
          *
          * If V is Node, simply iterate over the values in the mapping.
          * Otherwise, convert each key to V during iteration.
          *
          * Throws: NodeException if the nodes is not a mapping or an element
          *         could not be converted to specified type.
          */
        auto mappingValues(V = Node)() const
        {
            enforce(isMapping,
                    new NodeException("Trying to 'mappingValues'-iterate over a "
                        ~ nodeTypeString ~ " node", startMark_));
            static if (is(Unqual!V == Node))
                return mapping.map!(pair => pair.value);
            else
                return mapping.map!(pair => pair.value.as!V);
        }
        @safe unittest
        {
            int[int] array;
            Node m1 = Node(array);
            m1["foo"] = 2;
            m1["bar"] = 3;

            assert(m1.mappingValues.equal([2, 3]) || m1.mappingValues.equal([3, 2]));

            const cm1 = Node(["foo": 2, "bar": 3]);

            assert(cm1.mappingValues.equal([2, 3]) || cm1.mappingValues.equal([3, 2]));
        }


        /** Foreach over a sequence, getting each element as T.
         *
         * If T is Node, simply iterate over the nodes in the sequence.
         * Otherwise, convert each node to T during iteration.
         *
         * Throws:  NodeException if the node is not a sequence or an
         *          element could not be converted to specified type.
         */
        template opApply(T)
        {
            int opApplyImpl(DG)(DG dg)
            {
                enforce(isSequence,
                        new NodeException("Trying to sequence-foreach over a " ~ nodeTypeString ~ " node",
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
            // Ugly workaround due to issues with inout and delegate params
            int opApplyImpl(DG)(DG dg) const
            {
                enforce(isSequence,
                        new NodeException("Trying to sequence-foreach over a " ~ nodeTypeString ~ " node",
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
            int opApply(scope int delegate(ref T) @system dg)
            {
                return opApplyImpl(dg);
            }
            int opApply(scope int delegate(ref T) @safe dg)
            {
                return opApplyImpl(dg);
            }
            int opApply(scope int delegate(ref const T) @system dg) const
            {
                return opApplyImpl(dg);
            }
            int opApply(scope int delegate(ref const T) @safe dg) const
            {
                return opApplyImpl(dg);
            }
         }
        @safe unittest
        {
            Node n1 = Node(11);
            Node n2 = Node(12);
            Node n3 = Node(13);
            Node n4 = Node(14);
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
        @safe unittest
        {
            string[] testStrs = ["1", "2", "3"];
            auto node1 = Node(testStrs);
            int i = 0;
            foreach (string elem; node1)
            {
                assert(elem == testStrs[i]);
                i++;
            }
            const node2 = Node(testStrs);
            i = 0;
            foreach (string elem; node2)
            {
                assert(elem == testStrs[i]);
                i++;
            }
            immutable node3 = Node(testStrs);
            i = 0;
            foreach (string elem; node3)
            {
                assert(elem == testStrs[i]);
                i++;
            }
        }

        /** Foreach over a mapping, getting each key/value as K/V.
         *
         * If the K and/or V is Node, simply iterate over the nodes in the mapping.
         * Otherwise, convert each key/value to T during iteration.
         *
         * Throws:  NodeException if the node is not a mapping or an
         *          element could not be converted to specified type.
         */
         template opApply(K, V)
         {
            int opApplyImpl(DG)(DG dg)
            {
                enforce(isMapping,
                        new NodeException("Trying to mapping-foreach over a " ~ nodeTypeString ~ " node",
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
            // Ugly workaround due to issues with inout and delegate params
            int opApplyImpl(DG)(DG dg) const
            {
                enforce(isMapping,
                        new NodeException("Trying to mapping-foreach over a " ~ nodeTypeString ~ " node",
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
            int opApply(scope int delegate(ref K, ref V) @system dg)
            {
                return opApplyImpl(dg);
            }
            int opApply(scope int delegate(ref K, ref V) @safe dg)
            {
                return opApplyImpl(dg);
            }
            int opApply(scope int delegate(ref const K, ref const V) @system dg) const
            {
                return opApplyImpl(dg);
            }
            int opApply(scope int delegate(ref const K, ref const V) @safe dg) const
            {
                return opApplyImpl(dg);
            }
         }
        @safe unittest
        {
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
        @safe unittest
        {
            string[int] testStrs = [0: "1", 1: "2", 2: "3"];
            auto node1 = Node(testStrs);
            foreach (const int i, string elem; node1)
            {
                assert(elem == testStrs[i]);
            }
            const node2 = Node(testStrs);
            foreach (const int i, string elem; node2)
            {
                assert(elem == testStrs[i]);
            }
            immutable node3 = Node(testStrs);
            foreach (const int i, string elem; node3)
            {
                assert(elem == testStrs[i]);
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
        void add(T)(T value)
        {
            enforce(isSequence(),
                    new NodeException("Trying to add an element to a " ~ nodeTypeString ~ " node", startMark_));

            auto nodes = get!(Node[])();
            static if(is(Unqual!T == Node)){nodes ~= value;}
            else                           {nodes ~= Node(value);}
            setValue(nodes);
        }
        @safe unittest
        {
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
        void add(K, V)(K key, V value)
        {
            enforce(isMapping(),
                    new NodeException("Trying to add a key-value pair to a " ~
                              nodeTypeString ~ " node",
                              startMark_));

            auto pairs = get!(Node.Pair[])();
            pairs ~= Pair(key, value);
            setValue(pairs);
        }
        @safe unittest
        {
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
        inout(Node*) opBinaryRight(string op, K)(K key) inout
            if (op == "in")
        {
            enforce(isMapping, new NodeException("Trying to use 'in' on a " ~
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
        @safe unittest
        {
            auto mapping = Node(["foo", "baz"], ["bar", "qux"]);
            assert("bad" !in mapping && ("bad" in mapping) is null);
            Node* foo = "foo" in mapping;
            assert(foo !is null);
            assert(*foo == Node("bar"));
            assert(foo.get!string == "bar");
            *foo = Node("newfoo");
            assert(mapping["foo"] == Node("newfoo"));
        }
        @safe unittest
        {
            auto mNode = Node(["a": 2]);
            assert("a" in mNode);
            const cNode = Node(["a": 2]);
            assert("a" in cNode);
            immutable iNode = Node(["a": 2]);
            assert("a" in iNode);
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
        void remove(T)(T rhs)
        {
            remove_!(T, No.key, "remove")(rhs);
        }
        @safe unittest
        {
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
        void removeAt(T)(T index)
        {
            remove_!(T, Yes.key, "removeAt")(index);
        }
        @safe unittest
        {
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
        hash_t toHash() nothrow const @trusted
        {
            const valueHash = value_.toHash();

            return tag_ is null ? valueHash : tag_.hashOf(valueHash);
        }
        @safe unittest
        {
            assert(Node(42).toHash() != Node(41).toHash());
            assert(Node(42).toHash() != Node(42, "some-tag").toHash());
        }

    package:

        // Equality test with any value.
        //
        // useTag determines whether or not to consider tags in node-node comparisons.
        bool equals(Flag!"useTag" useTag, T)(ref T rhs) const
        {
            static if(is(Unqual!T == Node))
            {
                return cmp!useTag(rhs) == 0;
            }
            else
            {
                try
                {
                    auto stored = get!(T, No.stringConversion);
                    // Need to handle NaNs separately.
                    static if(isFloatingPoint!T)
                    {
                        return rhs == stored || (isNaN(rhs) && isNaN(stored));
                    }
                    else
                    {
                        return rhs == get!T;
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
        // TODO: Make @safe when TypeInfo.cmp is @safe as well.
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

            const typeCmp = type.opCmp(rhs.type);
            if(typeCmp != 0){return typeCmp;}

            static int compareCollections(T)(const ref Node lhs, const ref Node rhs)
            {
                const c1 = lhs.getValue!T;
                const c2 = rhs.getValue!T;
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

            if(isSequence){return compareCollections!(Node[])(this, rhs);}
            if(isMapping) {return compareCollections!(Pair[])(this, rhs);}
            if(isString)
            {
                return std.algorithm.cmp(getValue!string,
                                         rhs.getValue!string);
            }
            if(isInt)
            {
                return cmp(getValue!long, rhs.getValue!long);
            }
            if(isBool)
            {
                const b1 = getValue!bool;
                const b2 = rhs.getValue!bool;
                return b1 ? b2 ? 0 : 1
                          : b2 ? -1 : 0;
            }
            if(isBinary)
            {
                const b1 = getValue!(ubyte[]);
                const b2 = rhs.getValue!(ubyte[]);
                return std.algorithm.cmp(b1, b2);
            }
            if(isNull)
            {
                return 0;
            }
            // Floats need special handling for NaNs .
            // We consider NaN to be lower than any float.
            if(isFloat)
            {
                const r1 = getValue!real;
                const r2 = rhs.getValue!real;
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
            }
            else if(isTime)
            {
                const t1 = getValue!SysTime;
                const t2 = rhs.getValue!SysTime;
                return cmp(t1, t2);
            }
            else if(isUserType)
            {
                return getValue!YAMLObject.cmp(rhs.getValue!YAMLObject);
            }
            assert(false, "Unknown type of node for comparison : " ~ type.toString());
        }

        // Get a string representation of the node tree. Used for debugging.
        //
        // Params:  level = Level of the node in the tree.
        //
        // Returns: String representing the node tree.
        @property string debugString(uint level = 0) const @safe
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
                       (convertsTo!string ? get!string : type.toString()) ~ ")\n";
            }
            assert(false);
        }

        // Get type of the node value (YAMLObject for user types).
        @property TypeInfo type() const @safe nothrow
        {
            return value_.type;
        }

    public:
        // Determine if the value stored by the node is of specified type.
        //
        // This only works for default YAML types, not for user defined types.
        @property bool isType(T)() const
        {
            return this.type is typeid(Unqual!T);
        }

        // Is the value a bool?
        alias isType!bool isBool;

        // Is the value a raw binary buffer?
        alias isType!(ubyte[]) isBinary;

        // Is the value an integer?
        alias isType!long isInt;

        // Is the value a floating point number?
        alias isType!real isFloat;

        // Is the value a string?
        alias isType!string isString;

        // Is the value a timestamp?
        alias isType!SysTime isTime;

        // Does given node have the same type as this node?
        bool hasEqualType(const ref Node node) const @safe
        {
            return this.type is node.type;
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
        @property bool convertsTo(T)() const
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
        bool contains_(T, Flag!"key" key, string func)(T rhs) const
        {
            static if(!key) if(isSequence)
            {
                foreach(ref node; getValue!(Node[]))
                {
                    if(node == rhs){return true;}
                }
                return false;
            }

            if(isMapping)
            {
                return findPair!(T, key)(rhs) >= 0;
            }

            throw new NodeException("Trying to use " ~ func ~ "() on a " ~ nodeTypeString ~ " node",
                            startMark_);
        }

        // Implementation of remove() and removeAt()
        void remove_(T, Flag!"key" key, string func)(T rhs)
        {
            enforce(isSequence || isMapping,
                    new NodeException("Trying to " ~ func ~ "() from a " ~ nodeTypeString ~ " node",
                              startMark_));

            static void removeElem(E, I)(ref Node node, I index)
            {
                auto elems = node.getValue!(E[]);
                moveAll(elems[cast(size_t)index + 1 .. $], elems[cast(size_t)index .. $ - 1]);
                elems.length = elems.length - 1;
                node.setValue(elems);
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
        // Cannot be inferred @safe due to https://issues.dlang.org/show_bug.cgi?id=16528
        sizediff_t findPair(T, Flag!"key" key = Yes.key)(const ref T index) const @safe
        {
            const pairs = getValue!(Pair[])();
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
        void checkSequenceIndex(T)(T index) const
        {
            assert(isSequence,
                   "checkSequenceIndex() called on a " ~ nodeTypeString ~ " node");

            static if(!isIntegral!T)
            {
                throw new NodeException("Indexing a sequence with a non-integral type.", startMark_);
            }
            else
            {
                enforce(index >= 0 && index < getValue!(Node[]).length,
                        new NodeException("Sequence index out of range: " ~ to!string(index),
                                  startMark_));
            }
        }
        // Safe wrapper for getting a value out of the variant.
        inout(T) getValue(T)() @trusted inout
        {
            return value_.get!T;
        }
        // Safe wrapper for coercing a value out of the variant.
        inout(T) coerceValue(T)() @trusted inout
        {
            return (cast(Value)value_).coerce!T;
        }
        // Safe wrapper for setting a value for the variant.
        void setValue(T)(T value) @trusted
        {
            static if (allowed!T)
            {
                value_ = value;
            }
            else
            {
                value_ = cast(YAMLObject)new YAMLContainer!T(value);
            }
        }
}

package:
// Merge pairs into an array of pairs based on merge rules in the YAML spec.
//
// Any new pair will only be added if there is not already a pair
// with the same key.
//
// Params:  pairs   = Appender managing the array of pairs to merge into.
//          toMerge = Pairs to merge.
void merge(ref Appender!(Node.Pair[]) pairs, Node.Pair[] toMerge) @safe
{
    bool eq(ref Node.Pair a, ref Node.Pair b){return a.key == b.key;}

    foreach(ref pair; toMerge) if(!canFind!eq(pairs.data, pair))
    {
        pairs.put(pair);
    }
}
