
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.testconstructor;


import std.datetime;
import std.exception;
import std.path;
import std.string;

import dyaml.tag;
import dyaml.testcommon;


///Expected results of loading test inputs.
Node[][string] expected;

///Initialize expected.
static this()
{
    expected["aliases-cdumper-bug"]         = constructAliasesCDumperBug();
    expected["construct-binary"]            = constructBinary();
    expected["construct-bool"]              = constructBool();
    expected["construct-custom"]            = constructCustom();
    expected["construct-float"]             = constructFloat();
    expected["construct-int"]               = constructInt();
    expected["construct-map"]               = constructMap();
    expected["construct-merge"]             = constructMerge();
    expected["construct-null"]              = constructNull();
    expected["construct-omap"]              = constructOMap();
    expected["construct-pairs"]             = constructPairs();
    expected["construct-seq"]               = constructSeq();
    expected["construct-set"]               = constructSet();
    expected["construct-str-ascii"]         = constructStrASCII();
    expected["construct-str"]               = constructStr();
    expected["construct-str-utf8"]          = constructStrUTF8();
    expected["construct-timestamp"]         = constructTimestamp();
    expected["construct-value"]             = constructValue();
    expected["duplicate-merge-key"]         = duplicateMergeKey();
    expected["float-representer-2.3-bug"]   = floatRepresenterBug();
    expected["invalid-single-quote-bug"]    = invalidSingleQuoteBug();
    expected["more-floats"]                 = moreFloats();
    expected["negative-float-bug"]          = negativeFloatBug();
    expected["single-dot-is-not-float-bug"] = singleDotFloatBug();
    expected["timestamp-bugs"]              = timestampBugs();
    expected["utf16be"]                     = utf16be();
    expected["utf16le"]                     = utf16le();
    expected["utf8"]                        = utf8();
    expected["utf8-implicit"]               = utf8implicit();
}

///Construct a pair of nodes with specified values.
Node.Pair pair(A, B)(A a, B b)
{
    return Node.Pair(a,b);
}

///Test cases:

Node[] constructAliasesCDumperBug()
{
    return [Node(["today", "today"])];
}

Node[] constructBinary()
{
    auto canonical   = cast(ubyte[])"GIF89a\x0c\x00\x0c\x00\x84\x00\x00\xff\xff\xf7\xf5\xf5\xee\xe9\xe9\xe5fff\x00\x00\x00\xe7\xe7\xe7^^^\xf3\xf3\xed\x8e\x8e\x8e\xe0\xe0\xe0\x9f\x9f\x9f\x93\x93\x93\xa7\xa7\xa7\x9e\x9e\x9eiiiccc\xa3\xa3\xa3\x84\x84\x84\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9!\xfe\x0eMade with GIMP\x00,\x00\x00\x00\x00\x0c\x00\x0c\x00\x00\x05,  \x8e\x810\x9e\xe3@\x14\xe8i\x10\xc4\xd1\x8a\x08\x1c\xcf\x80M$z\xef\xff0\x85p\xb8\xb01f\r\x1b\xce\x01\xc3\x01\x1e\x10' \x82\n\x01\x00;";
    auto generic     = cast(ubyte[])"GIF89a\x0c\x00\x0c\x00\x84\x00\x00\xff\xff\xf7\xf5\xf5\xee\xe9\xe9\xe5fff\x00\x00\x00\xe7\xe7\xe7^^^\xf3\xf3\xed\x8e\x8e\x8e\xe0\xe0\xe0\x9f\x9f\x9f\x93\x93\x93\xa7\xa7\xa7\x9e\x9e\x9eiiiccc\xa3\xa3\xa3\x84\x84\x84\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9!\xfe\x0eMade with GIMP\x00,\x00\x00\x00\x00\x0c\x00\x0c\x00\x00\x05,  \x8e\x810\x9e\xe3@\x14\xe8i\x10\xc4\xd1\x8a\x08\x1c\xcf\x80M$z\xef\xff0\x85p\xb8\xb01f\r\x1b\xce\x01\xc3\x01\x1e\x10' \x82\n\x01\x00;";
    auto description = "The binary value above is a tiny arrow encoded as a gif image.";

    return [Node([pair("canonical",   canonical),
                  pair("generic",     generic),
                  pair("description", description)])];
}

Node[] constructBool()
{
    return [Node([pair("canonical", true),
                  pair("answer",    false),
                  pair("logical",   true),
                  pair("option",    true),
                  pair("but", [pair("y", "is a string"), pair("n", "is a string")])])];
}

Node[] constructCustom()
{
    return [Node([Node(new TestClass(1, 2, 3)), 
                  Node(TestStruct(10))])];
}

Node[] constructFloat()
{
    return [Node([pair("canonical",         cast(real)685230.15),
                  pair("exponential",       cast(real)685230.15),
                  pair("fixed",             cast(real)685230.15),
                  pair("sexagesimal",       cast(real)685230.15),
                  pair("negative infinity", -real.infinity),
                  pair("not a number",      real.nan)])];
}

Node[] constructInt()
{
    return [Node([pair("canonical",   685230L),
                  pair("decimal",     685230L),
                  pair("octal",       685230L),
                  pair("hexadecimal", 685230L),
                  pair("binary",      685230L),
                  pair("sexagesimal", 685230L)])];
}

Node[] constructMap()
{
    return [Node([pair("Block style", 
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
    return [Node([Node([pair("x", 1L), pair("y", 2L)]),
                  Node([pair("x", 0L), pair("y", 2L)]), 
                  Node([pair("r", 10L)]), 
                  Node([pair("r", 1L)]), 
                  Node([pair("x", 1L), pair("y", 2L), pair("r", 10L), pair("label", "center/big")]), 
                  Node([pair("r", 10L), pair("label", "center/big"), pair("x", 1L), pair("y", 2L)]), 
                  Node([pair("label", "center/big"), pair("x", 1L), pair("y", 2L), pair("r", 10L)]), 
                  Node([pair("x", 1L), pair("label", "center/big"), pair("r", 10L), pair("y", 2L)])])];
}

Node[] constructNull()
{
    return [Node(YAMLNull()),
            Node([pair("empty", YAMLNull()), 
                  pair("canonical", YAMLNull()), 
                  pair("english", YAMLNull()), 
                  pair(YAMLNull(), "null key")]),
            Node([pair("sparse", 
                       [Node(YAMLNull()),
                        Node("2nd entry"),
                        Node(YAMLNull()),
                        Node("4th entry"),
                        Node(YAMLNull())])])];
}

Node[] constructOMap()
{
    return [Node([pair("Bestiary", 
                       [pair("aardvark", "African pig-like ant eater. Ugly."), 
                        pair("anteater", "South-American ant eater. Two species."), 
                        pair("anaconda", "South-American constrictor snake. Scaly.")]), 
                  pair("Numbers",[pair("one", 1L), 
                                  pair("two", 2L), 
                                  pair("three", 3L)])])];
}

Node[] constructPairs()
{
    return [Node([pair("Block tasks", 
                       Node([pair("meeting", "with team."),
                             pair("meeting", "with boss."),
                             pair("break", "lunch."),
                             pair("meeting", "with client.")], "tag:yaml.org,2002:pairs")),
                  pair("Flow tasks", 
                       Node([pair("meeting", "with team"),
                             pair("meeting", "with boss")], "tag:yaml.org,2002:pairs"))])];
}

Node[] constructSeq()
{
    return [Node([pair("Block style", 
                       [Node("Mercury"), Node("Venus"), Node("Earth"), Node("Mars"),
                        Node("Jupiter"), Node("Saturn"), Node("Uranus"), Node("Neptune"),
                        Node("Pluto")]), 
                  pair("Flow style",
                       [Node("Mercury"), Node("Venus"), Node("Earth"), Node("Mars"),
                        Node("Jupiter"), Node("Saturn"), Node("Uranus"), Node("Neptune"),
                        Node("Pluto")])])];
}

Node[] constructSet()
{
    return [Node([pair("baseball players",
                       [Node("Mark McGwire"), Node("Sammy Sosa"), Node("Ken Griffey")]), 
                  pair("baseball teams", 
                       [Node("Boston Red Sox"), Node("Detroit Tigers"), Node("New York Yankees")])])];
}

Node[] constructStrASCII()
{
    return [Node("ascii string")];
}

Node[] constructStr()
{
    return [Node([pair("string", "abcd")])];
}

Node[] constructStrUTF8()
{
    return [Node("\u042d\u0442\u043e \u0443\u043d\u0438\u043a\u043e\u0434\u043d\u0430\u044f \u0441\u0442\u0440\u043e\u043a\u0430")];
}

Node[] constructTimestamp()
{
    return [Node([pair("canonical",        SysTime(DateTime(2001, 12, 15, 2, 59, 43), FracSec.from!"hnsecs"(1000000), UTC())), 
                  pair("valid iso8601",    SysTime(DateTime(2001, 12, 15, 2, 59, 43), FracSec.from!"hnsecs"(1000000), UTC())),
                  pair("space separated",  SysTime(DateTime(2001, 12, 15, 2, 59, 43), FracSec.from!"hnsecs"(1000000), UTC())),
                  pair("no time zone (Z)", SysTime(DateTime(2001, 12, 15, 2, 59, 43), FracSec.from!"hnsecs"(1000000), UTC())),
                  pair("date (00:00:00Z)", SysTime(DateTime(2002, 12, 14), UTC()))])];
}

Node[] constructValue()
{
    return[Node([pair("link with", 
                      [Node("library1.dll"), Node("library2.dll")])]),
           Node([pair("link with", 
                      [Node([pair("=", "library1.dll"), pair("version", cast(real)1.2)]), 
                       Node([pair("=", "library2.dll"), pair("version", cast(real)2.3)])])])];
}

Node[] duplicateMergeKey()
{
    return [Node([pair("foo", "bar"),  
                  pair("x", 1L), 
                  pair("y", 2L), 
                  pair("z", 3L), 
                  pair("t", 4L)])];
}

Node[] floatRepresenterBug()
{
    return [Node([pair(cast(real)1.0, 1L),
                  pair(real.infinity, 10L), 
                  pair(-real.infinity, -10L),
                  pair(real.nan, 100L)])];
}

Node[] invalidSingleQuoteBug()
{
    return [Node([Node("foo \'bar\'"), Node("foo\n\'bar\'")])];
}

Node[] moreFloats()
{
    return [Node([Node(cast(real)0.0),
                  Node(cast(real)1.0),
                  Node(cast(real)-1.0),
                  Node(real.infinity),
                  Node(-real.infinity),
                  Node(real.nan),
                  Node(real.nan)])];
}

Node[] negativeFloatBug()
{
    return [Node(cast(real)-1.0)];
}

Node[] singleDotFloatBug()
{
    return [Node(".")];
}

Node[] timestampBugs()
{
    return [Node([Node(SysTime(DateTime(2001, 12, 15, 3, 29, 43),  FracSec.from!"hnsecs"(1000000), UTC())), 
                  Node(SysTime(DateTime(2001, 12, 14, 16, 29, 43), FracSec.from!"hnsecs"(1000000), UTC())), 
                  Node(SysTime(DateTime(2001, 12, 14, 21, 59, 43), FracSec.from!"hnsecs"(10100), UTC())), 
                  Node(SysTime(DateTime(2001, 12, 14, 21, 59, 43), new SimpleTimeZone(60))), 
                  Node(SysTime(DateTime(2001, 12, 14, 21, 59, 43), new SimpleTimeZone(-90))),
                  Node(SysTime(DateTime(2005, 7, 8, 17, 35, 4),    FracSec.from!"hnsecs"(5176000), UTC()))])];
}

Node[] utf16be()
{
    return [Node("UTF-16-BE")];
}

Node[] utf16le()
{
    return [Node("UTF-16-LE")];
}

Node[] utf8()
{
    return [Node("UTF-8")];
}

Node[] utf8implicit()
{
    return [Node("implicit UTF-8")];
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

    override string toString()
    {
        return format("TestClass(", x, ", ", y, ", ", z, ")");
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
TestClass constructClass(Mark start, Mark end, ref Node node)
{
    try
    {
        return new TestClass(node["x"].get!int, node["y"].get!int, node["z"].get!int);
    }
    catch(NodeException e)
    {
        throw new ConstructorException("Error constructing TestClass (missing data members?) " 
                                       ~ e.msg, start, end);
    }
}

Node representClass(ref Node node, Representer representer)
{ 
    auto value = node.get!TestClass;
    auto pairs = [Node.Pair("x", value.x), 
                  Node.Pair("y", value.y), 
                  Node.Pair("z", value.z)];
    auto result = representer.representMapping("!tag1", pairs);

    return result;
}
          
///Constructor function for TestStruct.
TestStruct constructStruct(Mark start, Mark end, ref Node node)
{
    return TestStruct(to!int(node.get!string));
}

///Representer function for TestStruct.
Node representStruct(ref Node node, Representer representer)
{
    string[] keys, values;
    auto value = node.get!TestStruct;
    return representer.representScalar("!tag2", to!string(value.value));
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
    string base = dataFilename.baseName.stripExtension;
    enforce((base in expected) !is null,
            new Exception("Unimplemented constructor test: " ~ base));

    auto constructor = new Constructor;
    constructor.addConstructorMapping("!tag1", &constructClass);
    constructor.addConstructorScalar("!tag2", &constructStruct);

    auto loader        = Loader(dataFilename);
    loader.constructor = constructor;
    loader.resolver    = new Resolver;

    Node[] exp = expected[base];

    //Compare with expected results document by document.
    size_t i = 0;
    foreach(node; loader)
    {
        if(!node.equals!(Node, false)(exp[i]))
        {
            if(verbose)
            {
                writeln("Expected value:");
                writeln(exp[i].debugString);
                writeln("\n");
                writeln("Actual value:");
                writeln(node.debugString);
            }
            assert(false);
        }
        ++i;
    }
    assert(i == exp.length);
}


unittest
{
    writeln("D:YAML Constructor unittest");
    run("testConstructor", &testConstructor, ["data", "code"]);
}
