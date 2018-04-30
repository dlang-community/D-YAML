import std.stdio;
import std.string;
import dyaml;

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

Color constructColorScalar(ref Node node) @safe
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

Color constructColorMapping(ref Node node) @safe
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

       auto resolver = new Resolver;
       import std.regex;
       resolver.addImplicitResolver("!color", std.regex.regex("[0-9a-fA-F]{6}"),
                                    "0123456789abcdefABCDEF");

       auto loader = Loader("input.yaml");
       loader.constructor = constructor;
       loader.resolver = resolver;

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
