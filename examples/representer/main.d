import std.stdio;
import dyaml;

struct Color
{
   ubyte red;
   ubyte green;
   ubyte blue;

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
}

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
