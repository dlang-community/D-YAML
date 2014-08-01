======================
Custom YAML data types
======================

Sometimes you need to serialize complex data types such as classes. To do this
you could use plain nodes such as mappings with classes' fields. YAML also 
supports custom types with identifiers called *tags*. That is the topic of this 
tutorial.

Each YAML node has a tag specifying its type. For instance: strings use the tag 
``tag:yaml.org,2002:str``. Tags of most default types are *implicitly resolved* 
during parsing - you don't need to specify tag for each float, integer, etc.
D:YAML can also implicitly resolve custom tags, as we will show later.


-----------
Constructor
-----------

D:YAML uses the `Constructor <../api/dyaml.constructor.html>`_ class to process
each node to hold data type corresponding to its tag. *Constructor* stores
functions to process each supported tag. These are supplied by the user using 
the *addConstructorXXX()* methods, where *XXX* is *Scalar*, *Sequence* or 
*Mapping*. *Constructor* is then passed to *Loader*, which parses YAML input.

Structs and classes must implement the *opCmp()* operator for YAML support. This 
is used for duplicate detection in mappings, sorting and equality comparisons of
nodes. The signature of the operator that must be implemented is 
``const int opCmp(ref const MyStruct s)`` for structs where *MyStruct* is the 
struct type, and ``int opCmp(Object o)`` for classes. Note that the class 
*opCmp()* should not alter the compared values - it is not const for compatibility 
reasons. 

We will implement support for an RGB color type. It is implemented as the 
following struct:

.. code-block:: d
    
   struct Color
   {
       ubyte red;
       ubyte green;
       ubyte blue;

       const int opCmp(ref const Color c)
       {
           if(red   != c.red)  {return red   - c.red;}
           if(green != c.green){return green - c.green;}
           if(blue  != c.blue) {return blue  - c.blue;}
           return 0;
       }
   }

First, we need a function to construct our data type. The function will take a 
reference to *Node* to construct from. The node is guaranteed to contain either 
a *string*, an array of *Node* or of *Node.Pair*, depending on whether we're 
constructing our value from a scalar, sequence, or mapping, respectively. 
If this function throws any exception, D:YAML handles it and adds its message 
to a *YAMLException* that will be thrown when loading the file. 

In this tutorial, we have functions to construct a color from a scalar, using 
CSS-like format, RRGGBB, or from a mapping, where we use the following format:
{r:RRR, g:GGG, b:BBB} . Code of these functions:

.. code-block:: d

   Color constructColorScalar(ref Node node)
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

       Color result;
       result.red   = cast(ubyte)(16 * hex(value[0]) + hex(value[1]));
       result.green = cast(ubyte)(16 * hex(value[2]) + hex(value[3]));
       result.blue  = cast(ubyte)(16 * hex(value[4]) + hex(value[5]));

       return result;
   }

   Color constructColorMapping(ref Node node)
   {
       ubyte r,g,b;
   
       //Might throw if a value is missing is not an integer, or is out of range.
       //If this happens, D:YAML will handle the exception and use its message
       //in a YAMLException thrown when loading.
       r = node["r"].as!ubyte;
       g = node["g"].as!ubyte;
       b = node["b"].as!ubyte;
   
       return Color(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b);
   }
   
Next, we need some YAML data using our new tag. Create a file called 
``input.yaml`` with the following contents:

.. code-block:: yaml

   scalar-red: !color FF0000
   scalar-orange: !color FFFF00
   mapping-red: !color-mapping {r: 255, g: 0, b: 0}
   mapping-orange:
       !color-mapping
       r: 255
       g: 255
       b: 0

You can see that we're using tag ``!color`` for scalar colors, and 
``!color-mapping`` for colors expressed as mappings. 

Finally, the code to put it all together:

.. code-block:: d
   
   void main()
   {
       auto red    = Color(255, 0, 0);
       auto orange = Color(255, 255, 0);

       try
       {
           auto constructor = new Constructor;
           //both functions handle the same tag, but one handles scalar, one mapping.
           constructor.addConstructorScalar("!color", &constructColorScalar);
           constructor.addConstructorMapping("!color-mapping", &constructColorMapping);

           auto loader = Loader("input.yaml");
           loader.constructor = constructor;

           auto root = loader.load();

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

First, we create a *Constructor* and pass functions to handle the ``!color`` 
and ``!color-mapping`` tag. We construct a *Loader* and pass the *Constructor*
to it. We then load the YAML document, and finally, read the colors to test if
they were loaded as expected.

You can find the source code for what we've done so far in the 
``examples/constructor`` directory in the D:YAML package.


--------
Resolver
--------

Specifying tag for every color can be tedious. D:YAML can implicitly resolve 
scalar tags using regular expressions. This is how default types are resolved.
We will use the `Resolver <../api/dyaml.resolver.html>`_ class to add implicit
tag resolution for the Color data type (in its scalar form).

We use the *addImplicitResolver()* method of *Resolver*, passing the tag, 
regular expression the scalar must match to resolve to this tag, and a string of
possible starting characters of the scalar. Then we pass the *Resolver* to 
*Loader*.

Note that resolvers added first override ones added later. If no resolver 
matches a scalar, YAML string tag is used. Therefore our custom values must not 
be resolvable as any non-string YAML data type.

Add this to your code to add implicit resolution of ``!color``.

.. code-block:: d

   //code from the previous example...

   auto resolver = new Resolver;
   resolver.addImplicitResolver("!color", std.regex.regex("[0-9a-fA-F]{6}"),
                                "0123456789abcdefABCDEF");
   
   auto loader = Loader("input.yaml");
   
   loader.constructor = constructor;
   loader.resolver = resolver;

   //code from the previous example...

Now, change contents of ``input.yaml`` to this:

.. code-block:: yaml

   scalar-red: FF0000
   scalar-orange: FFFF00
   mapping-red: !color-mapping {r: 255, g: 0, b: 0}
   mapping-orange:
       !color-mapping
       r: 255
       g: 255
       b: 0

We no longer need to specify the tag for scalar color values. Compile and test 
the example. If everything went as expected, it should report success. 

You can find the complete code in the ``examples/resolver`` directory in the 
D:YAML package.


-----------
Representer
-----------

Now that you can load custom data types, it might be good to know how to dump 
them. D:YAML uses the `Representer <../api/dyaml.representer.html>`_ class for 
this purpose.

*Representer* processes YAML nodes into plain mapping, sequence or scalar nodes
ready for output. Just like with *Constructor*, this is done by user specified 
functions. These functions take references to a node to process and to the 
*Representer*, and return the processed node. 

Representer functions can be added with the *addRepresenter()* method. The 
*Representer* is then passed to *Dumper*, which dumps YAML documents. Only one
function per type can be specified. This is asserted in *addRepresenter()*
preconditions. Default YAML types already have representer functions specified, 
but you can disable them by constructing *Representer* with the
*useDefaultRepresenters* parameter set to false.

By default, tags are explicitly output for all non-default types. To make dumped
tags implicit, you can pass a *Resolver* that will resolve them implicitly. Of 
course, you will need to use an identical *Resolver* when loading the output.

With the following code, we will add support for dumping the our Color type.

.. code-block:: d

   Node representColor(ref Node node, Representer representer)
   {
       //The node is guaranteed to be Color as we add representer for Color.
       Color color = node.as!Color;

       static immutable hex = "0123456789ABCDEF";

       //Using the color format from the Constructor example.
       string scalar;
       foreach(channel; [color.red, color.green, color.blue])
       {
           scalar ~= hex[channel / 16]; 
           scalar ~= hex[channel % 16];
       }

       //Representing as a scalar, with custom tag to specify this data type.
       return representer.representScalar("!color", scalar);
   }

First we get the *Color* from the node. Then we convert it to a string with the
CSS-like format we've used before. Finally, we use the *representScalar()* 
method of *Representer* to get a scalar node ready for output. There are 
corresponding *representMapping()* and *representSequence()* methods
as well, with examples in the 
`Resolver API documentation <../api/dyaml.resolver.html>`_. 

Since a type can only have one representer function, we don't dump *Color* both 
in the scalar and mapping formats we've used before. However, you can decide to
dump the node with different formats/tags in the representer function itself. 
E.g. you could dump the Color as a mapping based on some arbitrary condition, 
such as the color being white.

.. code-block:: d

   void main()
   {
       try
       {
           auto representer = new Representer;
           representer.addRepresenter!Color(&representColor);

           auto resolver = new Resolver;
           resolver.addImplicitResolver("!color", std.regex.regex("[0-9a-fA-F]{6}"),
                                        "0123456789abcdefABCDEF");

           auto dumper = Dumper("output.yaml");
           dumper.representer = representer;
           dumper.resolver    = resolver;

           auto document = Node([Color(255, 0, 0), 
                                 Color(0, 255, 0), 
                                 Color(0, 0, 255)]);

           dumper.dump(document);
       }
       catch(YAMLException e)
       {
           writeln(e.msg);
       }
   }

We construct a new *Representer*, and specify a representer function for the 
*Color* (the template argument) type. We also construct a *Resolver*, same as in
the previous section, so the ``!color`` tag will be implicit. Of course,
identical *Resolver* would then have to be used when loading the file.
You don't need to do this if you want the tag to be explicit.

We construct a *Dumper* to file ``output.yaml`` and pass the *Representer* and 
*Resolver* to it. Then, we create a simple node containing a sequence of colors 
and finally, we dump it.

Source code for this section can be found in the ``examples/representer`` 
directory of the D:YAML package.
