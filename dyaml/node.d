
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * Node of a YAML document. Used to read YAML data once it's loaded,
 * and to prepare data to emit.
 */
module dyaml.node;


import std.algorithm;
import std.conv;
import std.datetime;
import std.exception;
import std.math;
import std.stdio;   
import std.string;
import std.traits;
import std.typecons;
import std.variant;

import dyaml.event;
import dyaml.exception;
import dyaml.tag;


///Exception thrown at node related errors.
class NodeException : YAMLException
{
    package:
        /*
         * Construct a NodeException.
         *
         * Params:  msg   = Error message.
         *          start = Start position of the node.
         */
        this(string msg, Mark start, string file = __FILE__, int line = __LINE__)
        {
            super(msg ~ "\nNode at:" ~ start.toString(), file, line);
        }
}

//Node kinds.
package enum NodeID : ubyte
{
    Scalar,
    Sequence,
    Mapping
}

///Null YAML type. Used in nodes with _null values.
struct YAMLNull{}

//Merge YAML type, used to support "tag:yaml.org,2002:merge".
package struct YAMLMerge{}

//Base class for YAMLContainer - used for user defined YAML types.
package abstract class YAMLObject
{
    public:
        ///Get type of the stored value.
        @property TypeInfo type() const;

    protected:
        ///Test for equality with another YAMLObject.
        bool equals(const YAMLObject rhs) const;
}

//Stores a user defined YAML data type.
package class YAMLContainer(T) : YAMLObject
{
    private:
        //Stored value.
        T value_;

    public:
        //Get type of the stored value.
        @property override TypeInfo type() const {return typeid(T);}

        //Get string representation of the container.
        override string toString()
        {
            static if(!hasMember!(T, "toString"))
            {
                return super.toString();
            }
            else
            {
                return format("YAMLContainer(", value_.toString(), ")");
            }
        }

    protected:
        //Test for equality with another YAMLObject.
        override bool equals(const YAMLObject rhs) const 
        {
            if(rhs.type !is typeid(T)){return false;}
            return value_ == (cast(YAMLContainer)rhs).value_;
        }

    private:
        //Construct a YAMLContainer holding specified value.
        this(T value){value_ = value;}
}


/**
 * YAML node.
 *
 * This is a pseudo-dynamic type that can store any YAML value, including a 
 * sequence or mapping of nodes. You can get data from a Node directly or 
 * iterate over it if it's a collection.
 */
struct Node
{
    public:
        ///Key-value pair of YAML nodes, used in mappings.
        struct Pair
        {
            public:
                ///Key node.
                Node key;
                ///Value node.
                Node value;

            public:
                ///Construct a Pair from two values. Will be converted to Nodes if needed.
                this(K, V)(K key, V value)
                {
                    static if(is(K == Node)){this.key = key;}
                    else                    {this.key = Node(key);}
                    static if(is(V == Node)){this.value = value;}
                    else                    {this.value = Node(value);}
                }

                ///Equality test with another Pair.
                bool equals(ref Pair rhs)
                {
                    return equals_!true(rhs);
                }

            private:
                /* 
                 * Equality test with another Pair.
                 *
                 * useTag determines whether or not we consider node tags 
                 * in the test.
                 */
                bool equals_(bool useTag)(ref Pair rhs) 
                {
                    return key.equals!(Node, useTag)(rhs.key) && 
                           value.equals!(Node, useTag)(rhs.value);
                }
        }

    package:
        //YAML value type.
        alias Algebraic!(YAMLNull, YAMLMerge, bool, long, real, ubyte[], SysTime, string,
                         Node.Pair[], Node[], YAMLObject) Value;

    private:
        ///Stored value.
        Value value_;
        ///Start position of the node.
        Mark startMark_;
        ///Tag of the node.
        Tag tag_;

    public:
        /**
         * Construct a Node from a value.
         *
         * Any type except of Node can be stored in a Node, but default YAML 
         * types (integers, floats, strings, timestamps, etc.) will be stored
         * more efficiently. 
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
        this(T)(T value, in string tag = null) if (isSomeString!T || 
                                                  (!isArray!T && !isAssociativeArray!T))
        {
            tag_ = Tag(tag);

            //No copyconstruction.
            static assert(!is(T == Node));

            //We can easily convert ints, floats, strings.
            static if(isIntegral!T)          {value_ = Value(cast(long) value);}
            else static if(isFloatingPoint!T){value_ = Value(cast(real) value);}
            else static if(isSomeString!T)   {value_ = Value(to!string(value));}
            //Other directly supported type.
            else static if(Value.allowed!T)  {value_ = Value(value);}
            //User defined type.
            else                             {value_ = userValue(value);}
        }
        unittest
        {
            with(Node(42))
            {
                assert(isScalar() && !isSequence && !isMapping && !isUserType);
                assert(get!int == 42 && get!float == 42.0f && get!string == "42");
                assert(!isUserType());
            }
            with(Node(new class{int a = 5;}))
            {
                assert(isUserType());
            }
        }

        /**
         * Construct a node from an _array.
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
         * //Will be emitted as a sequence (default for arrays)
         * auto seq = Node([1, 2, 3, 4, 5]);
         * //Will be emitted as a set (overriden tag)
         * auto set = Node([1, 2, 3, 4, 5], "tag:yaml.org,2002:set");
         * --------------------
         */
        this(T)(T[] array, in string tag = null) if (!isSomeString!(T[]))
        {
            tag_ = Tag(tag);

            //Construction from raw node or pair array.
            static if(is(T == Node) || is(T == Node.Pair))
            {
                value_ = Value(array);
            }
            //Need to handle byte buffers separately.
            else static if(is(T == byte) || is(T == ubyte))
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
                assert(opIndex(2).get!int == 3);
            }

            //Will be emitted as a sequence (default for arrays)
            auto seq = Node([1, 2, 3, 4, 5]);
            //Will be emitted as a set (overriden tag)
            auto set = Node([1, 2, 3, 4, 5], "tag:yaml.org,2002:set");
        }

        /**
         * Construct a node from an associative _array.
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
         * //Will be emitted as an unordered mapping (default for mappings)
         * auto map   = Node([1 : "a", 2 : "b"]);
         * //Will be emitted as an ordered map (overriden tag)
         * auto omap  = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:omap");
         * //Will be emitted as pairs (overriden tag)
         * auto pairs = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:pairs");
         * --------------------
         */
        this(K, V)(V[K] array, in string tag = null)
        {
            tag_ = Tag(tag);

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
                assert(opIndex("2").get!int == 2);
            }

            //Will be emitted as an unordered mapping (default for mappings)
            auto map   = Node([1 : "a", 2 : "b"]);
            //Will be emitted as an ordered map (overriden tag)
            auto omap  = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:omap");
            //Will be emitted as pairs (overriden tag)
            auto pairs = Node([1 : "a", 2 : "b"], "tag:yaml.org,2002:pairs");
        }

        /**
         * Construct a node from arrays of _keys and _values.
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
         * //Will be emitted as an unordered mapping (default for mappings)
         * auto map   = Node([1, 2], ["a", "b"]);
         * //Will be emitted as an ordered map (overriden tag)
         * auto omap  = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:omap");
         * //Will be emitted as pairs (overriden tag)
         * auto pairs = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:pairs");
         * --------------------
         */
        this(K, V)(K[] keys, V[] values, in string tag = null) 
            if(!(isSomeString!(K[]) || isSomeString!(V[])))
        in
        {
            assert(keys.length == values.length, 
                   "Lengths of keys and values arrays to construct "
                   "a YAML node from don't match");
        }
        body
        {
            tag_ = Tag(tag);

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
                assert(opIndex("2").get!int == 2);
            }

            //Will be emitted as an unordered mapping (default for mappings)
            auto map   = Node([1, 2], ["a", "b"]);
            //Will be emitted as an ordered map (overriden tag)
            auto omap  = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:omap");
            //Will be emitted as pairs (overriden tag)
            auto pairs = Node([1, 2], ["a", "b"], "tag:yaml.org,2002:pairs");
        }

        ///Is this node valid (initialized)? 
        @property bool isValid()    const {return value_.hasValue;}
                                            
        ///Is this node a scalar value?
        @property bool isScalar()   const {return !(isMapping || isSequence);}
                                            
        ///Is this node a sequence?
        @property bool isSequence() const {return isType!(Node[]);}
                                            
        ///Is this node a mapping?
        @property bool isMapping()  const {return isType!(Pair[]);}

        ///Is this node a user defined type?
        @property bool isUserType() const {return isType!YAMLObject;}

        /**
         * Equality test.
         *
         * If T is Node, recursively compare all subnodes. 
         * This might be quite expensive if testing entire documents.
         *
         * If T is not Node, convert the node to T and test equality with that.
         *
         * Examples:
         * --------------------
         * auto node = Node(42);
         *
         * assert(node == 42);
         * assert(node == "42");
         * assert(node != "43");
         * --------------------
         *
         * Params:  rhs = Variable to test equality with.
         *
         * Returns: true if equal, false otherwise.
         */
        bool opEquals(T)(ref T rhs)
        {
            return equals!(T, true)(rhs);
        }

        /**
         * Get the value of the node as specified type.
         *
         * If the specifed type does not match type in the node,
         * conversion is attempted.
         *
         * Timestamps are stored as std.datetime.SysTime.
         * Binary values are decoded and stored as ubyte[]. 
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
         * assert(node.get!int == 42);
         * assert(node.get!string == "42");
         * assert(node.get!double == 42.0);
         * --------------------
         *
         * Returns: Value of the node as specified type.
         *
         * Throws:  NodeException if unable to convert to specified type.
         */
        @property T get(T)()
        {
            T result;
            getToVar(result);
            return result;
        }

        /**
         * Write the value of the node to target.
         *
         * If the target type does not match node type,
         * conversion is attempted.
         *
         * Params:  target = Variable to write to.
         *
         * Throws:  NodeException if unable to convert to specified type.
         */
        void getToVar(T)(out T target)
        {
            if(isType!T)
            {
                target = value_.get!T;
                return;
            }

            ///Must go before others, as even string/int/etc could be stored in a YAMLObject.
            if(isUserType)
            {
                auto object = get!YAMLObject;
                if(object.type is typeid(T))
                {
                    target = (cast(YAMLContainer!T)object).value_;
                    return;
                }
            }

            //If we're getting from a mapping and we're not getting Node.Pair[],
            //we're getting the default value.
            if(isMapping){return this["="].get!T;}

            void throwUnexpectedType()
            {
                //Can't get the value.
                throw new NodeException("Node has unexpected type " ~ type.toString ~ 
                                        ". Expected " ~ typeid(T).toString, startMark_);
            }

            static if(isSomeString!T)
            {
                //Try to convert to string.
                try
                {
                    target = value_.coerce!T();
                    return;
                }
                catch(VariantException e)
                {
                    throw new NodeException("Unable to convert node value to a string",
                                            startMark_);
                }
            }
            else static if(isFloatingPoint!T)
            {
                ///Can convert int to float.
                if(isInt())
                {
                    target = to!T(value_.get!long);
                    return;
                }
                else if(isFloat())
                {
                    target = to!T(value_.get!real);
                    return;
                }
            }
            else static if(isIntegral!T)
            {
                if(isInt())
                {                
                    long temp = value_.get!long;
                    if(temp < T.min || temp > T.max)
                    {
                        throw new NodeException("Integer value out of range of type " ~
                                                typeid(T).toString ~ "Value: " ~ 
                                                to!string(temp), startMark_);
                    }
                    target = to!T(temp);
                    return;
                }
                else
                {
                    throwUnexpectedType();
                }
            }
            else
            {
                throwUnexpectedType();
            }
        }

        /**
         * If this is a collection, return its _length.
         *
         * Otherwise, throw NodeException.
         *
         * Returns: Number of elements in a sequence or key-value pairs in a mapping.
         *
         * Throws: NodeException if this is not a sequence nor a mapping.
         */
        @property size_t length()
        {
            if(isSequence)    {return get!(Node[]).length;}
            else if(isMapping){return get!(Pair[]).length;}
            throw new NodeException("Trying to get length of a node that is not a collection",
                                    startMark_);
        }

        /**
         * Get the element at specified index.
         *
         * If the node is a sequence, index must be integral.
         *
         *
         * If the node is a mapping, return the value corresponding to the first 
         * key equal to index, even after conversion. I.e; node["12"] will 
         * return value of the first key that equals "12", even if it's an integer.
         *
         * Params:  index = Index to use.
         *
         * Returns: Value corresponding to the index.
         *
         * Throws:  NodeException if the index could not be found,
         *          non-integral index is used with a sequence or the node is
         *          not a collection.
         */
        Node opIndex(T)(T index)
        {
            if(isSequence)
            {
                checkSequenceIndex(index);
                static if(isIntegral!T){return value_.get!(Node[])[index];}
                assert(false);
            }
            else if(isMapping)
            {
                auto idx = findPair(index);
                if(idx >= 0){return get!(Pair[])[idx].value;}

                throw new NodeException("Mapping index not found" ~ 
                                        isSomeString!T ? ": " ~ to!string(index) : "",
                                        startMark_);
            }
            throw new NodeException("Trying to index node that does not support indexing",
                                    startMark_);
        }
        unittest
        {
            writeln("D:YAML Node opIndex unittest");

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

            Node narray = Node(Value([n1, n2, n3, n4]));
            Node nmap   = Node(Value([Pair(k1, n1),
                                      Pair(k2, n2),  
                                      Pair(k3, n3),  
                                      Pair(k4, n4)]));

            assert(narray[0].get!int == 11);
            assert(null !is collectException(narray[42]));
            assert(nmap["11"].get!int == 11);
            assert(nmap["14"].get!int == 14);
            assert(null !is collectException(nmap["42"]));
        }

        /**
         * Set element at specified index in a collection.
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
         * Params:  index = Index of the value to set.
         *
         * Throws:  NodeException if the node is not a collection, index is out
         *          of range or if a non-integral index is used on a sequence node.
         */
        void opIndexAssign(K, V)(V value, K index)
        {
            if(isSequence())
            {
                //This ensures K is integral.
                checkSequenceIndex(index);
                static if(isIntegral!K)
                {
                    auto nodes = value_.get!(Node[]);
                    static if(is(V == Node)){nodes[index] = value;}
                    else                    {nodes[index] = Node(value);}
                    value_ = Value(nodes);
                    return;
                }
                assert(false);
            }
            else if(isMapping())
            {
                auto idx = findPair(index);
                if(idx < 0){add(index, value);}
                else
                {
                    auto pairs = get!(Node.Pair[])();
                    static if(is(V == Node)){pairs[idx].value = value;}
                    else                    {pairs[idx].value = Node(value);}
                    value_ = Value(pairs);
                }
                return;
            }

            throw new NodeException("Trying to index a YAML node that is not a collection.", 
                                    startMark_);
        }
        unittest
        {
            writeln("D:YAML Node opIndexAssign unittest");

            with(Node([1, 2, 3, 4, 3]))
            {
                opIndexAssign(42, 3);
                assert(length == 5);
                assert(opIndex(3).get!int == 42);
            }
            with(Node(["1", "2", "3"], [4, 5, 6]))
            {
                opIndexAssign(42, "3");
                opIndexAssign(123, 456);
                assert(length == 4);
                assert(opIndex("3").get!int == 42);
                assert(opIndex(456).get!int == 123);
            }
        }

        /**
         * Iterate over a sequence, getting each element as T.
         *
         * If T is Node, simply iterate over the nodes in the sequence.
         * Otherwise, convert each node to T during iteration.
         *
         * Throws:  NodeException if the node is not a sequence or an
         *          element could not be converted to specified type.
         */
        int opApply(T)(int delegate(ref T) dg)
        {
            enforce(isSequence, 
                    new NodeException("Trying to iterate over a node that is not a sequence",
                                      startMark_));

            int result = 0;
            foreach(ref node; get!(Node[]))
            {
                static if(is(T == Node))
                {
                    result = dg(node);
                }
                else
                {
                    T temp = node.get!T;
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
            Node narray = Node(Value([n1, n2, n3, n4]));

            int[] array, array2;
            foreach(int value; narray)
            {
                array ~= value;
            }
            foreach(Node node; narray)
            {
                array2 ~= node.get!int;
            }
            assert(array == [11, 12, 13, 14]);
            assert(array2 == [11, 12, 13, 14]);
        }

        /**
         * Iterate over a mapping, getting each key/value as K/V.
         *
         * If the K and/or V is Node, simply iterate over the nodes in the mapping.
         * Otherwise, convert each key/value to T during iteration.
         *
         * Throws:  NodeException if the node is not a mapping or an
         *          element could not be converted to specified type.
         */
        int opApply(K, V)(int delegate(ref K, ref V) dg)
        {
            enforce(isMapping,
                    new NodeException("Trying to iterate over a node that is not a mapping",
                                      startMark_));

            int result = 0;
            foreach(ref pair; get!(Node.Pair[]))
            {
                static if(is(K == Node) && is(V == Node))
                {
                    result = dg(pair.key, pair.value);
                }
                else static if(is(K == Node))
                {
                    V tempValue = pair.value.get!V;
                    result = dg(pair.key, tempValue);
                }
                else static if(is(V == Node))
                {
                    K tempKey   = pair.key.get!K;
                    result = dg(tempKey, pair.value);
                }
                else
                {
                    K tempKey   = pair.key.get!K;
                    V tempValue = pair.value.get!V;
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

            Node n1 = Node(Value(cast(long)11));
            Node n2 = Node(Value(cast(long)12));
            Node n3 = Node(Value(cast(long)13));
            Node n4 = Node(Value(cast(long)14));

            Node k1 = Node(Value("11"));
            Node k2 = Node(Value("12"));
            Node k3 = Node(Value("13"));
            Node k4 = Node(Value("14"));

            Node nmap1 = Node(Value([Pair(k1, n1),
                                     Pair(k2, n2),  
                                     Pair(k3, n3),  
                                     Pair(k4, n4)]));

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

            Node nmap2 = Node(Value([Pair(k1, Node(Value(cast(long)5))),
                                     Pair(k2, Node(Value(true))),  
                                     Pair(k3, Node(Value(cast(real)1.0))),  
                                     Pair(k4, Node(Value("yarly")))]));

            foreach(string key, Node value; nmap2)
            {
                switch(key)
                {
                    case "11": assert(value.get!int    == 5      ); break;
                    case "12": assert(value.get!bool   == true   ); break;
                    case "13": assert(value.get!float  == 1.0    ); break;
                    case "14": assert(value.get!string == "yarly"); break;
                    default:   assert(false);
                }
            }
        }

        /**
         * Add an element to a sequence.
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
                    new NodeException("Trying to add an element to a "
                                      "non-sequence YAML node", startMark_));

            auto nodes = get!(Node[])();
            static if(is(T == Node)){nodes ~= value;}
            else                    {nodes ~= Node(value);}
            value_ = Value(nodes);
        }
        unittest
        {
            writeln("D:YAML Node add unittest 1");

            with(Node([1, 2, 3, 4]))
            {
                add(5.0f);
                assert(opIndex(4).get!float == 5.0f);
            }
        }

        /**
         * Add a key-value pair to a mapping.
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
                    new NodeException("Trying to add a key-value pair to a "
                                      "non-mapping YAML node", startMark_));

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
                assert(opIndex(5).get!string == "6");
            }
        }

        /**
         * Remove first (if any) occurence of a value in a collection.
         *
         * This method can only be called on collection nodes.
         *
         * If the node is a sequence, the first node matching value (including
         * conversion, so e.g. "42" matches 42) is removed.
         * If the node is a mapping, the first key-value pair where _value 
         * matches specified value is removed.
         * 
         * Params:  value = Value to _remove.
         *
         * Throws:  NodeException if the node is not a collection.
         */
        void remove(T)(T value)
        {
            if(isSequence())
            {
                foreach(idx, ref elem; get!(Node[]))
                {
                    if(elem.convertsTo!T && elem.get!T == value)
                    {
                        removeAt(idx);
                        return;
                    }
                }
                return;
            }
            else if(isMapping())
            {
                auto idx = findPair!(T, true)(value);
                if(idx >= 0)
                {
                    auto pairs = get!(Node.Pair[])();
                    moveAll(pairs[idx + 1 .. $], pairs[idx .. $ - 1]);
                    pairs.length = pairs.length - 1;
                    value_ = Value(pairs);
                }
                return;
            }
            throw new NodeException("Trying to remove an element from a YAML node that "
                                    "is not a collection.", startMark_);
        }
        unittest
        {
            writeln("D:YAML Node remove unittest");
            with(Node([1, 2, 3, 4, 3]))
            {
                remove(3);
                assert(length == 4);
                assert(opIndex(2).get!int == 4);
                assert(opIndex(3).get!int == 3);
            }
            with(Node(["1", "2", "3"], [4, 5, 6]))
            {
                remove(4);
                assert(length == 2);
            }
        }

        /**
         * Remove element at the specified index of a collection.
         *
         * This method can only be called on collection nodes.
         * 
         * If the node is a sequence, index must be integral.
         *
         * If the node is a mapping, remove the first key-value pair where 
         * key matches index (including conversion, so e.g. "42" matches 42).
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
            if(isSequence())
            {
                //This ensures T is integral.
                checkSequenceIndex(index);
                static if(isIntegral!T)
                {
                    auto nodes = value_.get!(Node[]);
                    moveAll(nodes[index + 1 .. $], nodes[index .. $ - 1]);
                    nodes.length = nodes.length - 1;
                    value_ = Value(nodes);
                    return;
                }
                assert(false);
            }
            else if(isMapping())
            {
                auto idx = findPair(index);
                if(idx >= 0)
                {
                    auto pairs = get!(Node.Pair[])();
                    moveAll(pairs[idx + 1 .. $], pairs[idx .. $ - 1]);
                    pairs.length = pairs.length - 1;
                    value_ = Value(pairs);
                }
                return;
            }
            throw new NodeException("Trying to remove an element from a YAML node that "
                                    "is not a collection.", startMark_);
        }
        unittest
        {
            writeln("D:YAML Node removeAt unittest");
            with(Node([1, 2, 3, 4, 3]))
            {
                removeAt(3);
                assert(length == 4);
                assert(opIndex(3).get!int == 3);
            }
            with(Node(["1", "2", "3"], [4, 5, 6]))
            {
                removeAt("2");
                assert(length == 2);
            }
        }

    package:
        /*
         * Construct a node from raw data.
         *
         * Params:  value     = Value of the node.
         *          startMark = Start position of the node in file.
         *          tag       = Tag of the node.
         *
         * Returns: Constructed node.
         */
        static Node rawNode(Value value, in Mark startMark = Mark(), in Tag tag = Tag("DUMMY_TAG"))
        {
            Node node;
            node.value_ = value;
            node.startMark_ = startMark;
            node.tag_ = tag;

            return node;
        }

        /*
         * Equality test with any value.
         *
         * useTag determines whether or not to consider tags in node-node comparisons.
         */
        bool equals(T, bool useTag)(ref T rhs)
        {
            static if(is(T == Node))
            {
                static if(useTag)
                {
                    if(tag_ != rhs.tag_){return false;}
                }

                if(!isValid){return !rhs.isValid;}
                if(!rhs.isValid || !hasEqualType(rhs))
                {
                    return false;
                }
                if(isSequence)
                {
                    auto seq1 = get!(Node[]);
                    auto seq2 = rhs.get!(Node[]);
                    if(seq1 is seq2){return true;}
                    if(seq1.length != seq2.length){return false;}
                    foreach(node; 0 .. seq1.length)
                    {
                        if(!seq1[node].equals!(T, useTag)(seq2[node])){return false;}
                    }
                    return true;
                }
                if(isMapping)
                {
                    auto map1 = get!(Node.Pair[]);
                    auto map2 = rhs.get!(Node.Pair[]);
                    if(map1 is map2){return true;}
                    if(map1.length != map2.length){return false;}
                    foreach(pair; 0 .. map1.length)
                    {
                        if(!map1[pair].equals_!useTag(map2[pair])){return false;}
                    }
                    return true;
                }
                if(isScalar)
                {
                    if(isUserType)
                    {
                        if(!rhs.isUserType){return false;}
                        return get!YAMLObject.equals(rhs.get!YAMLObject);
                    }
                    if(isFloat)
                    {
                        if(!rhs.isFloat){return false;}
                        real r1 = get!real;
                        real r2 = rhs.get!real;
                        bool equals(real r1, real r2)
                        {
                            return r1 <= r2 + real.epsilon && r1 >= r2 - real.epsilon;
                        }
                        if(isNaN(r1)){return isNaN(r2);}
                        return equals(r1, r2);
                    }
                    else
                    {
                        return value_ == rhs.value_;
                    }
                }
                assert(false, "Unknown kind of node");
            }
            else
            {
                try{return rhs == get!T;}
                catch(NodeException e){return false;}
            }
        }

        /*
         * Get a string representation of the node tree. Used for debugging.
         *
         * Params:  level = Level of the node in the tree.
         *
         * Returns: String representing the node tree.
         */
        @property string debugString(uint level = 0)
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
                       (convertsTo!string ? get!string : type.toString) ~ ")\n";
            }
            assert(false);
        }

        //Construct Node.Value from user defined type.
        static Value userValue(T)(T value)
        {
            return Value(cast(YAMLObject)new YAMLContainer!T(value));
        }

        //Get type of the node value (YAMLObject for user types).
        @property TypeInfo type() const {return value_.type;}

        /*
         * Determine if the value stored by the node is of specified type.
         *
         * This only works for default YAML types, not for user defined types.
         */
        @property bool isType(T)() const {return value_.type is typeid(T);}

        //Return tag of the node.
        @property Tag tag() const {return tag_;}

        //Set tag of the node.
        @property void tag(Tag tag) {tag_ = tag;}

    private:
        //Is the value an integer of some kind?
        alias isType!long isInt;

        //Is the value a floating point number of some kind?
        alias isType!real isFloat;

        //Is the value a string of some kind?
        alias isType!string isString;

        //Does given node have the same type as this node?
        bool hasEqualType(ref Node node)
        {                 
            return value_.type is node.value_.type;
        }

        //Determine if the value can be converted to specified type.
        bool convertsTo(T)()
        {
            if(isType!T){return true;}

            static if(isSomeString!T)
            {
                try
                {
                    auto dummy = value_.coerce!T();
                    return true;
                }
                catch(VariantException e){return false;}
            }
            else static if(isFloatingPoint!T){return isInt() || isFloat();}
            else static if(isIntegral!T)     {return isInt();}
            else                             {return false;}
        }

        //Get index of pair with key (or value, if value is true) matching index.
        long findPair(T, bool value = false)(const ref T index)
        {
            auto pairs = get!(Node.Pair[])();
            Node* node;
            foreach(idx, ref pair; pairs)
            {
                static if(value){node = &pair.value;}
                else{node = &pair.key;}

                static if(is(T == Node))
                {
                    if(*node == index){return idx;}
                }
                else static if(isFloatingPoint!T)
                {
                    //Need to handle NaNs separately.
                    if((node.get!T == index) ||
                       (isFloat && isNaN(index) && isNaN(node.get!real)))
                    {
                        return idx;
                    }
                }
                else 
                {  
                    try
                    {
                        if(node.get!T == index){return idx;}
                    }
                    catch(NodeException e)
                    {
                        continue;
                    }
                }
            }
            return -1;
        }

        //Check if index is integral and in range.
        void checkSequenceIndex(T)(T index)
        {
            static if(!isIntegral!T)
            {
                throw new NodeException("Indexing a YAML sequence with a non-integral type.",
                                        startMark_);
            }
            else
            {
                enforce(index >= 0 && index < value_.get!(Node[]).length,
                        new NodeException("Index to a YAML sequence out of range: " 
                                          ~ to!string(index), startMark_));
            }
        }
}

package:
/*
 * Merge a pair into an array of pairs based on merge rules in the YAML spec.
 *
 * The new pair will only be added if there is not already a pair 
 * with the same key.
 *
 * Params:  pairs   = Array of pairs to merge into.
 *          toMerge = Pair to merge.
 */
void merge(ref Node.Pair[] pairs, ref Node.Pair toMerge)
{
    foreach(ref pair; pairs)
    {
        if(pair.key == toMerge.key){return;}
    }
    pairs ~= toMerge;
}

/*
 * Merge pairs into an array of pairs based on merge rules in the YAML spec.
 *
 * Any new pair will only be added if there is not already a pair 
 * with the same key.
 *
 * Params:  pairs   = Array of pairs to merge into.
 *          toMerge = Pairs to merge.
 */
void merge(ref Node.Pair[] pairs, Node.Pair[] toMerge)
{
    foreach(ref pair; toMerge){merge(pairs, pair);}
}
