import std.regex;
import std.stdio;
import dyaml;

int main(string[] args)
{
    string path = "input.yaml";
    if (args.length > 1)
    {
        path = args[1];
    }

    try
    {

        auto loader = Loader.fromFile("input.yaml");
        loader.resolver.addImplicitResolver("!color", regex("[0-9a-fA-F]{6}"),
            "0123456789abcdefABCDEF");

        auto root = loader.load();

        if(root["scalar-red"].tag == "!color" &&
            root["scalar-orange"].tag == "!color")
        {
            writeln("SUCCESS");
            return 0;
        }
    }
    catch(YAMLException e)
    {
        writeln(e.msg);
    }

    writeln("FAILURE");
    return 1;
}
