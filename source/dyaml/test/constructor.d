
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.constructor;


version(unittest)
{

import std.datetime;
import std.exception;
import std.path;
import std.string;
import std.typecons;

import dyaml.test.common;


///Expected results of loading test inputs.
Node[][string] expected;

///Initialize expected.
static this() @safe
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

Node[] constructAliasesCDumperBug() @safe
{
    return [
        Node(
            [
                Node("today", "tag:yaml.org,2002:str"),
                Node("today", "tag:yaml.org,2002:str")
            ],
        "tag:yaml.org,2002:seq")
    ];
}

Node[] constructBinary() @safe
{
    auto canonical   = "GIF89a\x0c\x00\x0c\x00\x84\x00\x00\xff\xff\xf7\xf5\xf5\xee\xe9\xe9\xe5fff\x00\x00\x00\xe7\xe7\xe7^^^\xf3\xf3\xed\x8e\x8e\x8e\xe0\xe0\xe0\x9f\x9f\x9f\x93\x93\x93\xa7\xa7\xa7\x9e\x9e\x9eiiiccc\xa3\xa3\xa3\x84\x84\x84\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9!\xfe\x0eMade with GIMP\x00,\x00\x00\x00\x00\x0c\x00\x0c\x00\x00\x05,  \x8e\x810\x9e\xe3@\x14\xe8i\x10\xc4\xd1\x8a\x08\x1c\xcf\x80M$z\xef\xff0\x85p\xb8\xb01f\r\x1b\xce\x01\xc3\x01\x1e\x10' \x82\n\x01\x00;".representation.dup;
    auto generic     = "GIF89a\x0c\x00\x0c\x00\x84\x00\x00\xff\xff\xf7\xf5\xf5\xee\xe9\xe9\xe5fff\x00\x00\x00\xe7\xe7\xe7^^^\xf3\xf3\xed\x8e\x8e\x8e\xe0\xe0\xe0\x9f\x9f\x9f\x93\x93\x93\xa7\xa7\xa7\x9e\x9e\x9eiiiccc\xa3\xa3\xa3\x84\x84\x84\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9\xff\xfe\xf9!\xfe\x0eMade with GIMP\x00,\x00\x00\x00\x00\x0c\x00\x0c\x00\x00\x05,  \x8e\x810\x9e\xe3@\x14\xe8i\x10\xc4\xd1\x8a\x08\x1c\xcf\x80M$z\xef\xff0\x85p\xb8\xb01f\r\x1b\xce\x01\xc3\x01\x1e\x10' \x82\n\x01\x00;".representation.dup;
    auto description = "The binary value above is a tiny arrow encoded as a gif image.";

    return [
        Node(
            [
                pair(
                    Node("canonical", "tag:yaml.org,2002:str"),
                    Node(canonical, "tag:yaml.org,2002:binary")
                ),
                pair(
                    Node("generic", "tag:yaml.org,2002:str"),
                    Node(generic, "tag:yaml.org,2002:binary")
                ),
                pair(
                    Node("description", "tag:yaml.org,2002:str"),
                    Node(description, "tag:yaml.org,2002:str")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructBool() @safe
{
    const(bool) a = true;
    immutable(bool) b = true;
    const bool aa = true;
    immutable bool bb = true;
    return [
        Node(
            [
                pair(
                    Node("canonical", "tag:yaml.org,2002:str"),
                    Node(true, "tag:yaml.org,2002:bool")
                ),
                pair(
                    Node("answer", "tag:yaml.org,2002:str"),
                    Node(false, "tag:yaml.org,2002:bool")
                ),
                pair(
                    Node("logical", "tag:yaml.org,2002:str"),
                    Node(true, "tag:yaml.org,2002:bool")
                ),
                pair(
                    Node("option", "tag:yaml.org,2002:str"),
                    Node(true, "tag:yaml.org,2002:bool")
                ),
                pair(
                    Node("constbool", "tag:yaml.org,2002:str"),
                    Node(a, "tag:yaml.org,2002:bool")
                ),
                pair(
                    Node("imutbool", "tag:yaml.org,2002:str"),
                    Node(b, "tag:yaml.org,2002:bool")
                ),
                pair(
                    Node("const_bool", "tag:yaml.org,2002:str"),
                    Node(aa, "tag:yaml.org,2002:bool")
                ),
                pair(
                    Node("imut_bool", "tag:yaml.org,2002:str"),
                    Node(bb, "tag:yaml.org,2002:bool")
                ),
                pair(
                    Node("but", "tag:yaml.org,2002:str"),
                    Node(
                            [
                            pair(
                                Node("y", "tag:yaml.org,2002:str"),
                                Node("is a string", "tag:yaml.org,2002:str")
                            ),
                            pair(
                                Node("n", "tag:yaml.org,2002:str"),
                                Node("is a string", "tag:yaml.org,2002:str")
                            )
                        ],
                    "tag:yaml.org,2002:map")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructCustom() @safe
{
    return [
        Node(
            [
                Node(new TestClass(1, 2, 3)),
                Node(TestStruct(10))
            ],
        "tag:yaml.org,2002:seq")
    ];
}

Node[] constructFloat() @safe
{
    return [
        Node(
            [
                pair(
                    Node("canonical", "tag:yaml.org,2002:str"),
                    Node(685230.15L, "tag:yaml.org,2002:float")
                ),
                pair(
                    Node("exponential", "tag:yaml.org,2002:str"),
                    Node(685230.15L, "tag:yaml.org,2002:float")
                ),
                pair(
                    Node("fixed", "tag:yaml.org,2002:str"),
                    Node(685230.15L, "tag:yaml.org,2002:float")
                ),
                pair(
                    Node("sexagesimal", "tag:yaml.org,2002:str"),
                    Node(685230.15L, "tag:yaml.org,2002:float")
                ),
                pair(
                    Node("negative infinity", "tag:yaml.org,2002:str"),
                    Node(-real.infinity, "tag:yaml.org,2002:float")
                ),
                pair(
                    Node("not a number", "tag:yaml.org,2002:str"),
                    Node(real.nan, "tag:yaml.org,2002:float")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructInt() @safe
{
    return [
        Node(
            [
                pair(
                    Node("canonical", "tag:yaml.org,2002:str"),
                    Node(685230L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node("decimal", "tag:yaml.org,2002:str"),
                    Node(685230L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node("octal", "tag:yaml.org,2002:str"),
                    Node(685230L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node("hexadecimal", "tag:yaml.org,2002:str"),
                    Node(685230L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node("binary", "tag:yaml.org,2002:str"),
                    Node(685230L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node("sexagesimal", "tag:yaml.org,2002:str"),
                    Node(685230L, "tag:yaml.org,2002:int")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructMap() @safe
{
    return [
        Node(
            [
                pair(
                    Node("Block style", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            pair(
                                Node("Clark", "tag:yaml.org,2002:str"),
                                Node("Evans", "tag:yaml.org,2002:str")
                            ),
                            pair(
                                Node("Brian", "tag:yaml.org,2002:str"),
                                Node("Ingerson", "tag:yaml.org,2002:str")
                            ),
                            pair(
                                Node("Oren", "tag:yaml.org,2002:str"),
                                Node("Ben-Kiki", "tag:yaml.org,2002:str")
                            )
                        ],
                    "tag:yaml.org,2002:map")
                ),
                pair(
                    Node("Flow style", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            pair(
                                Node("Clark", "tag:yaml.org,2002:str"),
                                Node("Evans", "tag:yaml.org,2002:str")
                            ),
                            pair(
                                Node("Brian", "tag:yaml.org,2002:str"),
                                Node("Ingerson", "tag:yaml.org,2002:str")
                            ),
                            pair(
                                Node("Oren", "tag:yaml.org,2002:str"),
                                Node("Ben-Kiki", "tag:yaml.org,2002:str")
                            )
                        ],
                    "tag:yaml.org,2002:map")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructMerge() @safe
{
    return [
        Node(
            [
                Node(
                    [
                        pair(
                            Node("x", "tag:yaml.org,2002:str"),
                            Node(1L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("y", "tag:yaml.org,2002:str"),
                            Node(2L, "tag:yaml.org,2002:int")
                        )
                    ],
                "tag:yaml.org,2002:map"),
                Node(
                    [
                        pair(
                            Node("x", "tag:yaml.org,2002:str"),
                            Node(0L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("y", "tag:yaml.org,2002:str"),
                            Node(2L, "tag:yaml.org,2002:int")
                        )
                    ],
                "tag:yaml.org,2002:map"),
                Node(
                    [
                        pair(
                            Node("r", "tag:yaml.org,2002:str"),
                            Node(10L, "tag:yaml.org,2002:int")
                        )
                    ],
                "tag:yaml.org,2002:map"),
                Node(
                    [
                        pair(
                            Node("r", "tag:yaml.org,2002:str"),
                            Node(1L, "tag:yaml.org,2002:int")
                        )
                    ],
                "tag:yaml.org,2002:map"),
                Node(
                    [
                        pair(
                            Node("x", "tag:yaml.org,2002:str"),
                            Node(1L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("y", "tag:yaml.org,2002:str"),
                            Node(2L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("r", "tag:yaml.org,2002:str"),
                            Node(10L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("label", "tag:yaml.org,2002:str"),
                            Node("center/big", "tag:yaml.org,2002:str")
                        )
                    ],
                "tag:yaml.org,2002:map"),
                Node(
                    [
                        pair(
                            Node("r", "tag:yaml.org,2002:str"),
                            Node(10L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("label", "tag:yaml.org,2002:str"),
                            Node("center/big", "tag:yaml.org,2002:str")
                        ),
                        pair(
                            Node("x", "tag:yaml.org,2002:str"),
                            Node(1L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("y", "tag:yaml.org,2002:str"),
                            Node(2L, "tag:yaml.org,2002:int")
                        )
                    ],
                "tag:yaml.org,2002:map"),
                Node(
                    [
                        pair(
                            Node("label", "tag:yaml.org,2002:str"),
                            Node("center/big", "tag:yaml.org,2002:str")
                        ),
                        pair(
                            Node("x", "tag:yaml.org,2002:str"),
                            Node(1L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("y", "tag:yaml.org,2002:str"),
                            Node(2L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("r", "tag:yaml.org,2002:str"),
                            Node(10L, "tag:yaml.org,2002:int")
                        )
                    ],
                "tag:yaml.org,2002:map"),
                Node(
                    [
                        pair(
                            Node("x", "tag:yaml.org,2002:str"),
                            Node(1L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("label", "tag:yaml.org,2002:str"),
                            Node("center/big", "tag:yaml.org,2002:str")
                        ),
                        pair(
                            Node("r", "tag:yaml.org,2002:str"),
                            Node(10L, "tag:yaml.org,2002:int")
                        ),
                        pair(
                            Node("y", "tag:yaml.org,2002:str"),
                            Node(2L, "tag:yaml.org,2002:int")
                        )
                    ],
                "tag:yaml.org,2002:map")
            ],
        "tag:yaml.org,2002:seq")
    ];
}

Node[] constructNull() @safe
{
    return [
        Node(YAMLNull(), "tag:yaml.org,2002:null"),
        Node(
            [
                pair(
                    Node("empty", "tag:yaml.org,2002:str"),
                    Node(YAMLNull(), "tag:yaml.org,2002:null")
                ),
                pair(
                    Node("canonical", "tag:yaml.org,2002:str"),
                    Node(YAMLNull(), "tag:yaml.org,2002:null")
                ),
                pair(
                    Node("english", "tag:yaml.org,2002:str"),
                    Node(YAMLNull(), "tag:yaml.org,2002:null")
                ),
                pair(
                    Node(YAMLNull(), "tag:yaml.org,2002:null"),
                    Node("null key", "tag:yaml.org,2002:str")
                )
            ],
        "tag:yaml.org,2002:map"),
        Node(
            [
                pair(
                    Node("sparse", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            Node(YAMLNull(), "tag:yaml.org,2002:null"),
                            Node("2nd entry", "tag:yaml.org,2002:str"),
                            Node(YAMLNull(), "tag:yaml.org,2002:null"),
                            Node("4th entry", "tag:yaml.org,2002:str"),
                            Node(YAMLNull(), "tag:yaml.org,2002:null")
                        ],
                    "tag:yaml.org,2002:seq")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructOMap() @safe
{
    return [
        Node(
            [
                pair(
                    Node("Bestiary", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            pair(
                                Node("aardvark", "tag:yaml.org,2002:str"),
                                Node("African pig-like ant eater. Ugly.", "tag:yaml.org,2002:str")
                            ),
                            pair(
                                Node("anteater", "tag:yaml.org,2002:str"),
                                Node("South-American ant eater. Two species.", "tag:yaml.org,2002:str")
                            ),
                            pair(
                                Node("anaconda", "tag:yaml.org,2002:str"),
                                Node("South-American constrictor snake. Scaly.", "tag:yaml.org,2002:str")
                            )
                        ],
                    "tag:yaml.org,2002:omap")
                ),
                pair(
                    Node("Numbers", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            pair(
                                Node("one", "tag:yaml.org,2002:str"),
                                Node(1L, "tag:yaml.org,2002:int")
                            ),
                            pair(
                                Node("two", "tag:yaml.org,2002:str"),
                                Node(2L, "tag:yaml.org,2002:int")
                            ),
                            pair(
                                Node("three", "tag:yaml.org,2002:str"),
                                Node(3L, "tag:yaml.org,2002:int")
                            )
                        ],
                    "tag:yaml.org,2002:omap")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructPairs() @safe
{
    return [
        Node(
            [
                pair(
                    Node("Block tasks", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            pair(Node("meeting", "tag:yaml.org,2002:str"), Node("with team.", "tag:yaml.org,2002:str")),
                            pair(Node("meeting", "tag:yaml.org,2002:str"), Node("with boss.", "tag:yaml.org,2002:str")),
                            pair(Node("break", "tag:yaml.org,2002:str"), Node("lunch.", "tag:yaml.org,2002:str")),
                            pair(Node("meeting", "tag:yaml.org,2002:str"), Node("with client.", "tag:yaml.org,2002:str"))
                        ],
                    "tag:yaml.org,2002:pairs")
                ),
                pair(
                    Node("Flow tasks", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            pair(Node("meeting", "tag:yaml.org,2002:str"), Node("with team", "tag:yaml.org,2002:str")),
                            pair(Node("meeting", "tag:yaml.org,2002:str"), Node("with boss", "tag:yaml.org,2002:str"))
                        ],
                    "tag:yaml.org,2002:pairs")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructSeq() @safe
{
    return [
        Node(
            [
                pair(
                    Node("Block style", "tag:yaml.org,2002:str"),
                    Node([
                          Node("Mercury", "tag:yaml.org,2002:str"),
                          Node("Venus", "tag:yaml.org,2002:str"),
                          Node("Earth", "tag:yaml.org,2002:str"),
                          Node("Mars", "tag:yaml.org,2002:str"),
                          Node("Jupiter", "tag:yaml.org,2002:str"),
                          Node("Saturn", "tag:yaml.org,2002:str"),
                          Node("Uranus", "tag:yaml.org,2002:str"),
                          Node("Neptune", "tag:yaml.org,2002:str"),
                          Node("Pluto", "tag:yaml.org,2002:str")
                    ], "tag:yaml.org,2002:seq")
                ),
                pair(
                    Node("Flow style", "tag:yaml.org,2002:str"),
                    Node([
                        Node("Mercury", "tag:yaml.org,2002:str"),
                        Node("Venus", "tag:yaml.org,2002:str"),
                        Node("Earth", "tag:yaml.org,2002:str"),
                        Node("Mars", "tag:yaml.org,2002:str"),
                        Node("Jupiter", "tag:yaml.org,2002:str"),
                        Node("Saturn", "tag:yaml.org,2002:str"),
                        Node("Uranus", "tag:yaml.org,2002:str"),
                        Node("Neptune", "tag:yaml.org,2002:str"),
                        Node("Pluto", "tag:yaml.org,2002:str")
                    ], "tag:yaml.org,2002:seq")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructSet() @safe
{
    return [
        Node(
            [
                pair(
                    Node("baseball players", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            Node("Mark McGwire", "tag:yaml.org,2002:str"),
                            Node("Sammy Sosa", "tag:yaml.org,2002:str"),
                            Node("Ken Griffey", "tag:yaml.org,2002:str")
                        ],
                    "tag:yaml.org,2002:set")
                ),
                pair(
                    Node("baseball teams", "tag:yaml.org,2002:str"),
                    Node(
                            [
                            Node("Boston Red Sox", "tag:yaml.org,2002:str"),
                            Node("Detroit Tigers", "tag:yaml.org,2002:str"),
                            Node("New York Yankees", "tag:yaml.org,2002:str")
                        ],
                    "tag:yaml.org,2002:set")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructStrASCII() @safe
{
    return [
        Node("ascii string", "tag:yaml.org,2002:str")
    ];
}

Node[] constructStr() @safe
{
    return [
        Node(
            [
                pair(
                    Node("string", "tag:yaml.org,2002:str"),
                    Node("abcd", "tag:yaml.org,2002:str")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructStrUTF8() @safe
{
    return [
        Node("\u042d\u0442\u043e \u0443\u043d\u0438\u043a\u043e\u0434\u043d\u0430\u044f \u0441\u0442\u0440\u043e\u043a\u0430", "tag:yaml.org,2002:str")
    ];
}

Node[] constructTimestamp() @safe
{
    return [
        Node(
            [
                pair(
                    Node("canonical", "tag:yaml.org,2002:str"),
                    Node(SysTime(DateTime(2001, 12, 15, 2, 59, 43), 1000000.dur!"hnsecs", UTC()), "tag:yaml.org,2002:timestamp")
                ),
                pair(
                    Node("valid iso8601", "tag:yaml.org,2002:str"),
                    Node(SysTime(DateTime(2001, 12, 15, 2, 59, 43), 1000000.dur!"hnsecs", UTC()), "tag:yaml.org,2002:timestamp")
                ),
                pair(
                    Node("space separated", "tag:yaml.org,2002:str"),
                    Node(SysTime(DateTime(2001, 12, 15, 2, 59, 43), 1000000.dur!"hnsecs", UTC()), "tag:yaml.org,2002:timestamp")
                ),
                pair(
                    Node("no time zone (Z)", "tag:yaml.org,2002:str"),
                    Node(SysTime(DateTime(2001, 12, 15, 2, 59, 43), 1000000.dur!"hnsecs", UTC()), "tag:yaml.org,2002:timestamp")
                ),
                pair(
                    Node("date (00:00:00Z)", "tag:yaml.org,2002:str"),
                    Node(SysTime(DateTime(2002, 12, 14), UTC()), "tag:yaml.org,2002:timestamp")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] constructValue() @safe
{
    return [
        Node(
            [
                pair(
                    Node("link with", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            Node("library1.dll", "tag:yaml.org,2002:str"),
                            Node("library2.dll", "tag:yaml.org,2002:str")
                        ],
                    "tag:yaml.org,2002:seq")
                )
            ],
        "tag:yaml.org,2002:map"),
        Node(
            [
                pair(
                    Node("link with", "tag:yaml.org,2002:str"),
                    Node(
                        [
                            Node(
                                [
                                    pair(
                                        Node("=", "tag:yaml.org,2002:value"),
                                        Node("library1.dll", "tag:yaml.org,2002:str")
                                    ),
                                    pair(
                                        Node("version", "tag:yaml.org,2002:str"),
                                        Node(1.2L, "tag:yaml.org,2002:float")
                                    )
                                ],
                            "tag:yaml.org,2002:map"),
                            Node(
                                [
                                    pair(
                                        Node("=", "tag:yaml.org,2002:value"),
                                        Node("library2.dll", "tag:yaml.org,2002:str")
                                    ),
                                    pair(
                                        Node("version", "tag:yaml.org,2002:str"),
                                        Node(2.3L, "tag:yaml.org,2002:float")
                                    )
                                ],
                            "tag:yaml.org,2002:map")
                        ],
                    "tag:yaml.org,2002:seq")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] duplicateMergeKey() @safe
{
    return [
        Node(
            [
                pair(
                    Node("foo", "tag:yaml.org,2002:str"),
                    Node("bar", "tag:yaml.org,2002:str")
                ),
                pair(
                    Node("x", "tag:yaml.org,2002:str"),
                    Node(1L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node("y", "tag:yaml.org,2002:str"),
                    Node(2L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node("z", "tag:yaml.org,2002:str"),
                    Node(3L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node("t", "tag:yaml.org,2002:str"),
                    Node(4L, "tag:yaml.org,2002:int")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] floatRepresenterBug() @safe
{
    return [
        Node(
            [
                pair(
                    Node(1.0L, "tag:yaml.org,2002:float"),
                    Node(1L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node(real.infinity, "tag:yaml.org,2002:float"),
                    Node(10L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node(-real.infinity, "tag:yaml.org,2002:float"),
                    Node(-10L, "tag:yaml.org,2002:int")
                ),
                pair(
                    Node(real.nan, "tag:yaml.org,2002:float"),
                    Node(100L, "tag:yaml.org,2002:int")
                )
            ],
        "tag:yaml.org,2002:map")
    ];
}

Node[] invalidSingleQuoteBug() @safe
{
    return [
        Node(
            [
                Node("foo \'bar\'", "tag:yaml.org,2002:str"),
                Node("foo\n\'bar\'", "tag:yaml.org,2002:str")
            ],
        "tag:yaml.org,2002:seq")
    ];
}

Node[] moreFloats() @safe
{
    return [
        Node(
            [
                Node(0.0L, "tag:yaml.org,2002:float"),
                Node(1.0L, "tag:yaml.org,2002:float"),
                Node(-1.0L, "tag:yaml.org,2002:float"),
                Node(real.infinity, "tag:yaml.org,2002:float"),
                Node(-real.infinity, "tag:yaml.org,2002:float"),
                Node(real.nan, "tag:yaml.org,2002:float"),
                Node(real.nan, "tag:yaml.org,2002:float")
            ],
        "tag:yaml.org,2002:seq")
    ];
}

Node[] negativeFloatBug() @safe
{
    return [
        Node(-1.0L, "tag:yaml.org,2002:float")
    ];
}

Node[] singleDotFloatBug() @safe
{
    return [
        Node(".", "tag:yaml.org,2002:str")
    ];
}

Node[] timestampBugs() @safe
{
    return [
        Node(
            [
                Node(SysTime(DateTime(2001, 12, 15, 3, 29, 43), 1000000.dur!"hnsecs", UTC()), "tag:yaml.org,2002:timestamp"),
                Node(SysTime(DateTime(2001, 12, 14, 16, 29, 43), 1000000.dur!"hnsecs", UTC()), "tag:yaml.org,2002:timestamp"),
                Node(SysTime(DateTime(2001, 12, 14, 21, 59, 43), 10100.dur!"hnsecs", UTC()), "tag:yaml.org,2002:timestamp"),
                Node(SysTime(DateTime(2001, 12, 14, 21, 59, 43), new immutable SimpleTimeZone(60.dur!"minutes")), "tag:yaml.org,2002:timestamp"),
                Node(SysTime(DateTime(2001, 12, 14, 21, 59, 43), new immutable SimpleTimeZone(-90.dur!"minutes")), "tag:yaml.org,2002:timestamp"),
                Node(SysTime(DateTime(2005, 7, 8, 17, 35, 4), 5176000.dur!"hnsecs", UTC()), "tag:yaml.org,2002:timestamp")
            ],
        "tag:yaml.org,2002:seq")
    ];
}

Node[] utf16be() @safe
{
    return [
        Node("UTF-16-BE", "tag:yaml.org,2002:str")
    ];
}

Node[] utf16le() @safe
{
    return [
        Node("UTF-16-LE", "tag:yaml.org,2002:str")
    ];
}

Node[] utf8() @safe
{
    return [
        Node("UTF-8", "tag:yaml.org,2002:str")
    ];
}

Node[] utf8implicit() @safe
{
    return [
        Node("implicit UTF-8", "tag:yaml.org,2002:str")
    ];
}

///Testing custom YAML class type.
class TestClass
{
    int x, y, z;

    this(int x, int y, int z) @safe
    {
        this.x = x;
        this.y = y;
        this.z = z;
    }

    Node opCast(T: Node)() @safe
    {
        return Node(
            [
                Node.Pair(
                    Node("x", "tag:yaml.org,2002:str"),
                    Node(x, "tag:yaml.org,2002:int")
                ),
                Node.Pair(
                    Node("y", "tag:yaml.org,2002:str"),
                    Node(y, "tag:yaml.org,2002:int")
                ),
                Node.Pair(
                    Node("z", "tag:yaml.org,2002:str"),
                    Node(z, "tag:yaml.org,2002:int")
                )
            ],
        "!tag1");
    }
}

///Testing custom YAML struct type.
struct TestStruct
{
    int value;

    this (int x) @safe
    {
        value = x;
    }

    ///Constructor function for TestStruct.
    this(ref Node node) @safe
    {
        value = node.as!string.to!int;
    }

    ///Representer function for TestStruct.
    Node opCast(T: Node)() @safe
    {
        return Node(value.to!string, "!tag2");
    }
}

/**
 * Constructor unittest.
 *
 * Params:  dataFilename = File name to read from.
 *          codeDummy    = Dummy .code filename, used to determine that
 *                         .data file with the same name should be used in this test.
 */
void testConstructor(string dataFilename, string codeDummy) @safe
{
    string base = dataFilename.baseName.stripExtension;
    enforce((base in expected) !is null,
            new Exception("Unimplemented constructor test: " ~ base));

    auto loader        = Loader.fromFile(dataFilename);

    Node[] exp = expected[base];

    //Compare with expected results document by document.
    size_t i;
    foreach(node; loader)
    {
        if(node != exp[i])
        {
            static if(verbose)
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


@safe unittest
{
    printProgress("D:YAML Constructor unittest");
    run("testConstructor", &testConstructor, ["data", "code"]);
}

} // version(unittest)
