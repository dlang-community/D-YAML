import std.stdio;
import std.string;
import dyaml;

struct Color
{
   ubyte red;
   ubyte green;
   ubyte blue;

   this(ubyte r, ubyte g, ubyte b) @safe
   {
        red = r;
        green = g;
        blue = b;
   }

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
}

void main(string[] args)
{
   auto red = Color(255, 0, 0);
   auto orange = Color(255, 255, 0);

   string path = "input.yaml";
   if (args.length > 1)
   {
        path = args[1];
   }

   try
   {
       auto root = Loader.fromFile(path).load();

       if(root["scalar-red"].as!Color     == red &&
          root["mapping-red"].as!Color    == red &&
          root["scalar-orange"].as!Color  == orange &&
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
