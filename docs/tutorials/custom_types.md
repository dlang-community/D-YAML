# Custom YAML data types

Sometimes you need to serialize complex data types such as classes. To
do this you could use plain nodes such as mappings with classes' fields.
YAML also supports custom types with identifiers called *tags*. That is
the topic of this tutorial.

Each YAML node has a tag specifying its type. For instance: strings use
the tag `tag:yaml.org,2002:str`. Tags of most default types are
*implicitly resolved* during parsing - you don't need to specify tag for
each float, integer, etc. D:YAML can also implicitly resolve custom
tags, as we will show later.

## Constructor

D:YAML supports conversion to user-defined types. Adding a constructor to read
the data from the node is all that is needed.

We will implement support for an RGB color type. It is implemented as
the following struct:

```D
struct Color
{
    ubyte red;
    ubyte green;
    ubyte blue;
}
```

First, we need our type to have an appropriate constructor. The constructor
will take a const *Node* to construct from. The node is guaranteed to
contain either a *string*, an array of *Node* or of *Node.Pair*,
depending on whether we're constructing our value from a scalar,
sequence, or mapping, respectively.

In this tutorial, we have a constructor to construct a color from a scalar,
using CSS-like format, RRGGBB, or from a mapping, where we use the
following format: {r:RRR, g:GGG, b:BBB} . Code of these functions:

```D

this(const Node node, string tag) @safe
{
     if (tag == "!color-mapping")
     {
         //Will throw if a value is missing, is not an integer, or is out of range.
         red = node["r"].as!ubyte;
         green = node["g"].as!ubyte;
         blue = node["b"].as!ubyte;
     }
     else
     {
         string value = node.as!string;

         if(value.length != 6)
         {
             throw new Exception("Invalid color: " ~ value);
         }
         //We don't need to check for uppercase chars this way.
         value = value.toLower();

         //Get value of a hex digit.
         uint hex(char c)
         {
             import std.ascii;
             if(!std.ascii.isHexDigit(c))
             {
                 throw new Exception("Invalid color: " ~ value);
             }

             if(std.ascii.isDigit(c))
             {
                 return c - '0';
             }
             return c - 'a' + 10;
         }

         red   = cast(ubyte)(16 * hex(value[0]) + hex(value[1]));
         green = cast(ubyte)(16 * hex(value[2]) + hex(value[3]));
         blue  = cast(ubyte)(16 * hex(value[4]) + hex(value[5]));
     }
}
```

Next, we need some YAML data using our new tag. Create a file called
`input.yaml` with the following contents:

```YAML
scalar-red: !color FF0000
scalar-orange: !color FFFF00
mapping-red: !color-mapping {r: 255, g: 0, b: 0}
mapping-orange:
    !color-mapping
    r: 255
    g: 255
    b: 0
```

You can see that we're using tag `!color` for scalar colors, and
`!color-mapping` for colors expressed as mappings.

Finally, the code to put it all together:

```D
void main()
{
    auto red    = Color(255, 0, 0);
    auto orange = Color(255, 255, 0);

    try
    {
        auto root = Loader.fromFile("input.yaml").load();

        if(root["scalar-red"].as!Color == red &&
           root["mapping-red"].as!Color == red &&
           root["scalar-orange"].as!Color == orange &&
           root["mapping-orange"].as!Color == orange)
        {
            writeln("SUCCESS");
            return;
        }
    }
    catch(YAMLException e)
    {
        writeln(e.msg);
    }

    writeln("FAILURE");
}
```

First we load the YAML document, and then have the resulting *Node*s converted
to Colors via their constructor.

You can find the source code for what we've done so far in the
`examples/constructor` directory in the D:YAML package.

## Resolver

Specifying tag for every color can be tedious. D:YAML can implicitly
resolve scalar tags using regular expressions. This is how default types
are resolved. We will use the [Resolver](../api/dyaml.resolver.html)
class to add implicit tag resolution for the Color data type (in its
scalar form).

We use the *addImplicitResolver()* method of *Resolver*, passing the
tag, regular expression the scalar must match to resolve to this tag,
and a string of possible starting characters of the scalar. Then we pass
the *Resolver* to *Loader*.

Note that resolvers added first override ones added later. If no
resolver matches a scalar, YAML string tag is used. Therefore our custom
values must not be resolvable as any non-string YAML data type.

Add this to your code to add implicit resolution of `!color`.

```D
import std.regex;
auto resolver = new Resolver;
resolver.addImplicitResolver("!color", regex("[0-9a-fA-F]{6}"),
                             "0123456789abcdefABCDEF");

auto loader = Loader.fromFile("input.yaml");

loader.resolver = resolver;
```

Now, change contents of `input.yaml` to this:

```YAML
scalar-red: FF0000
scalar-orange: FFFF00
mapping-red: !color-mapping {r: 255, g: 0, b: 0}
mapping-orange:
    !color-mapping
    r: 255
    g: 255
    b: 0
```

We no longer need to specify the tag for scalar color values. Compile
and test the example. If everything went as expected, it should report
success.

You can find the complete code in the `examples/resolver` directory in
the D:YAML package.

## Representer

Now that you can load custom data types, it might be good to know how to
dump them.

The *Node* struct simply attempts to cast all unrecognized types to *Node*.
This gives each type a consistent and simple way of being represented in a
document. All we need to do is specify a `Node opCast(T: Node)()` method for
any types we wish to support. It is also possible to specify specific styles
for each representation.

Each type may only have one opCast!Node. Default YAML types are already
supported.

With the following code, we will add support for dumping the our Color
type.

```D
Node opCast(T: Node)() const
{
    static immutable hex = "0123456789ABCDEF";

    //Using the color format from the Constructor example.
    string scalar;
    foreach(channel; [red, green, blue])
    {
        scalar ~= hex[channel / 16];
        scalar ~= hex[channel % 16];
    }

    //Representing as a scalar, with custom tag to specify this data type.
    return Node(scalar, "!color");
}
```

First we convert the colour data to a string with the CSS-like format we've
used before. Then, we create a scalar *Node* with our desired tag.

Since a type can only have one opCast!Node method, we don't dump
*Color* both in the scalar and mapping formats we've used before.
However, you can decide to dump the node with different formats/tags in
the method itself. E.g. you could dump the Color as a
mapping based on some arbitrary condition, such as the color being
white.

```D
void main()
{
    try
    {
        auto dumper = dumper();

        auto document = Node([Color(255, 0, 0),
                              Color(0, 255, 0),
                              Color(0, 0, 255)]);

        dumper.dump(File("output.yaml", "w").lockingTextWriter, document);
    }
    catch(YAMLException e)
    {
        writeln(e.msg);
    }
}
```

We construct a *Dumper* to file `output.yaml`. Then, we create a simple node
containing a sequence of colors and finally, we dump it.

Source code for this section can be found in the `examples/representer`
directory of the D:YAML package.
