
///Example D:YAML application that displays statistics about YAML documents.

import std.stdio;
import std.string;
import dyaml;


///Collects statistics about a YAML document and returns them as string.
string statistics(ref Node document)
{
    size_t nodes;
    size_t scalars, sequences, mappings;
    size_t seqItems, mapPairs;

    size_t[string] tags;

    void crawl(ref Node root)
    {
        ++nodes;
        if((root.tag in tags) is null)
        {
            tags[root.tag] = 0;
        }
        ++tags[root.tag];
        final switch (root.nodeID)
        {
            case NodeID.scalar:
                ++scalars;
                return;
            case NodeID.sequence:
                ++sequences;
                seqItems += root.length;
                foreach(ref Node node; root)
                {
                    crawl(node);
                }
                return;
            case NodeID.mapping:
                ++mappings;
                mapPairs += root.length;
                foreach(ref Node key, ref Node value; root)
                {
                    crawl(key);
                    crawl(value);
                }
                return;
            case NodeID.invalid:
                assert(0);
        }
    }

    crawl(document);

    string tagStats = "\nTag statistics:\n";
    foreach(tag, count; tags)
    {
        tagStats ~= format("\n%s : %s", tag, count);
    }

    return format(  "\nNodes:                   %s" ~
                  "\n\nScalars:                 %s" ~
                    "\nSequences:               %s" ~
                    "\nMappings:                %s" ~
                  "\n\nAverage sequence length: %s" ~
                    "\nAverage mapping length:  %s" ~
                  "\n\n%s",
                  nodes, scalars, sequences, mappings,
                  sequences == 0.0 ? 0.0 : cast(real)seqItems / sequences,
                  mappings  == 0.0 ? 0.0 : cast(real)mapPairs / mappings,
                  tagStats);
}

void main(string[] args)
{
    //Help message
    if(args.length == 1)
    {
        writeln("Usage: yaml_stats [YAML_FILE ...]\n");
        writeln("Analyzes YAML files with provided filenames and displays statistics.");
        return;
    }

    //Print stats about every document in every file.
    foreach(file; args[1 .. $])
    {
        writeln("\nFile ", file);
        writeln("------------------------------------------------------------");
        try
        {
            auto loader = Loader.fromFile(file);

            size_t idx = 0;
            foreach(ref document; loader)
            {
                writeln("\nDocument ", idx++);
                writeln("----------------------------------------");
                writeln(statistics(document));
            }
        }
        catch(YAMLException e)
        {
            writeln("ERROR: ", e.msg);
        }
    }
}
