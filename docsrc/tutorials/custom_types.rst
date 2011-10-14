======================
Custom YAML data types
======================

Often you might want to serialize complex data types such as classes. You can 
use functions to process nodes such as a mapping containing class data members 
indexed by name. Alternatively, YAML supports custom data types using 
identifiers called *tags*. That is the topic of this tutorial.

Each YAML node has a tag specifying its type. For instance: strings use the tag 
``tag:yaml.org,2002:str``. Tags of most default types are *implicitly resolved* 
during parsing, so you don't need to specify tag for each float, integer, etc.
It is also possible to implicitly resolve custom tags, as we will show later.


-----------
Constructor
-----------

D:YAML uses the *Constructor* class to process each node to hold data type
corresponding to its tag. *Constructor* stores a function for each supported 
tag to process it. These functions are supplied by the user using the 
*addConstructor()* method. *Constructor* is then passed to *Loader*, which 
parses YAML input.

We will implement support for an RGB color type. It is implemented as the 
following struct:

.. code-block:: d
    
   struct Color
   {
       ubyte red;
       ubyte green;
       ubyte blue;
   }

First, we need a function to construct our data type. It must take two *Mark* 
structs, which store position of the node in the file, and either a *string*, an
array of *Node* or of *Node.Pair*, depending on whether we're constructing our 
value from a scalar, sequence, or mapping, respectively. In this tutorial, we 
have functions to construct a color from a scalar, using HTML-like format, 
RRGGBB, or from a mapping, where we use the following format: 
{r:RRR, g:GGG, b:BBB} . Code of these functions:

.. code-block:: d

   Color constructColorScalar(Mark start, Mark end, string value)
   {
       if(value.length != 6)
       {
           throw new ConstructorException("Invalid color: " ~ value, start, end);
       }
       //We don't need to check for uppercase chars this way.
       value = value.toLower();

       //Get value of a hex digit.
       uint hex(char c)
       {
           if(!std.ascii.isHexDigit(c))
           {
               throw new ConstructorException("Invalid color: " ~ value, start, end);
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

   Color constructColorMapping(Mark start, Mark end, Node.Pair[] pairs)
   {
       int r, g, b;
       r = g = b = -1;
       bool error = pairs.length != 3;

       foreach(ref pair; pairs)
       {
           //Key might not be a string, and value might not be an int,
           //so we need to check for that
           try
           {
               switch(pair.key.get!string)
               {
                   case "r": r = pair.value.get!int; break;
                   case "g": g = pair.value.get!int; break;
                   case "b": b = pair.value.get!int; break;
                   default:  error = true;
               }
           }
           catch(NodeException e)
           {
               error = true;
           }
       }

       if(error || r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255)
       {
           throw new ConstructorException("Invalid color", start, end);
       }

       return Color(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b);
   }

Next, we need some YAML data using our new tag. Create a file called input.yaml 
with the following contents:

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
           constructor.addConstructor("!color", &constructColorScalar);
           constructor.addConstructor("!color-mapping", &constructColorMapping);

           auto loader = Loader("input.yaml");
           loader.constructor = constructor;

           auto root = loader.load();

           if(root["scalar-red"].get!Color == red && 
              root["mapping-red"].get!Color == red && 
              root["scalar-orange"].get!Color == orange && 
              root["mapping-orange"].get!Color == orange)
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
and ``!color-mapping`` tag. We construct a *Loader*m and pass the *Constructor*
to it. We then load the YAML document, and finally, read the colors using 
*get()* method to test if they were loaded as expected.

You can find the source code for what we've done so far in the 
``examples/constructor`` directory in the D:YAML package.


--------
Resolver
--------

Specifying tag for every color value can be tedious. D:YAML can implicitly 
resolve scalar tags using regular expressions. This is how default types such as
int are resolved. We will use the *Resolver* class to add implicit tag 
resolution for the Color data type (in its scalar form).

We use the *addImplicitResolver* method of *Resolver*, passing the tag, regular
expression the value must match to resolve to this tag, and a string of possible
starting characters of the value. Then we pass the *Resolver* to *Loader*.

Note that resolvers added first override ones added later. If no resolver 
matches a scalar, YAML string tag is used. Therefore our custom values must not 
be resolvable as any non-string YAML data type.

Add this to your code to add implicit resolution of ``!color``.

.. code-block:: d

   //code from the previous example...

   auto resolver = new Resolver;
   resolver.addImplicitResolver("!color", std.regex.regex("[0-9a-fA-F]{6}",
                                "0123456789abcdefABCDEF"));
   
   auto loader = Loader("input.yaml");
   
   loader.constructor = constructor;
   loader.resolver = resolver;

   //code from the previous example...

Now, change contents of input.yaml to this:

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
