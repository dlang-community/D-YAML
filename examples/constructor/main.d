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

       auto loader = new Loader("input.yaml", constructor, new Resolver);

       auto root = loader.loadSingleDocument();

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
