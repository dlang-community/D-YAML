
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * Implements a class that processes YAML mappings, sequences and scalars into
 * nodes. This can be used to implement custom data types. A tutorial can be 
 * found $(LINK2 ../tutorials/custom_types.html, here).
 */
module dyaml.constructor;


import std.array;
import std.algorithm;
import std.base64;
import std.container;
import std.conv;
import std.datetime;
import std.exception;
import std.stdio; 
import std.regex;
import std.string;
import std.utf;

import dyaml.node;
import dyaml.exception;
import dyaml.tag;
import dyaml.style;


/**
 * Exception thrown at constructor errors.
 *
 * Can be thrown by custom constructor functions.
 */
package class ConstructorException : YAMLException
{
    /**
     * Construct a ConstructorException.
     *
     * Params:  msg   = Error message.
     *          start = Start position of the error context.
     *          end   = End position of the error context.
     */
    this(string msg, Mark start, Mark end, string file = __FILE__, int line = __LINE__)
    {
        super(msg ~ "\nstart: " ~ start.toString() ~ "\nend: " ~ end.toString(),
              file, line);
    }
}

private alias ConstructorException Error;

/**
 * Constructs YAML values.
 *
 * Each YAML scalar, sequence or mapping has a tag specifying its data type.
 * Constructor uses user-specifyable functions to create a node of desired
 * data type from a scalar, sequence or mapping.
 *
 *
 * Each of these functions is associated with a tag, and can process either
 * a scalar, a sequence, or a mapping. The constructor passes each value to 
 * the function with corresponding tag, which then returns the resulting value
 * that can be stored in a node.
 *
 * If a tag is detected with no known constructor function, it is considered an error.
 */
final class Constructor
{
    private:
        ///Constructor functions from scalars.
        Node.Value delegate(ref Node)[Tag] fromScalar_;
        ///Constructor functions from sequences.
        Node.Value delegate(ref Node)[Tag] fromSequence_;
        ///Constructor functions from mappings.
        Node.Value delegate(ref Node)[Tag] fromMapping_;

    public:
        /**
         * Construct a Constructor.
         *
         * If you don't want to support default YAML tags/data types, you can use
         * defaultConstructors to disable constructor functions for these.
         *
         * Params:  defaultConstructors = Use constructors for default YAML tags?
         */
        this(in bool defaultConstructors = true)
        {
            if(!defaultConstructors){return;}

            addConstructorScalar("tag:yaml.org,2002:null",      &constructNull);
            addConstructorScalar("tag:yaml.org,2002:bool",      &constructBool);
            addConstructorScalar("tag:yaml.org,2002:int",       &constructLong);
            addConstructorScalar("tag:yaml.org,2002:float",     &constructReal);
            addConstructorScalar("tag:yaml.org,2002:binary",    &constructBinary);
            addConstructorScalar("tag:yaml.org,2002:timestamp", &constructTimestamp);
            addConstructorScalar("tag:yaml.org,2002:str",       &constructString);

            ///In a mapping, the default value is kept as an entry with the '=' key.
            addConstructorScalar("tag:yaml.org,2002:value",     &constructString);

            addConstructorSequence("tag:yaml.org,2002:omap",    &constructOrderedMap);
            addConstructorSequence("tag:yaml.org,2002:pairs",   &constructPairs);
            addConstructorMapping("tag:yaml.org,2002:set",      &constructSet);
            addConstructorSequence("tag:yaml.org,2002:seq",     &constructSequence);
            addConstructorMapping("tag:yaml.org,2002:map",      &constructMap);
            addConstructorScalar("tag:yaml.org,2002:merge",     &constructMerge);
        }

        ///Destroy the constructor.
        ~this()
        {
            clear(fromScalar_);
            fromScalar_ = null;
            clear(fromSequence_);
            fromSequence_ = null;
            clear(fromMapping_);
            fromMapping_ = null;
        }

        /**
         * Add a constructor function from scalar.
         *
         * The function must take a reference to $(D Node) to construct from.
         * The node contains a string for scalars, $(Node[]) for sequences and 
         * $(Node.Pair[]) for mappings. 
         *
         * Any exception thrown by this function will be caught by D:YAML and
         * its message will be added to a $(YAMLException) that will also tell 
         * the user which type failed to construct, and position in the file.
         *
         *
         * The value returned by this function will be stored in the resulting node.
         *
         * Only one constructor function can be set for one tag.
         *
         *
         * Structs and classes must implement the $(D opCmp()) operator for D:YAML 
         * support. The signature of the operator that must be implemented 
         * is $(D const int opCmp(ref const MyStruct s)) for structs where 
         * $(I MyStruct) is the struct type, and $(D int opCmp(Object o)) for 
         * classes. Note that the class $(D opCmp()) should not alter the compared
         * values - it is not const for compatibility reasons.
         *
         * Params:  tag  = Tag for the function to handle.
         *          ctor = Constructor function.
         *
         * Example:
         *
         * --------------------
         * import std.string;
         *
         * import yaml;
         *
         * struct MyStruct
         * {
         *     int x, y, z;
         *
         *     //Any D:YAML type must have a custom opCmp operator.
         *     //This is used for ordering in mappings.
         *     const int opCmp(ref const MyStruct s)
         *     {
         *         if(x != s.x){return x - s.x;}
         *         if(y != s.y){return y - s.y;}
         *         if(z != s.z){return z - s.z;}
         *         return 0;
         *     }        
         * }
         *
         * MyStruct constructMyStructScalar(ref Node node)
         * { 
         *     //Guaranteed to be string as we construct from scalar.
         *     //!mystruct x:y:z
         *     auto parts = node.as!string().split(":");
         *     //If this throws, the D:YAML will handle it and throw a YAMLException.
         *     return MyStruct(to!int(parts[0]), to!int(parts[1]), to!int(parts[2]));
         * }
         *
         * void main()
         * {
         *     auto loader = Loader("file.yaml");
         *     auto constructor = new Constructor;
         *     constructor.addConstructorScalar("!mystruct", &constructMyStructScalar);
         *     loader.constructor = constructor;
         *     Node node = loader.load();
         * }
         * --------------------
         */
        void addConstructorScalar(T)(in string tag, T function(ref Node) ctor)
        {
            const t = Tag(tag);
            auto deleg = addConstructor!T(t, ctor);
            (*delegates!string)[t] = deleg;
        }

        /**
         * Add a constructor function from sequence.
         *
         * See_Also:    addConstructorScalar
         * 
         * Example:
         *
         * --------------------
         * import std.string;
         *
         * import yaml;
         *
         * struct MyStruct
         * {
         *     int x, y, z;
         *
         *     //Any D:YAML type must have a custom opCmp operator.
         *     //This is used for ordering in mappings.
         *     const int opCmp(ref const MyStruct s)
         *     {
         *         if(x != s.x){return x - s.x;}
         *         if(y != s.y){return y - s.y;}
         *         if(z != s.z){return z - s.z;}
         *         return 0;
         *     }        
         * }
         *
         * MyStruct constructMyStructSequence(ref Node node)
         * { 
         *     //node is guaranteed to be sequence.
         *     //!mystruct [x, y, z]
         *     return MyStruct(node[0].as!int, node[1].as!int, node[2].as!int);
         * }
         *
         * void main()
         * {
         *     auto loader = Loader("file.yaml");
         *     auto constructor = new Constructor;
         *     constructor.addConstructorSequence("!mystruct", &constructMyStructSequence);
         *     loader.constructor = constructor;
         *     Node node = loader.load();
         * }
         * --------------------
         */
        void addConstructorSequence(T)(in string tag, T function(ref Node) ctor)
        {
            const t = Tag(tag);
            auto deleg = addConstructor!T(t, ctor);
            (*delegates!(Node[]))[t] = deleg;
        }

        /**
         * Add a constructor function from a mapping.
         *
         * See_Also:    addConstructorScalar
         * 
         * Example:
         *
         * --------------------
         * import std.string;
         *
         * import yaml;
         *
         * struct MyStruct
         * {
         *     int x, y, z;
         *
         *     //Any D:YAML type must have a custom opCmp operator.
         *     //This is used for ordering in mappings.
         *     const int opCmp(ref const MyStruct s)
         *     {
         *         if(x != s.x){return x - s.x;}
         *         if(y != s.y){return y - s.y;}
         *         if(z != s.z){return z - s.z;}
         *         return 0;
         *     }        
         * }
         *
         * MyStruct constructMyStructMapping(ref Node node)
         * { 
         *     //node is guaranteed to be mapping.
         *     //!mystruct {"x": x, "y": y, "z": z}
         *     return MyStruct(node["x"].as!int, node["y"].as!int, node["z"].as!int);
         * }
         *
         * void main()
         * {
         *     auto loader = Loader("file.yaml");
         *     auto constructor = new Constructor;
         *     constructor.addConstructorMapping("!mystruct", &constructMyStructMapping);
         *     loader.constructor = constructor;
         *     Node node = loader.load();
         * }
         * --------------------
         */
        void addConstructorMapping(T)(in string tag, T function(ref Node) ctor)
        {
            const t = Tag(tag);
            auto deleg = addConstructor!T(t, ctor);
            (*delegates!(Node.Pair[]))[t] = deleg;
        }

    package:
        /*
         * Construct a node.
         *
         * Params:  start = Start position of the node.
         *          end   = End position of the node.
         *          tag   = Tag (data type) of the node.
         *          value = Value to construct node from (string, nodes or pairs).
         *          style = Style of the node (scalar or collection style).
         *
         * Returns: Constructed node.
         */ 
        Node node(T, U)(in Mark start, in Mark end, in Tag tag, T value, U style) 
            if((is(T : string) || is(T == Node[]) || is(T == Node.Pair[])) &&
               (is(U : CollectionStyle) || is(U : ScalarStyle)))
        {
            static type = is(T : string)       ? "scalar"   :
                          is(T == Node[])      ? "sequence" :
                          is(T == Node.Pair[]) ? "mapping"  :
                                                 "ERROR";
            enforce((tag in *delegates!T) !is null,
                    new Error("No constructor function from " ~ type ~
                              " for tag " ~ tag.get(), start, end));
            Node node = Node(value);
            try
            {
                static if(is(U : ScalarStyle))
                {
                    return Node.rawNode((*delegates!T)[tag](node), start, tag,
                                        style, CollectionStyle.Invalid);
                }
                else static if(is(U : CollectionStyle))
                {
                    return Node.rawNode((*delegates!T)[tag](node), start, tag,
                                        ScalarStyle.Invalid, style);
                }
                else static assert(false);
            }
            catch(Exception e)
            {
                throw new Error("Error constructing " ~ typeid(T).toString() 
                                ~ ":\n" ~ e.msg, start, end);
            }
        }

    private:
        /* 
         * Add a constructor function.
         *
         * Params:  tag  = Tag for the function to handle.
         *          ctor = Constructor function.
         */
        auto addConstructor(T)(in Tag tag, T function(ref Node) ctor)
        {
            assert((tag in fromScalar_) is null && 
                   (tag in fromSequence_) is null &&
                   (tag in fromMapping_) is null,
                   "Constructor function for tag " ~ tag.get ~ " is already "
                   "specified. Can't specify another one.");

            return (ref Node n)
            {
                static if(Node.Value.allowed!T){return Node.Value(ctor(n));}
                else                           {return Node.userValue(ctor(n));}
            }; 
        }

        //Get the array of constructor functions for scalar, sequence or mapping.
        auto delegates(T)() 
        {
            static if(is(T : string))          {return &fromScalar_;}
            else static if(is(T : Node[]))     {return &fromSequence_;}
            else static if(is(T : Node.Pair[])){return &fromMapping_;}
            else static assert(false);
        }
}


///Construct a _null _node.
YAMLNull constructNull(ref Node node)
{
    return YAMLNull();
}

///Construct a merge _node - a _node that merges another _node into a mapping.
YAMLMerge constructMerge(ref Node node)
{
    return YAMLMerge();
}

///Construct a boolean _node.
bool constructBool(ref Node node)
{
    static yes = ["yes", "true", "on"];
    static no = ["no", "false", "off"];
    string value = node.as!string().toLower();
    if(yes.canFind(value)){return true;}
    if(no.canFind(value)) {return false;}
    throw new Exception("Unable to parse boolean value: " ~ value);
}

///Construct an integer (long) _node.
long constructLong(ref Node node)
{
    string value = node.as!string().replace("_", "");
    const char c = value[0];
    const long sign = c != '-' ? 1 : -1;
    if(c == '-' || c == '+')
    {
        value = value[1 .. $];
    }

    enforce(value != "", new Exception("Unable to parse float value: " ~ value));

    long result;
    try
    {
        //Zero.
        if(value == "0")               {result = cast(long)0;}
        //Binary.
        else if(value.startsWith("0b")){result = sign * parse!int(value[2 .. $], 2);}
        //Hexadecimal.
        else if(value.startsWith("0x")){result = sign * parse!int(value[2 .. $], 16);}
        //Octal.
        else if(value[0] == '0')       {result = sign * parse!int(value, 8);}
        //Sexagesimal.
        else if(value.canFind(":"))
        {
            long val = 0;
            long base = 1;
            foreach_reverse(digit; value.split(":"))
            {
                val += to!long(digit) * base;
                base *= 60;
            }
            result = sign * val;
        }
        //Decimal.
        else{result = sign * to!long(value);}
    }
    catch(ConvException e)
    {
        throw new Exception("Unable to parse integer value: " ~ value);
    }

    return result;
}
unittest
{
    long getLong(string str)
    {
        return constructLong(Node(str));
    }

    string canonical   = "685230";
    string decimal     = "+685_230";
    string octal       = "02472256";
    string hexadecimal = "0x_0A_74_AE";
    string binary      = "0b1010_0111_0100_1010_1110";
    string sexagesimal = "190:20:30";

    assert(685230 == getLong(canonical));
    assert(685230 == getLong(decimal));
    assert(685230 == getLong(octal));
    assert(685230 == getLong(hexadecimal));
    assert(685230 == getLong(binary));
    assert(685230 == getLong(sexagesimal));
}

///Construct a floating point (real) _node.
real constructReal(ref Node node)
{
    string value = node.as!string().replace("_", "").toLower();
    const char c = value[0];
    const real sign = c != '-' ? 1.0 : -1.0;
    if(c == '-' || c == '+')
    {
        value = value[1 .. $];
    }

    enforce(value != "" && value != "nan" && value != "inf" && value != "-inf",
            new Exception("Unable to parse float value: " ~ value));

    real result;
    try
    {
        //Infinity.
        if     (value == ".inf"){result = sign * real.infinity;}
        //Not a Number.
        else if(value == ".nan"){result = real.nan;}
        //Sexagesimal.
        else if(value.canFind(":"))
        {
            real val = 0.0;
            real base = 1.0;
            foreach_reverse(digit; value.split(":"))
            {
                val += to!real(digit) * base;
                base *= 60.0;
            }
            result = sign * val;
        }
        //Plain floating point.
        else{result = sign * to!real(value);}
    }
    catch(ConvException e)
    {
        throw new Exception("Unable to parse float value: " ~ value);
    }

    return result;
}
unittest
{
    bool eq(real a, real b, real epsilon = 0.2)
    {
        return a >= (b - epsilon) && a <= (b + epsilon);
    }

    real getReal(string str)
    {
        return constructReal(Node(str));
    }

    string canonical   = "6.8523015e+5";
    string exponential = "685.230_15e+03";
    string fixed       = "685_230.15";
    string sexagesimal = "190:20:30.15";
    string negativeInf = "-.inf";
    string NaN         = ".NaN";

    assert(eq(685230.15, getReal(canonical)));
    assert(eq(685230.15, getReal(exponential)));
    assert(eq(685230.15, getReal(fixed)));
    assert(eq(685230.15, getReal(sexagesimal)));
    assert(eq(-real.infinity, getReal(negativeInf)));
    assert(to!string(getReal(NaN)) == "nan");
}

///Construct a binary (base64) _node.
ubyte[] constructBinary(ref Node node)
{
    string value = node.as!string;
    //For an unknown reason, this must be nested to work (compiler bug?).
    try
    {
        try{return Base64.decode(value.removechars("\n"));}
        catch(Exception e)
        {
            throw new Exception("Unable to decode base64 value: " ~ e.msg);
        }
    }
    catch(UTFException e)
    {
        throw new Exception("Unable to decode base64 value: " ~ e.msg);
    }
}
unittest
{
    ubyte[] test = cast(ubyte[])"The Answer: 42";
    char[] buffer;
    buffer.length = 256;
    string input = cast(string)Base64.encode(test, buffer);
    auto value = constructBinary(Node(input));
    assert(value == test);
}

///Construct a timestamp (SysTime) _node.
SysTime constructTimestamp(ref Node node)
{
    string value = node.as!string;

    auto YMDRegexp = regex("^([0-9][0-9][0-9][0-9])-([0-9][0-9]?)-([0-9][0-9]?)");
    auto HMSRegexp = regex("^[Tt \t]+([0-9][0-9]?):([0-9][0-9]):([0-9][0-9])(\\.[0-9]*)?");
    auto TZRegexp  = regex("^[ \t]*Z|([-+][0-9][0-9]?)(:[0-9][0-9])?");

    try
    {
        //First, get year, month and day.
        auto matches = match(value, YMDRegexp);

        enforce(!matches.empty, 
                new Exception("Unable to parse timestamp value: " ~ value));

        auto captures = matches.front.captures;
        const year  = to!int(captures[1]);
        const month = to!int(captures[2]);
        const day   = to!int(captures[3]);

        //If available, get hour, minute, second and fraction, if present.
        value = matches.front.post;
        matches  = match(value, HMSRegexp);
        if(matches.empty)
        {
            return SysTime(DateTime(year, month, day), UTC());
        }

        captures = matches.front.captures;
        const hour            = to!int(captures[1]);
        const minute          = to!int(captures[2]);
        const second          = to!int(captures[3]);
        const hectonanosecond = cast(int)(to!real("0" ~ captures[4]) * 10000000);

        //If available, get timezone.
        value = matches.front.post;
        matches = match(value, TZRegexp);
        if(matches.empty || matches.front.captures[0] == "Z")
        {                                                 
            return SysTime(DateTime(year, month, day, hour, minute, second),
                           FracSec.from!"hnsecs"(hectonanosecond), UTC());
        }

        captures = matches.front.captures;
        int sign    = 1;
        int tzHours = 0;
        if(!captures[1].empty)
        {
            if(captures[1][0] == '-'){sign = -1;}
            tzHours   = to!int(captures[1][1 .. $]);
        }
        const tzMinutes = (!captures[2].empty) ? to!int(captures[2][1 .. $]) : 0;
        const tzOffset = sign * (60 * tzHours + tzMinutes);

        return SysTime(DateTime(year, month, day, hour, minute, second),
                       FracSec.from!"hnsecs"(hectonanosecond), 
                       new SimpleTimeZone(tzOffset));
    }
    catch(ConvException e)
    {
        throw new Exception("Unable to parse timestamp value " ~ value ~ " : " ~ e.msg);
    }
    catch(DateTimeException e)
    {
        throw new Exception("Invalid timestamp value " ~ value ~ " : " ~ e.msg);
    }

    assert(false, "This code should never be reached");
}
unittest
{
    writeln("D:YAML construction timestamp unittest");

    string timestamp(string value)
    {
        return constructTimestamp(Node(value)).toISOString();
    }

    string canonical      = "2001-12-15T02:59:43.1Z";
    string iso8601        = "2001-12-14t21:59:43.10-05:00";
    string spaceSeparated = "2001-12-14 21:59:43.10 -5";
    string noTZ           = "2001-12-15 2:59:43.10";
    string noFraction     = "2001-12-15 2:59:43";
    string ymd            = "2002-12-14";

    assert(timestamp(canonical)      == "20011215T025943.1Z");
    //avoiding float conversion errors
    assert(timestamp(iso8601)        == "20011214T215943.0999999-05:00" ||
           timestamp(iso8601)        == "20011214T215943.1-05:00");
    assert(timestamp(spaceSeparated) == "20011214T215943.0999999-05:00" ||
           timestamp(spaceSeparated) == "20011214T215943.1-05:00");
    assert(timestamp(noTZ)           == "20011215T025943.0999999Z" ||
           timestamp(noTZ)           == "20011215T025943.1Z");
    assert(timestamp(noFraction)     == "20011215T025943Z");
    assert(timestamp(ymd)            == "20021214T000000Z");
}

///Construct a string _node.
string constructString(ref Node node)
{
    return node.as!string;
}

///Convert a sequence of single-element mappings into a sequence of pairs.
Node.Pair[] getPairs(string type, Node[] nodes) 
{
    Node.Pair[] pairs;

    foreach(ref node; nodes)
    {
        enforce(node.isMapping && node.length == 1,
                new Exception("While constructing " ~ type ~ 
                          ", expected a mapping with single element"));

        pairs ~= node.as!(Node.Pair[]);
    }

    return pairs;
}

///Construct an ordered map (ordered sequence of key:value pairs without duplicates) _node.
Node.Pair[] constructOrderedMap(ref Node node)
{
    auto pairs = getPairs("ordered map", node.as!(Node[]));

    //Detect duplicates. 
    //TODO this should be replaced by something with deterministic memory allocation.
    auto keys = redBlackTree!Node();
    scope(exit){clear(keys);}
    foreach(ref pair; pairs)
    {
        enforce(!(pair.key in keys),
                new Exception("Duplicate entry in an ordered map: " 
                              ~ pair.key.debugString()));
        keys.insert(pair.key);
    }
    return pairs;
}
unittest
{
    writeln("D:YAML construction ordered map unittest");

    alias Node.Pair Pair;

    Node[] alternateTypes(uint length)
    {
        Node[] pairs;
        foreach(long i; 0 .. length)
        {
            auto pair = (i % 2) ? Pair(to!string(i), i)
                                : Pair(i, to!string(i));
            pairs ~= Node([pair]);
        }
        return pairs;
    }

    Node[] sameType(uint length)
    {
        Node[] pairs;
        foreach(long i; 0 .. length)
        {
            auto pair = Pair(to!string(i), i);
            pairs ~= Node([pair]);
        }
        return pairs;
    }

    bool hasDuplicates(Node[] nodes)
    {
        return null !is collectException(constructOrderedMap(Node(nodes)));
    }

    assert(hasDuplicates(alternateTypes(8) ~ alternateTypes(2)));
    assert(!hasDuplicates(alternateTypes(8)));
    assert(hasDuplicates(sameType(64) ~ sameType(16)));
    assert(hasDuplicates(alternateTypes(64) ~ alternateTypes(16)));
    assert(!hasDuplicates(sameType(64)));
    assert(!hasDuplicates(alternateTypes(64)));
}

///Construct a pairs (ordered sequence of key: value pairs allowing duplicates) _node.
Node.Pair[] constructPairs(ref Node node)
{
    return getPairs("pairs", node.as!(Node[]));
}

///Construct a set _node.
Node[] constructSet(ref Node node)
{
    auto pairs = node.as!(Node.Pair[]);

    //In future, the map here should be replaced with something with deterministic
    //memory allocation if possible.
    //Detect duplicates.
    ubyte[Node] map;
    scope(exit){clear(map);}
    Node[] nodes;
    foreach(ref pair; pairs)
    {
        enforce((pair.key in map) is null,
                new Exception("Duplicate entry in a set"));
        map[pair.key] = 0;
        nodes ~= pair.key;
    }

    return nodes;
}
unittest
{
    writeln("D:YAML construction set unittest");

    Node.Pair[] set(uint length)
    {
        Node.Pair[] pairs;
        foreach(long i; 0 .. length)
        {
            pairs ~= Node.Pair(to!string(i), YAMLNull());
        }

        return pairs;
    }

    auto DuplicatesShort   = set(8) ~ set(2);
    auto noDuplicatesShort = set(8);
    auto DuplicatesLong    = set(64) ~ set(4);
    auto noDuplicatesLong  = set(64);

    bool eq(Node.Pair[] a, Node[] b)
    {
        if(a.length != b.length){return false;}
        foreach(i; 0 .. a.length)
        {
            if(a[i].key != b[i])
            {
                return false;
            }
        }
        return true;
    }

    assert(null !is collectException
           (constructSet(Node(DuplicatesShort.dup))));
    assert(null is collectException
           (constructSet(Node(noDuplicatesShort.dup))));
    assert(null !is collectException
           (constructSet(Node(DuplicatesLong.dup))));
    assert(null is collectException
           (constructSet(Node(noDuplicatesLong.dup))));
}

///Construct a sequence (array) _node.
Node[] constructSequence(ref Node node)
{
    return node.as!(Node[]);
}

///Construct an unordered map (unordered set of key:value _pairs without duplicates) _node.
Node.Pair[] constructMap(ref Node node)
{
    auto pairs = node.as!(Node.Pair[]);
    //Detect duplicates. 
    //TODO this should be replaced by something with deterministic memory allocation.
    auto keys = redBlackTree!Node();
    scope(exit){clear(keys);}
    foreach(ref pair; pairs)
    {
        enforce(!(pair.key in keys),
                new Exception("Duplicate entry in a map: " 
                              ~ pair.key.debugString()));
        keys.insert(pair.key);
    }
    return pairs;
}


//Unittests
private:

import std.stream;
import dyaml.loader;

struct MyStruct
{
    int x, y, z;

    const int opCmp(ref const MyStruct s)
    {
        if(x != s.x){return x - s.x;}
        if(y != s.y){return y - s.y;}
        if(z != s.z){return z - s.z;}
        return 0;
    }        
}

MyStruct constructMyStructScalar(ref Node node)
{ 
    //Guaranteed to be string as we construct from scalar.
    auto parts = node.as!string().split(":");
    return MyStruct(to!int(parts[0]), to!int(parts[1]), to!int(parts[2]));
}

MyStruct constructMyStructSequence(ref Node node)
{ 
    //node is guaranteed to be sequence.
    return MyStruct(node[0].as!int, node[1].as!int, node[2].as!int);
}

MyStruct constructMyStructMapping(ref Node node)
{ 
    //node is guaranteed to be mapping.
    return MyStruct(node["x"].as!int, node["y"].as!int, node["z"].as!int);
}

unittest
{
    char[] data = cast(char[])"!mystruct 1:2:3";
    auto loadStream  = new MemoryStream(data);
    auto loader = Loader(loadStream);
    auto constructor = new Constructor;
    constructor.addConstructorScalar("!mystruct", &constructMyStructScalar);
    loader.constructor = constructor;
    Node node = loader.load();

    assert(node.as!MyStruct == MyStruct(1, 2, 3));
}

unittest
{
    char[] data = cast(char[])"!mystruct [1, 2, 3]";
    auto loadStream  = new MemoryStream(data);
    auto loader = Loader(loadStream);
    auto constructor = new Constructor;
    constructor.addConstructorSequence("!mystruct", &constructMyStructSequence);
    loader.constructor = constructor;
    Node node = loader.load();

    assert(node.as!MyStruct == MyStruct(1, 2, 3));
}

unittest
{
    char[] data = cast(char[])"!mystruct {x: 1, y: 2, z: 3}";
    auto loadStream  = new MemoryStream(data);
    auto loader = Loader(loadStream);
    auto constructor = new Constructor;
    constructor.addConstructorMapping("!mystruct", &constructMyStructMapping);
    loader.constructor = constructor;
    Node node = loader.load();

    assert(node.as!MyStruct == MyStruct(1, 2, 3));
}
