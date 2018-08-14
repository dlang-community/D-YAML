
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * Class that processes YAML mappings, sequences and scalars into nodes.
 * This can be used to add custom data types. A tutorial can be found
 * $(LINK2 https://dlang-community.github.io/D-YAML/, here).
 */
module dyaml.constructor;


import std.array;
import std.algorithm;
import std.base64;
import std.container;
import std.conv;
import std.datetime;
import std.exception;
import std.regex;
import std.string;
import std.typecons;
import std.utf;

import dyaml.node;
import dyaml.exception;
import dyaml.style;


// Exception thrown at constructor errors.
package class ConstructorException : YAMLException
{
    /// Construct a ConstructorException.
    ///
    /// Params:  msg   = Error message.
    ///          start = Start position of the error context.
    ///          end   = End position of the error context.
    this(string msg, Mark start, Mark end, string file = __FILE__, int line = __LINE__)
        @safe pure nothrow
    {
        super(msg ~ "\nstart: " ~ start.toString() ~ "\nend: " ~ end.toString(),
              file, line);
    }
}

/** Constructs YAML values.
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
        // Constructor functions from scalars.
        Node delegate(ref Node) @safe[string] fromScalar_;
        // Constructor functions from sequences.
        Node delegate(ref Node) @safe[string] fromSequence_;
        // Constructor functions from mappings.
        Node delegate(ref Node) @safe[string] fromMapping_;

    public:
        /// Construct a Constructor.
        ///
        /// If you don't want to support default YAML tags/data types, you can use
        /// defaultConstructors to disable constructor functions for these.
        ///
        /// Params:  defaultConstructors = Use constructors for default YAML tags?
        this(const Flag!"useDefaultConstructors" defaultConstructors = Yes.useDefaultConstructors)
            @safe nothrow
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

        /** Add a constructor function from scalar.
         *
         * The function must take a reference to $(D Node) to construct from.
         * The node contains a string for scalars, $(D Node[]) for sequences and
         * $(D Node.Pair[]) for mappings.
         *
         * Any exception thrown by this function will be caught by D:YAML and
         * its message will be added to a $(D YAMLException) that will also tell
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
         */
        void addConstructorScalar(T)(const string tag, T function(ref Node) @safe ctor)
        {
            const t = tag;
            const deleg = addConstructor!T(t, ctor);
            (*delegates!string)[t] = deleg;
        }
        ///
        @safe unittest
        {
            static struct MyStruct
            {
                int x, y, z;

                //Any D:YAML type must have a custom opCmp operator.
                //This is used for ordering in mappings.
                int opCmp(ref const MyStruct s) const
                {
                    if(x != s.x){return x - s.x;}
                    if(y != s.y){return y - s.y;}
                    if(z != s.z){return z - s.z;}
                    return 0;
                }
            }

            static MyStruct constructMyStructScalar(ref Node node) @safe
            {
                //Guaranteed to be string as we construct from scalar.
                //!mystruct x:y:z
                auto parts = node.as!string().split(":");
                // If this throws, the D:YAML will handle it and throw a YAMLException.
                return MyStruct(to!int(parts[0]), to!int(parts[1]), to!int(parts[2]));
            }

            import dyaml.loader : Loader;
            auto loader = Loader.fromString("!mystruct 12:34:56");
            auto constructor = new Constructor;
            constructor.addConstructorScalar("!mystruct", &constructMyStructScalar);
            loader.constructor = constructor;
            Node node = loader.load();
            assert(node.get!MyStruct == MyStruct(12, 34, 56));
        }

        /** Add a constructor function from sequence.
         *
         * See_Also:    addConstructorScalar
         */
        void addConstructorSequence(T)(const string tag, T function(ref Node) @safe ctor)
        {
            const t = tag;
            const deleg = addConstructor!T(t, ctor);
            (*delegates!(Node[]))[t] = deleg;
        }
        ///
        @safe unittest
        {
            static struct MyStruct
            {
                int x, y, z;

                //Any D:YAML type must have a custom opCmp operator.
                //This is used for ordering in mappings.
                int opCmp(ref const MyStruct s) const
                {
                    if(x != s.x){return x - s.x;}
                    if(y != s.y){return y - s.y;}
                    if(z != s.z){return z - s.z;}
                    return 0;
                }
            }

            static MyStruct constructMyStructSequence(ref Node node) @safe
            {
                //node is guaranteed to be sequence.
                //!mystruct [x, y, z]
                return MyStruct(node[0].as!int, node[1].as!int, node[2].as!int);
            }

            import dyaml.loader : Loader;
            auto loader = Loader.fromString("!mystruct [1,2,3]");
            auto constructor = new Constructor;
            constructor.addConstructorSequence("!mystruct", &constructMyStructSequence);
            loader.constructor = constructor;
            Node node = loader.load();
            assert(node.get!MyStruct == MyStruct(1, 2, 3));
         }

        /** Add a constructor function from a mapping.
         *
         * See_Also:    addConstructorScalar
         */
        void addConstructorMapping(T)(const string tag, T function(ref Node) @safe ctor)
        {
            const t = tag;
            const deleg = addConstructor!T(t, ctor);
            (*delegates!(Node.Pair[]))[t] = deleg;
        }
        ///
        @safe unittest {
            static struct MyStruct
            {
                int x, y, z;

                //Any D:YAML type must have a custom opCmp operator.
                //This is used for ordering in mappings.
                int opCmp(ref const MyStruct s) const
                {
                    if(x != s.x){return x - s.x;}
                    if(y != s.y){return y - s.y;}
                    if(z != s.z){return z - s.z;}
                    return 0;
                }
            }

            static MyStruct constructMyStructMapping(ref Node node) @safe
            {
                //node is guaranteed to be mapping.
                //!mystruct {"x": x, "y": y, "z": z}
                return MyStruct(node["x"].as!int, node["y"].as!int, node["z"].as!int);
            }

            import dyaml.loader : Loader;
            auto loader = Loader.fromString(`!mystruct {"x": 11, "y": 22, "z": 33}`);
            auto constructor = new Constructor;
            constructor.addConstructorMapping("!mystruct", &constructMyStructMapping);
            loader.constructor = constructor;
            Node node = loader.load();
            assert(node.get!MyStruct == MyStruct(11, 22, 33));
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
        Node node(T, U)(const Mark start, const Mark end, const string tag,
                        T value, U style) @safe
            if((is(T : string) || is(T == Node[]) || is(T == Node.Pair[])) &&
               (is(U : CollectionStyle) || is(U : ScalarStyle)))
        {
            enum type = is(T : string)       ? "scalar"   :
                        is(T == Node[])      ? "sequence" :
                        is(T == Node.Pair[]) ? "mapping"  :
                                               "ERROR";
            enforce((tag in *delegates!T) !is null,
                    new ConstructorException("No constructor function from " ~ type ~
                              " for tag " ~ tag, start, end));

            Node node = Node(value);
            try
            {
                static if(is(U : ScalarStyle))
                {
                    auto newNode = (*delegates!T)[tag](node);
                    newNode.startMark_ = start;
                    newNode.scalarStyle = style;
                    return newNode;
                }
                else static if(is(U : CollectionStyle))
                {
                    auto newNode = (*delegates!T)[tag](node);
                    newNode.startMark_ = start;
                    newNode.collectionStyle = style;
                    return newNode;
                }
                else static assert(false);
            }
            catch(Exception e)
            {
                throw new ConstructorException("Error constructing " ~ typeid(T).toString()
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
        auto addConstructor(T)(const string tag, T function(ref Node) @safe ctor)
        {
            assert((tag in fromScalar_) is null &&
                   (tag in fromSequence_) is null &&
                   (tag in fromMapping_) is null,
                   "Constructor function for tag " ~ tag ~ " is already " ~
                   "specified. Can't specify another one.");


            return (ref Node n) @safe
            {
                return Node(ctor(n), tag);
            };
        }

        //Get the array of constructor functions for scalar, sequence or mapping.
        @property auto delegates(T)()
        {
            static if(is(T : string))          {return &fromScalar_;}
            else static if(is(T : Node[]))     {return &fromSequence_;}
            else static if(is(T : Node.Pair[])){return &fromMapping_;}
            else static assert(false);
        }
}

///Construct a struct from a scalar
@safe unittest
{
    static struct MyStruct
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

    static MyStruct constructMyStructScalar(ref Node node) @safe
    {
        // Guaranteed to be string as we construct from scalar.
        auto parts = node.as!string().split(":");
        return MyStruct(to!int(parts[0]), to!int(parts[1]), to!int(parts[2]));
    }

    import dyaml.loader : Loader;
    string data = "!mystruct 1:2:3";
    auto loader = Loader.fromString(data);
    auto constructor = new Constructor;
    constructor.addConstructorScalar("!mystruct", &constructMyStructScalar);
    loader.constructor = constructor;
    Node node = loader.load();

    assert(node.as!MyStruct == MyStruct(1, 2, 3));
}
///Construct a struct from a sequence
@safe unittest
{
    static struct MyStruct
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
    static MyStruct constructMyStructSequence(ref Node node) @safe
    {
        // node is guaranteed to be sequence.
        return MyStruct(node[0].as!int, node[1].as!int, node[2].as!int);
    }

    import dyaml.loader : Loader;
    string data = "!mystruct [1, 2, 3]";
    auto loader = Loader.fromString(data);
    auto constructor = new Constructor;
    constructor.addConstructorSequence("!mystruct", &constructMyStructSequence);
    loader.constructor = constructor;
    Node node = loader.load();

    assert(node.as!MyStruct == MyStruct(1, 2, 3));
}
///Construct a struct from a mapping
@safe unittest
{
    static struct MyStruct
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
    static MyStruct constructMyStructMapping(ref Node node) @safe
    {
        // node is guaranteed to be mapping.
        return MyStruct(node["x"].as!int, node["y"].as!int, node["z"].as!int);
    }

    import dyaml.loader : Loader;
    string data = "!mystruct {x: 1, y: 2, z: 3}";
    auto loader = Loader.fromString(data);
    auto constructor = new Constructor;
    constructor.addConstructorMapping("!mystruct", &constructMyStructMapping);
    loader.constructor = constructor;
    Node node = loader.load();

    assert(node.as!MyStruct == MyStruct(1, 2, 3));
}

/// Construct a _null _node.
YAMLNull constructNull(ref Node node) @safe pure nothrow @nogc
{
    return YAMLNull();
}

/// Construct a merge _node - a _node that merges another _node into a mapping.
YAMLMerge constructMerge(ref Node node) @safe pure nothrow @nogc
{
    return YAMLMerge();
}

/// Construct a boolean _node.
bool constructBool(ref Node node) @safe
{
    static yes = ["yes", "true", "on"];
    static no = ["no", "false", "off"];
    string value = node.as!string().toLower();
    if(yes.canFind(value)){return true;}
    if(no.canFind(value)) {return false;}
    throw new Exception("Unable to parse boolean value: " ~ value);
}

/// Construct an integer (long) _node.
long constructLong(ref Node node) @safe
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
        else if(value.startsWith("0b")){result = sign * to!int(value[2 .. $], 2);}
        //Hexadecimal.
        else if(value.startsWith("0x")){result = sign * to!int(value[2 .. $], 16);}
        //Octal.
        else if(value[0] == '0')       {result = sign * to!int(value, 8);}
        //Sexagesimal.
        else if(value.canFind(":"))
        {
            long val;
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
@safe unittest
{
    long getLong(string str) @safe
    {
        auto node = Node(str);
        return constructLong(node);
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

/// Construct a floating point (real) _node.
real constructReal(ref Node node) @safe
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
        throw new Exception("Unable to parse float value: \"" ~ value ~ "\"");
    }

    return result;
}
@safe unittest
{
    bool eq(real a, real b, real epsilon = 0.2) @safe
    {
        return a >= (b - epsilon) && a <= (b + epsilon);
    }

    real getReal(string str) @safe
    {
        auto node = Node(str);
        return constructReal(node);
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

/// Construct a binary (base64) _node.
ubyte[] constructBinary(ref Node node) @safe
{
    import std.ascii : newline;
    import std.array : array;

    string value = node.as!string;
    // For an unknown reason, this must be nested to work (compiler bug?).
    try
    {
        return Base64.decode(value.representation.filter!(c => !newline.canFind(c)).array);
    }
    catch(Base64Exception e)
    {
        throw new Exception("Unable to decode base64 value: " ~ e.msg);
    }
}

@safe unittest
{
    auto test = "The Answer: 42".representation;
    char[] buffer;
    buffer.length = 256;
    string input = Base64.encode(test, buffer).idup;
    auto node = Node(input);
    const value = constructBinary(node);
    assert(value == test);
    assert(value == [84, 104, 101, 32, 65, 110, 115, 119, 101, 114, 58, 32, 52, 50]);
}

/// Construct a timestamp (SysTime) _node.
SysTime constructTimestamp(ref Node node) @safe
{
    string value = node.as!string;

    auto YMDRegexp = regex("^([0-9][0-9][0-9][0-9])-([0-9][0-9]?)-([0-9][0-9]?)");
    auto HMSRegexp = regex("^[Tt \t]+([0-9][0-9]?):([0-9][0-9]):([0-9][0-9])(\\.[0-9]*)?");
    auto TZRegexp  = regex("^[ \t]*Z|([-+][0-9][0-9]?)(:[0-9][0-9])?");

    try
    {
        // First, get year, month and day.
        auto matches = match(value, YMDRegexp);

        enforce(!matches.empty,
                new Exception("Unable to parse timestamp value: " ~ value));

        auto captures = matches.front.captures;
        const year  = to!int(captures[1]);
        const month = to!int(captures[2]);
        const day   = to!int(captures[3]);

        // If available, get hour, minute, second and fraction, if present.
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
        const hectonanosecond = cast(int)(to!real("0" ~ captures[4]) * 10_000_000);

        // If available, get timezone.
        value = matches.front.post;
        matches = match(value, TZRegexp);
        if(matches.empty || matches.front.captures[0] == "Z")
        {
            // No timezone.
            return SysTime(DateTime(year, month, day, hour, minute, second),
                           hectonanosecond.dur!"hnsecs", UTC());
        }

        // We have a timezone, so parse it.
        captures = matches.front.captures;
        int sign    = 1;
        int tzHours;
        if(!captures[1].empty)
        {
            if(captures[1][0] == '-') {sign = -1;}
            tzHours   = to!int(captures[1][1 .. $]);
        }
        const tzMinutes = (!captures[2].empty) ? to!int(captures[2][1 .. $]) : 0;
        const tzOffset  = dur!"minutes"(sign * (60 * tzHours + tzMinutes));

        return SysTime(DateTime(year, month, day, hour, minute, second),
                       hectonanosecond.dur!"hnsecs",
                       new immutable SimpleTimeZone(tzOffset));
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
@safe unittest
{
    string timestamp(string value)
    {
        auto node = Node(value);
        return constructTimestamp(node).toISOString();
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

/// Construct a string _node.
string constructString(ref Node node) @safe
{
    return node.as!string;
}

/// Convert a sequence of single-element mappings into a sequence of pairs.
Node.Pair[] getPairs(string type, Node[] nodes) @safe
{
    Node.Pair[] pairs;
    pairs.reserve(nodes.length);
    foreach(ref node; nodes)
    {
        enforce(node.isMapping && node.length == 1,
                new Exception("While constructing " ~ type ~
                              ", expected a mapping with single element"));

        pairs ~= node.as!(Node.Pair[]);
    }

    return pairs;
}

/// Construct an ordered map (ordered sequence of key:value pairs without duplicates) _node.
Node.Pair[] constructOrderedMap(ref Node node) @safe
{
    auto pairs = getPairs("ordered map", node.as!(Node[]));

    //Detect duplicates.
    //TODO this should be replaced by something with deterministic memory allocation.
    auto keys = redBlackTree!Node();
    foreach(ref pair; pairs)
    {
        enforce(!(pair.key in keys),
                new Exception("Duplicate entry in an ordered map: "
                              ~ pair.key.debugString()));
        keys.insert(pair.key);
    }
    return pairs;
}
@safe unittest
{
    Node[] alternateTypes(uint length) @safe
    {
        Node[] pairs;
        foreach(long i; 0 .. length)
        {
            auto pair = (i % 2) ? Node.Pair(i.to!string, i) : Node.Pair(i, i.to!string);
            pairs ~= Node([pair]);
        }
        return pairs;
    }

    Node[] sameType(uint length) @safe
    {
        Node[] pairs;
        foreach(long i; 0 .. length)
        {
            auto pair = Node.Pair(i.to!string, i);
            pairs ~= Node([pair]);
        }
        return pairs;
    }

    bool hasDuplicates(Node[] nodes) @safe
    {
        auto node = Node(nodes);
        return null !is collectException(constructOrderedMap(node));
    }

    assert(hasDuplicates(alternateTypes(8) ~ alternateTypes(2)));
    assert(!hasDuplicates(alternateTypes(8)));
    assert(hasDuplicates(sameType(64) ~ sameType(16)));
    assert(hasDuplicates(alternateTypes(64) ~ alternateTypes(16)));
    assert(!hasDuplicates(sameType(64)));
    assert(!hasDuplicates(alternateTypes(64)));
}

/// Construct a pairs (ordered sequence of key: value pairs allowing duplicates) _node.
Node.Pair[] constructPairs(ref Node node) @safe
{
    return getPairs("pairs", node.as!(Node[]));
}

/// Construct a set _node.
Node[] constructSet(ref Node node) @safe
{
    auto pairs = node.as!(Node.Pair[]);

    // In future, the map here should be replaced with something with deterministic
    // memory allocation if possible.
    // Detect duplicates.
    ubyte[Node] map;
    Node[] nodes;
    nodes.reserve(pairs.length);
    foreach(ref pair; pairs)
    {
        enforce((pair.key in map) is null, new Exception("Duplicate entry in a set"));
        map[pair.key] = 0;
        nodes ~= pair.key;
    }

    return nodes;
}
@safe unittest
{
    Node.Pair[] set(uint length) @safe
    {
        Node.Pair[] pairs;
        foreach(long i; 0 .. length)
        {
            pairs ~= Node.Pair(i.to!string, YAMLNull());
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

    auto nodeDuplicatesShort   = Node(DuplicatesShort.dup);
    auto nodeNoDuplicatesShort = Node(noDuplicatesShort.dup);
    auto nodeDuplicatesLong    = Node(DuplicatesLong.dup);
    auto nodeNoDuplicatesLong  = Node(noDuplicatesLong.dup);

    assert(null !is collectException(constructSet(nodeDuplicatesShort)));
    assert(null is  collectException(constructSet(nodeNoDuplicatesShort)));
    assert(null !is collectException(constructSet(nodeDuplicatesLong)));
    assert(null is  collectException(constructSet(nodeNoDuplicatesLong)));
}

/// Construct a sequence (array) _node.
Node[] constructSequence(ref Node node) @safe
{
    return node.as!(Node[]);
}

/// Construct an unordered map (unordered set of key:value _pairs without duplicates) _node.
Node.Pair[] constructMap(ref Node node) @safe
{
    auto pairs = node.as!(Node.Pair[]);
    //Detect duplicates.
    //TODO this should be replaced by something with deterministic memory allocation.
    auto keys = redBlackTree!Node();
    foreach(ref pair; pairs)
    {
        enforce(!(pair.key in keys),
                new Exception("Duplicate entry in a map: " ~ pair.key.debugString()));
        keys.insert(pair.key);
    }
    return pairs;
}
