
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
import dyaml.token;


/**
 * Exception thrown at constructor errors.
 *
 * Can be thrown by custom constructor functions.
 */
class ConstructorException : YAMLException
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
        super(msg ~ "\nstart:" ~ start.toString() ~ "\nend:" ~ end.toString(),
              file, line);
    }
}

/**
 * Constructs YAML values.
 *
 * Each YAML scalar, sequence or mapping has a tag specifying its data type.
 * Constructor uses user-specifyable functions to create a node of desired
 * data type from a scalar, sequence or mapping.
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
        Node.Value delegate(Mark, Mark, ref Node)[Tag] fromScalar_;
        ///Constructor functions from sequences.
        Node.Value delegate(Mark, Mark, ref Node)[Tag] fromSequence_;
        ///Constructor functions from mappings.
        Node.Value delegate(Mark, Mark, ref Node)[Tag] fromMapping_;

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
         * The function must take two Marks (start and end positions of
         * the node in file) and a reference to Node to construct from.
         * The node contains a string for scalars, Node[] for sequences and 
         * Node.Pair[] for mappings.
         * The value returned by this function will be stored in the resulting node.
         *
         * Only one constructor function can be set for one tag.
         *
         * Params:  tag  = Tag for the function to handle.
         *          ctor = Constructor function.
         */
        void addConstructorScalar(T)(in string tag, T function(Mark, Mark, ref Node) ctor)
        {
            const t = Tag(tag);
            auto deleg = addConstructor!T(t, ctor);
            (*delegates!string)[t] = deleg;
        }

        /**
         * Add a constructor function from sequence.
         *
         * See_Also:    addConstructorScalar
         */
        void addConstructorSequence(T)(in string tag, T function(Mark, Mark, ref Node) ctor)
        {
            const t = Tag(tag);
            auto deleg = addConstructor!T(t, ctor);
            (*delegates!(Node[]))[t] = deleg;
        }

        /**
         * Add a constructor function from a mapping.
         *
         * See_Also:    addConstructorScalar
         */
        void addConstructorMapping(T)(in string tag, T function(Mark, Mark, ref Node) ctor)
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
         *
         * Returns: Constructed node.
         */ 
        Node node(T)(in Mark start, in Mark end, in Tag tag, T value) 
            if(is(T : string) || is(T == Node[]) || is(T == Node.Pair[]))
        {
            enforce((tag in *delegates!T) !is null,
                    new ConstructorException("Could not determine a constructor for tag " 
                                             ~ tag.get(), start, end));
            Node node = Node(value);
            return Node.rawNode((*delegates!T)[tag](start, end, node), start, tag);
        }

    private:
        /* 
         * Add a constructor function.
         *
         * Params:  tag  = Tag for the function to handle.
         *          ctor = Constructor function.
         */
        auto addConstructor(T)(in Tag tag, T function(Mark, Mark, ref Node) ctor)
        {
            assert((tag in fromScalar_) is null && 
                   (tag in fromSequence_) is null &&
                   (tag in fromMapping_) is null,
                   "Constructor function for tag " ~ tag.get ~ " is already "
                   "specified. Can't specify another one.");

            return (Mark s, Mark e, ref Node n)
            {
                static if(Node.Value.allowed!T){return Node.Value(ctor(s,e,n));}
                else                           {return Node.userValue(ctor(s,e,n));}
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


///Construct a null node.
YAMLNull constructNull(Mark start, Mark end, ref Node node)
{
    return YAMLNull();
}

///Construct a merge node - a node that merges another node into a mapping.
YAMLMerge constructMerge(Mark start, Mark end, ref Node node)
{
    return YAMLMerge();
}

///Construct a boolean node.
bool constructBool(Mark start, Mark end, ref Node node)
{
    string value = node.get!string().toLower();
    if(["yes", "true", "on"].canFind(value)) {return true;}
    if(["no", "false", "off"].canFind(value)){return false;}
    throw new ConstructorException("Unable to parse boolean value: " ~ value, start, end);
}

///Construct an integer (long) node.
long constructLong(Mark start, Mark end, ref Node node)
{
    string value = node.get!string().replace("_", "");
    const char c = value[0];
    const long sign = c != '-' ? 1 : -1;
    if(c == '-' || c == '+')
    {
        value = value[1 .. $];
    }

    enforce(value != "", new ConstructorException("Unable to parse float value: " ~ value,
                                                  start, end));

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
        throw new ConstructorException("Unable to parse integer value: " ~ value, start, end);
    }

    return result;
}
unittest
{
    long getLong(string str)
    {
        return constructLong(Mark(), Mark(), Node(str));
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

///Construct a floating point (real) node.
real constructReal(Mark start, Mark end, ref Node node)
{
    string value = node.get!string().replace("_", "").toLower();
    const char c = value[0];
    const real sign = c != '-' ? 1.0 : -1.0;
    if(c == '-' || c == '+')
    {
        value = value[1 .. $];
    }

    enforce(value != "" && value != "nan" && value != "inf" && value != "-inf",
            new ConstructorException("Unable to parse float value: " ~ value, start, end));

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
        throw new ConstructorException("Unable to parse float value: " ~ value, start, end);
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
        return constructReal(Mark(), Mark(), Node(str));
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

///Construct a binary (base64) node.
ubyte[] constructBinary(Mark start, Mark end, ref Node node)
{
    string value = node.get!string;
    //For an unknown reason, this must be nested to work (compiler bug?).
    try
    {
        try{return Base64.decode(value.removechars("\n"));}
        catch(Exception e)
        {
            throw new ConstructorException("Unable to decode base64 value: " ~ e.msg, start, 
                                           end);
        }
    }
    catch(UtfException e)
    {
        throw new ConstructorException("Unable to decode base64 value: " ~ e.msg, start, end);
    }
}
unittest
{
    ubyte[] test = cast(ubyte[])"The Answer: 42";
    char[] buffer;
    buffer.length = 256;
    string input = cast(string)Base64.encode(test, buffer);
    auto value = constructBinary(Mark(), Mark(), Node(input));
    assert(value == test);
}

///Construct a timestamp (SysTime) node.
SysTime constructTimestamp(Mark start, Mark end, ref Node node)
{
    string value = node.get!string;

    immutable YMDRegexp = regex("^([0-9][0-9][0-9][0-9])-([0-9][0-9]?)-([0-9][0-9]?)");
    immutable HMSRegexp = regex("^[Tt \t]+([0-9][0-9]?):([0-9][0-9]):([0-9][0-9])(\\.[0-9]*)?");
    immutable TZRegexp  = regex("^[ \t]*Z|([-+][0-9][0-9]?)(:[0-9][0-9])?");

    try
    {
        //First, get year, month and day.
        auto matches = match(value, YMDRegexp);

        enforce(!matches.empty, new ConstructorException("Unable to parse timestamp value: " 
                                                         ~ value, start, end));

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
        throw new ConstructorException("Unable to parse timestamp value: " ~ value ~ 
                                       " Reason: " ~ e.msg, start, end);
    }
    catch(DateTimeException e)
    {
        throw new ConstructorException("Invalid timestamp value: " ~ value ~ 
                                       " Reason: " ~ e.msg, start, end);
    }

    assert(false, "This code should never be reached");
}
unittest
{
    writeln("D:YAML construction timestamp unittest");

    string timestamp(string value)
    {
        return constructTimestamp(Mark(), Mark(), Node(value)).toISOString();
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

///Construct a string node.
string constructString(Mark start, Mark end, ref Node node)
{
    return node.get!string;
}

///Convert a sequence of single-element mappings into a sequence of pairs.
Node.Pair[] getPairs(string type, Mark start, Mark end, Node[] nodes) 
{
    Node.Pair[] pairs;

    foreach(ref node; nodes)
    {
        enforce(node.isMapping && node.length == 1,
                new ConstructorException("While constructing " ~ type ~ 
                                         ", expected a mapping with single element,", start,
                                         end));

        pairs ~= node.get!(Node.Pair[]);
    }

    return pairs;
}

///Construct an ordered map (ordered sequence of key:value pairs without duplicates) node.
Node.Pair[] constructOrderedMap(Mark start, Mark end, ref Node node)
{
    auto pairs = getPairs("ordered map", start, end, node.get!(Node[]));

    //TODO: the map here should be replaced with something with deterministic
    //memory allocation if possible.
    //Detect duplicates.
    bool[Node] map;
    foreach(ref pair; pairs)
    {
        enforce((pair.key in map) is null,
                new ConstructorException("Found a duplicate entry in an ordered map", 
                                         start, end));
        map[pair.key] = true;
    }
    clear(map);
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
            auto pair = (i % 2) ? Pair(Node.rawNode(Node.Value(to!string(i))), Node.rawNode(Node.Value(i)))
                                : Pair(Node.rawNode(Node.Value(i)), Node.rawNode(Node.Value(to!string(i))));
            pairs ~= Node.rawNode(Node.Value([pair]));
        }
        return pairs;
    }

    Node[] sameType(uint length)
    {
        Node[] pairs;
        foreach(long i; 0 .. length)
        {
            auto pair = Pair(Node.rawNode(Node.Value(to!string(i))), Node.rawNode(Node.Value(i)));
            pairs ~= Node.rawNode(Node.Value([pair]));
        }
        return pairs;
    }

    bool hasDuplicates(Node[] nodes)
    {
        return null !is collectException(constructOrderedMap(Mark(), Mark(), Node(nodes)));
    }

    assert(hasDuplicates(alternateTypes(8) ~ alternateTypes(2)));
    assert(!hasDuplicates(alternateTypes(8)));
    assert(hasDuplicates(sameType(64) ~ sameType(16)));
    assert(hasDuplicates(alternateTypes(64) ~ alternateTypes(16)));
    assert(!hasDuplicates(sameType(64)));
    assert(!hasDuplicates(alternateTypes(64)));
}

///Construct a pairs (ordered sequence of key: value pairs allowing duplicates) node.
Node.Pair[] constructPairs(Mark start, Mark end, ref Node node)
{
    return getPairs("pairs", start, end, node.get!(Node[]));
}

///Construct a set node.
Node[] constructSet(Mark start, Mark end, ref Node node)
{
    auto pairs = node.get!(Node.Pair[]);

    //In future, the map here should be replaced with something with deterministic
    //memory allocation if possible.
    //Detect duplicates.
    ubyte[Node] map;
    scope(exit){clear(map);}
    Node[] nodes;
    foreach(ref pair; pairs)
    {
        enforce((pair.key in map) is null,
                new ConstructorException("Found a duplicate entry in a set", start, end));
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
            pairs ~= Node.Pair(Node.rawNode(Node.Value(to!string(i))), Node.rawNode(Node.Value(YAMLNull())));
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
           (constructSet(Mark(), Mark(), Node(DuplicatesShort.dup))));
    assert(null is collectException
           (constructSet(Mark(), Mark(), Node(noDuplicatesShort.dup))));
    assert(null !is collectException
           (constructSet(Mark(), Mark(), Node(DuplicatesLong.dup))));
    assert(null is collectException
           (constructSet(Mark(), Mark(), Node(noDuplicatesLong.dup))));
}

///Construct a sequence (array) node.
Node[] constructSequence(Mark start, Mark end, ref Node node)
{
    return node.get!(Node[]);
}

///Construct an unordered map (unordered set of key: value _pairs without duplicates) node.
Node.Pair[] constructMap(Mark start, Mark end, ref Node node)
{
    auto pairs = node.get!(Node.Pair[]);
    //TODO: the map here should be replaced with something with deterministic
    //memory allocation if possible.
    //Detect duplicates.
    bool[Node] map;
    scope(exit){clear(map);}
    foreach(ref pair; pairs)
    {
        enforce((pair.key in map) is null,
                new ConstructorException("Found a duplicate entry in a map", start, end));
        map[pair.key] = true;
    }
    return pairs;
}
