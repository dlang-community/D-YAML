import std.stdio;
import yaml;

void main()
{
    yaml.Node root = yaml.load("input.yaml");
    foreach(string word; root["Hello World"])
    {
        writeln(word);
    }
    writeln("The answer is ", root["Answer"].get!int);
}
