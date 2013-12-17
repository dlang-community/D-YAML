import std.stdio;
import dyaml.all;

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
