
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * Node of a YAML document. Used to read YAML data once it's loaded.
 */
module dyaml.node;


import std.algorithm;
import std.conv;
import std.datetime;
import std.exception;
import std.math;
import std.stdio;   
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
        this(string msg, Mark start)
        {
            super(msg ~ "\nNode at:" ~ start.toString());
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

///Base class for YAMLContainer - used for user defined YAML types.
private abstract class YAMLObject
{
    protected:
        ///Get type of the stored value.
        @property TypeInfo type() const;

        ///Test for equality with another YAMLObject.
        bool equals(const YAMLObject rhs) const;
}

//Stores a user defined YAML data type.
private class YAMLContainer(T) : YAMLObject
{
    private:
        //Stored value.
        T value_;

        //Construct a YAMLContainer holding specified value.
        this(T value){value_ = value;}

    protected:
        //Get type of the stored value.
        @property override TypeInfo type() const {return typeid(T);}

        //Test for equality with another YAMLObject.
        override bool equals(const YAMLObject rhs) const 
        {
            if(rhs.type !is typeid(T)){return false;}
            return value_ == (cast(YAMLContainer)rhs).value_;
        }
}


/**
 * YAML node.
 *
 * This is a pseudo-dynamic type that can store any YAML value, including sequence 
 * or a mapping of nodes. You can get data from a Node directly or iterate over it
 * if it's a sequence or a mapping.
 */
struct Node
{
    public:
        ///Pair of YAML nodes, used in mappings.
        struct Pair
        {
            public:
                ///Key node.
                Node key;
                ///Value node.
                Node value;

            public:
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
        //Stored value.
        Value value_;
        ///Start position of the node.
        Mark startMark_;
        ///Tag of the node.
        Tag tag_;

    public:
        ///Is this node valid (initialized)? 
        @property bool isValid()    const {return value_.hasValue;}
                                            
        ///Is this node a scalar value?
        @property bool isScalar()   const {return !(isMapping || isSequence);}
                                            
        ///Is this node a sequence of nodes?
        @property bool isSequence() const {return isType!(Node[]);}
                                            
        ///Is this node a mapping of nodes?
        @property bool isMapping()  const {return isType!(Pair[]);}

        ///Is this node a user defined type?
        @property bool isUserType() const {return isType!YAMLObject;}

        /**
         * Equality test.
         *
         * If T is Node, recursively compare all 
         * subnodes and might be quite expensive if testing entire documents.
         *
         * If T is not Node, convert the node to T and test equality with that.
         *
         * Examples:
         * --------------------
         * //node is a Node that contains integer 42
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
         * conversion is attempted if possible.
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
         * by old versions of the program, which expects the node to be a scalar.
         * )
         *
         * Examples:
         *
         * Automatic type conversion:
         * --------------------
         * //node is a node that contains integer 42
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
         * If the type of target does not match type of the node,
         * conversion is attempted, if possible.
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
            }
            else
            {
                //Can't get the value.
                throw new NodeException("Node has unexpected type " ~ typeString ~ 
                                        ". Expected " ~ typeid(T).toString, startMark_);
            }
        }

        /**
         * If this is a sequence or a mapping, return its length.
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
         * Get the element with specified index.
         *
         * If the node is a sequence, index must be integral.
         *
         * If the node is a mapping, return the value corresponding to the first 
         * key equal to index, even after conversion. I.e; node["12"] will 
         * return value of the first key that equals "12", even if it's an integer.
         *
         * Params:  index = Index to use.
         *
         * Returns: Value corresponding to the index.
         *
         * Throws:  NodeException if the index could not be found.
         */
        Node opIndex(T)(in T index)
        {
            if(isSequence)
            {
                //Sequence, index must be integral.
                static if(isIntegral!T)
                {
                    auto nodes = value_.get!(Node[]);
                    enforce(index >= 0 && index < nodes.length,
                            new NodeException("Index to a sequence out of range: " 
                                              ~ to!string(index), startMark_));
                    return nodes[index];
                }
                else
                {
                    throw new NodeException("Indexing a sequence with a non-integer type.",
                                            startMark_);
                }
            }
            else if(isMapping)
            {
                //Mapping, look for keys convertible to T with value of index.
                foreach(ref pair; get!(Pair[]))
                {
                    //Handle NaN.
                    static if(isFloatingPoint!T)
                    {
                        if(isFloat && isNaN(index) && isNaN(pair.key.get!real))
                        {
                            return pair.value;
                        }
                    }
                    //If we can get the key as type T, get it and compare to
                    //index, and return value if the key matches.
                    if(pair.key.convertsTo!T && pair.key.get!T == index)
                    {
                        return pair.value;
                    }
                }
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
            Node n1 = Node(Value(cast(long)11));
            Node n2 = Node(Value(cast(long)12));
            Node n3 = Node(Value(cast(long)13));
            Node n4 = Node(Value(cast(long)14));

            Node k1 = Node(Value("11"));
            Node k2 = Node(Value("12"));
            Node k3 = Node(Value("13"));
            Node k4 = Node(Value("14"));

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

    package:
        /*
         * Construct a node from raw data.
         *
         * Params:  value     = Value of the node.
         *          startMark = Start position of the node in file.
         *          tag       = Tag of the node.
         */
        this(Value value, in Mark startMark = Mark(), in Tag tag = Tag("DUMMY_TAG"))
        {
            value_ = value;
            startMark_ = startMark;
            tag_ = tag;
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
                        if(isNaN(r1)){return isNaN(r2);}
                        return r1 == r2;
                    }
                    else{return value_ == rhs.value_;}
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
                       (convertsTo!string ? get!string : typeString) ~ ")\n";
            }
            assert(false);
        }

        //Construct Node.Value from user defined type.
        static Value userValue(T)(T value)
        {
            return Value(cast(YAMLObject)new YAMLContainer!T(value));
        }

        //Return string representation of the type of the node.
        @property string typeString() const {return to!string(value_.type);}

    private:
        /*
         * Determine if the value stored by the node is of specified type.
         *
         * This only works for default YAML types, not for user defined types.
         */
        @property bool isType(T)() const {return value_.type is typeid(T);}

        ///Is the value an integer of some kind?
        alias isType!long isInt;

        ///Is the value a floating point number of some kind?
        alias isType!real isFloat;

        ///Does given node have the same type as this node?
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
