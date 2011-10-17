import std.ascii;
import std.stdio;
import std.string;
import yaml;

struct Color
{
   ubyte red;
   ubyte green;
   ubyte blue;
}

Color constructColorScalar(Mark start, Mark end, ref Node node)
{
    string value = node.get!string;

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

Color constructColorMapping(Mark start, Mark end, ref Node node)
{
    int r,g,b;
    bool error = false;

    //Might throw if a value is missing or is not an integer.
    try
    {
        r = node["r"].get!int;
        g = node["g"].get!int;
        b = node["b"].get!int;
    }
    catch(NodeException e)
    {
        error = true;
    }

    if(error || r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255)
    {
        throw new ConstructorException("Invalid color", start, end);
    }

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
       resolver.addImplicitResolver("!color", std.regex.regex("[0-9a-fA-F]{6}"),
                                    "0123456789abcdefABCDEF");
       
       auto loader = Loader("input.yaml");
       loader.constructor = constructor;
       loader.resolver = resolver;

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
