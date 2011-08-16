
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.testconstructor;


import std.datetime;
import std.exception;
import std.path;

import dyaml.testcommon;


///Expected results of loading test inputs.
Node[][string] expected;

///Initialize expected.
static this()
{
    expected["construct-binary.data"]            = constructBinary();
    expected["construct-bool.data"]              = constructBool();
    expected["construct-custom.data"]            = constructCustom();
    expected["construct-float.data"]             = constructFloat();
    expected["construct-int.data"]               = constructInt();
    expected["construct-map.data"]               = constructMap();
    expected["construct-merge.data"]             = constructMerge();
    expected["construct-null.data"]              = constructNull();
    expected["construct-omap.data"]              = constructOMap();
    expected["construct-pairs.data"]             = constructPairs();
    expected["construct-seq.data"]               = constructSeq();
    expected["construct-set.data"]               = constructSet();
    expected["construct-str-ascii.data"]         = constructStrASCII();
    expected["construct-str.data"]               = constructStr();
    expected["construct-str-utf8.data"]          = constructStrUTF8();
    expected["construct-timestamp.data"]         = constructTimestamp();
    expected["construct-value.data"]             = constructValue();
    expected["duplicate-merge-key.data"]         = duplicateMergeKey();
    expected["float-representer-2.3-bug.data"]   = floatRepresenterBug();
    expected["invalid-single-quote-bug.data"]    = invalidSingleQuoteBug();
    expected["more-floats.data"]                 = moreFloats();
    expected["negative-float-bug.data"]          = negativeFloatBug();
    expected["single-dot-is-not-float-bug.data"] = singleDotFloatBug();
    expected["timestamp-bugs.data"]              = timestampBugs();
    expected["utf16be.data"]                     = utf16be();
    expected["utf16le.data"]                     = utf16le();
    expected["utf8.data"]                        = utf8();
    expected["utf8-implicit.data"]               = utf8implicit();
}

///Construct a node with specified value.
Node node(T)(T value)
{
    static if(Node.Value.allowed!T){return Node(Node.Value(value));}
    else{return Node(Node.userValue(value));}
}

///Construct a pair of nodes with specified values.
Node.Pair pair(A, B)(A a, B b)
{
    static if(is(A == Node) && is(B == Node)){return Node.Pair(a, b);}
    else static if(is(A == Node))            {return Node.Pair(a, node(b));}
    else static if(is(B == Node))            {return Node.Pair(node(a), b);}
    else                                     {return Node.Pair(node(a), node(b));}
}

///Test cases:

Node[] constructBinary()
{
    auto canonical   = cast(ubyte[])"GIF89a\x0c\x00\x0c\x00\x84\x00\x00\xff\xff\xf7\xf5\xf5\xee\xe9\xe9\xe5fff\x00\x00\x00\xe7\xe7\xe7^^^\xf3\xf3\xed\x8e\x8e\x8e\xe0\xe0\xe0\x9f\x9f\x9f\x93\x93\x93\xa7\xa7\xa7\x9e\x9e\x9eiiiccc\xa3\xa3\xa3\x84\x84\x84\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9!\xfe\x0eMade with GIMP\x00,\x00\x00\x00\x00\x0c\x00\x0c\x00\x00\x05,  \x8e\x810\x9e\xe3@\x14\xe8i\x10\xc4\xd1\x8a\x08\x1c\xcf\x80M$z\xef\xff0\x85p\xb8\xb01f\r\x1b\xce\x01\xc3\x01\x1e\x10' \x82\n\x01\x00;";
    auto generic     = cast(ubyte[])"GIF89a\x0c\x00\x0c\x00\x84\x00\x00\xff\xff\xf7\xf5\xf5\xee\xe9\xe9\xe5fff\x00\x00\x00\xe7\xe7\xe7^^^\xf3\xf3\xed\x8e\x8e\x8e\xe0\xe0\xe0\x9f\x9f\x9f\x93\x93\x93\xa7\xa7\xa7\x9e\x9e\x9eiiiccc\xa3\xa3\xa3\x84\x84\x84\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9!\xfe\x0eMade with GIMP\x00,\x00\x00\x00\x00\x0c\x00\x0c\x00\x00\x05,  \x8e\x810\x9e\xe3@\x14\xe8i\x10\xc4\xd1\x8a\x08\x1c\xcf\x80M$z\xef\xff0\x85p\xb8\xb01f\r\x1b\xce\x01\xc3\x01\x1e\x10' \x82\n\x01\x00;";
    auto description = "The binary value above is a tiny arrow encoded as a gif image.";

    return [node([pair("canonical",   canonical),
                  pair("generic",     generic),
                  pair("description", description)])];
}

Node[] constructBool()
{
    return [node([pair("canonical", true),
                  pair("answer",    false),
                  pair("logical",   true),
                  pair("option",    true),
                  pair("but", [pair("y", "is a string"), pair("n", "is a string")])])];
}

Node[] constructCustom()
{
    return [node([node(new TestClass(1, 0, 0)), 
                  node(new TestClass(1, 2, 3)), 
                  node(TestStruct(10))])];
}

Node[] constructFloat()
{
    return [node([pair("canonical",         cast(real)685230.15),
                  pair("exponential",       cast(real)685230.15),
                  pair("fixed",             cast(real)685230.15),
                  pair("sexagesimal",       cast(real)685230.15),
                  pair("negative infinity", -real.infinity),
                  pair("not a number",      real.nan)])];
}

Node[] constructInt()
{
    return [node([pair("canonical",   685230L),
                  pair("decimal",     685230L),
                  pair("octal",       685230L),
                  pair("hexadecimal", 685230L),
                  pair("binary",      685230L),
                  pair("sexagesimal", 685230L)])];
}

Node[] constructMap()
{
    return [node([pair("Block style", 
                       [pair("Clark", "Evans"), 
                        pair("Brian", "Ingerson"), 
                        pair("Oren", "Ben-Kiki")]),
                  pair("Flow style",
                       [pair("Clark", "Evans"), 
                        pair("Brian", "Ingerson"), 
                        pair("Oren", "Ben-Kiki")])])];
}

Node[] constructMerge()
{
    return [node([node([pair("x", 1L), pair("y", 2L)]),
                  node([pair("x", 0L), pair("y", 2L)]), 
                  node([pair("r", 10L)]), 
                  node([pair("r", 1L)]), 
                  node([pair("x", 1L), pair("y", 2L), pair("r", 10L), pair("label", "center/big")]), 
                  node([pair("r", 10L), pair("label", "center/big"), pair("x", 1L), pair("y", 2L)]), 
                  node([pair("label", "center/big"), pair("x", 1L), pair("y", 2L), pair("r", 10L)]), 
                  node([pair("x", 1L), pair("label", "center/big"), pair("r", 10L), pair("y", 2L)])])];
}

Node[] constructNull()
{
    return [node(YAMLNull()),
            node([pair("empty", YAMLNull()), 
                  pair("canonical", YAMLNull()), 
                  pair("english", YAMLNull()), 
                  pair(YAMLNull(), "null key")]),
            node([pair("sparse", 
                       [node(YAMLNull()),
                        node("2nd entry"),
                        node(YAMLNull()),
                        node("4th entry"),
                        node(YAMLNull())])])];
}

Node[] constructOMap()
{
    return [node([pair("Bestiary", 
                       [pair("aardvark", "African pig-like ant eater. Ugly."), 
                        pair("anteater", "South-American ant eater. Two species."), 
                        pair("anaconda", "South-American constrictor snake. Scaly.")]), 
                  pair("Numbers",[pair("one", 1L), 
                                  pair("two", 2L), 
                                  pair("three", 3L)])])];
}

Node[] constructPairs()
{
    return [node([pair("Block tasks", 
                       [pair("meeting", "with team."),
                        pair("meeting", "with boss."),
                        pair("break", "lunch."),
                        pair("meeting", "with client.")]),
                  pair("Flow tasks", 
                       [pair("meeting", "with team"),
                        pair("meeting", "with boss")])])];
}

Node[] constructSeq()
{
    return [node([pair("Block style", 
                       [node("Mercury"), node("Venus"), node("Earth"), node("Mars"),
                        node("Jupiter"), node("Saturn"), node("Uranus"), node("Neptune"),
                        node("Pluto")]), 
                  pair("Flow style",
                       [node("Mercury"), node("Venus"), node("Earth"), node("Mars"),
                        node("Jupiter"), node("Saturn"), node("Uranus"), node("Neptune"),
                        node("Pluto")])])];
}

Node[] constructSet()
{
    return [node([pair("baseball players",
                       [node("Mark McGwire"), node("Sammy Sosa"), node("Ken Griffey")]), 
                  pair("baseball teams", 
                       [node("Boston Red Sox"), node("Detroit Tigers"), node("New York Yankees")])])];
}

Node[] constructStrASCII()
{
    return [node("ascii string")];
}

Node[] constructStr()
{
    return [node([pair("string", "abcd")])];
}

Node[] constructStrUTF8()
{
    return [node("\u042d\u0442\u043e \u0443\u043d\u0438\u043a\u043e\u0434\u043d\u0430\u044f \u0441\u0442\u0440\u043e\u043a\u0430")];
}

Node[] constructTimestamp()
{
    return [node([pair("canonical",        SysTime(DateTime(2001, 12, 15, 2, 59, 43), FracSec.from!"hnsecs"(1000000), UTC())), 
                  pair("valid iso8601",    SysTime(DateTime(2001, 12, 15, 2, 59, 43), FracSec.from!"hnsecs"(1000000), UTC())),
                  pair("space separated",  SysTime(DateTime(2001, 12, 15, 2, 59, 43), FracSec.from!"hnsecs"(1000000), UTC())),
                  pair("no time zone (Z)", SysTime(DateTime(2001, 12, 15, 2, 59, 43), FracSec.from!"hnsecs"(1000000), UTC())),
                  pair("date (00:00:00Z)", SysTime(DateTime(2002, 12, 14), UTC()))])];
}

Node[] constructValue()
{
    return[node([pair("link with", 
                      [node("library1.dll"), node("library2.dll")])]),
           node([pair("link with", 
                      [node([pair("=", "library1.dll"), pair("version", cast(real)1.2)]), 
                       node([pair("=", "library2.dll"), pair("version", cast(real)2.3)])])])];
}

Node[] duplicateMergeKey()
{
    return [node([pair("foo", "bar"),  
                  pair("x", 1L), 
                  pair("y", 2L), 
                  pair("z", 3L), 
                  pair("t", 4L)])];
}

Node[] floatRepresenterBug()
{
    return [node([pair(cast(real)1.0, 1L),
                  pair(real.infinity, 10L), 
                  pair(-real.infinity, -10L),
                  pair(real.nan, 100L)])];
}

Node[] invalidSingleQuoteBug()
{
    return [node([node("foo \'bar\'"), node("foo\n\'bar\'")])];
}

Node[] moreFloats()
{
    return [node([node(cast(real)0.0),
                  node(cast(real)1.0),
                  node(cast(real)-1.0),
                  node(real.infinity),
                  node(-real.infinity),
                  node(real.nan),
                  node(real.nan)])];
}

Node[] negativeFloatBug()
{
    return [node(cast(real)-1.0)];
}

Node[] singleDotFloatBug()
{
    return [node(".")];
}

Node[] timestampBugs()
{
    return [node([node(SysTime(DateTime(2001, 12, 15, 3, 29, 43),  FracSec.from!"hnsecs"(1000000), UTC())), 
                  node(SysTime(DateTime(2001, 12, 14, 16, 29, 43), FracSec.from!"hnsecs"(1000000), UTC())), 
                  node(SysTime(DateTime(2001, 12, 14, 21, 59, 43), FracSec.from!"hnsecs"(10100), UTC())), 
                  node(SysTime(DateTime(2001, 12, 14, 21, 59, 43), new SimpleTimeZone(60))), 
                  node(SysTime(DateTime(2001, 12, 14, 21, 59, 43), new SimpleTimeZone(-90))),
                  node(SysTime(DateTime(2005, 7, 8, 17, 35, 4),    FracSec.from!"hnsecs"(5176000), UTC()))])];
}

Node[] utf16be()
{
    return [node("UTF-16-BE")];
}

Node[] utf16le()
{
    return [node("UTF-16-LE")];
}

Node[] utf8()
{
    return [node("UTF-8")];
}

Node[] utf8implicit()
{
    return [node("implicit UTF-8")];
}

///Testing custom YAML class type.
class TestClass
{
    int x, y, z;

    this(int x, int y, int z)
    {
        this.x = x; 
        this.y = y; 
        this.z = z;
    }

    override bool opEquals(Object rhs)
    {
        if(typeid(rhs) != typeid(TestClass)){return false;}
        auto t = cast(TestClass)rhs;
        return x == t.x && y == t.y && z == t.z;
    }
}

///Testing custom YAML struct type.
struct TestStruct
{
    int value;

    bool opEquals(const ref TestStruct rhs) const
    {
        return value == rhs.value;
    }
}

///Constructor function for TestClass.
TestClass constructClass(Mark start, Mark end, Node.Pair[] pairs)
{
    int x, y, z;
    foreach(ref pair; pairs)
    {
        switch(pair.key.get!string)
        {
            case "x": x = pair.value.get!int; break;
            case "y": y = pair.value.get!int; break;
            case "z": z = pair.value.get!int; break;
            default: break;
        }
    }

    return new TestClass(x, y, z);
}
          
///Constructor function for TestStruct.
TestStruct constructStruct(Mark start, Mark end, string value)
{
    return TestStruct(to!int(value));
}

/**
 * Constructor unittest.
 *
 * Params:  verbose      = Print verbose output?
 *          dataFilename = File name to read from.
 *          codeDummy    = Dummy .code filename, used to determine that
 *                         .data file with the same name should be used in this test.
 */
void testConstructor(bool verbose, string dataFilename, string codeDummy)
{
    string base = dataFilename.basename;
    enforce((base in expected) !is null,
            new Exception("Unimplemented constructor test: " ~ base));

    auto constructor = new Constructor;
    constructor.addConstructor("!tag1", &constructClass);
    constructor.addConstructor("!tag2", &constructStruct);

    auto resolver = new Resolver;
    auto loader   = Loader(dataFilename, constructor, resolver);

    //Compare with expected results document by document.
    size_t i = 0;
    foreach(node; loader)
    {
        if(node != expected[base][i])
        {
            if(verbose)
            {
                writeln("Expected value:");
                writeln(expected[base][i].debugString);
                writeln("\n");
                writeln("Actual value:");
                writeln(node.debugString);
            }
            assert(false);
        }
        ++i;
    }
    assert(i == expected[base].length);
}


unittest
{
    writeln("D:YAML Constructor unittest");
    run("testConstructor", &testConstructor, ["data", "code"]);
}
