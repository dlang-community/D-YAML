
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * Class used to load YAML documents.
 */
module dyaml.loader;


import std.exception;
import std.stream;

import dyaml.anchor;
import dyaml.composer;
import dyaml.constructor;
import dyaml.event;
import dyaml.exception;
import dyaml.node;
import dyaml.parser;
import dyaml.reader;
import dyaml.resolver;
import dyaml.scanner;
import dyaml.tagdirectives;
import dyaml.token;


/**
 * Loads YAML documents from files or streams.
 *
 * User specified Constructor and/or Resolver can be used to support new
 * tags / data types.
 *
 * Examples:
 *
 * Load single YAML document from a file:
 * --------------------
 * auto rootNode = Loader("file.yaml").load();
 * ...
 * --------------------
 *
 * Load all YAML documents from a file:
 * --------------------
 * auto nodes = Loader("file.yaml").loadAll();
 * ...
 * --------------------
 *
 * Iterate over YAML documents in a file, lazily loading them:
 * --------------------
 * auto loader = Loader("file.yaml");
 * 
 * foreach(ref node; loader)
 * {
 *     ...
 * }
 * --------------------
 * 
 * Load YAML from memory:
 * --------------------
 * import std.stream;
 * import std.stdio;
 *
 * string yaml_input = "red:   '#ff0000'\n"
 *                     "green: '#00ff00'\n"
 *                     "blue:  '#0000ff'";
 *
 * auto colors = Loader(new MemoryStream(cast(char[])yaml_input)).load();
 *
 * foreach(string color, string value; colors)
 * {
 *     writeln(color, " is ", value, " in HTML/CSS");
 * }
 * --------------------
 *
 * Use a custom constructor/resolver to support custom data types and/or implicit tags:
 * --------------------
 * auto constructor = new Constructor();
 * auto resolver = new Resolver();
 *
 * //Add constructor functions / resolver expressions here...
 *
 * auto loader = Loader("file.yaml");
 * loader.constructor = constructor;
 * loader.resolver = resolver;
 * auto rootNode = loader.load(node);
 * --------------------
 */
struct Loader
{
    private:
        ///Resolver used by default.
        static Resolver defaultResolver_;
        ///Constructor used by default.
        static Constructor defaultConstructor_;

        static this()
        {
            defaultResolver_ = new Resolver;
            defaultConstructor_ = new Constructor;
        }


        ///Reads character data from a stream.
        Reader reader_;
        ///Processes character data to YAML tokens.
        Scanner scanner_;
        ///Processes tokens to YAML events.
        Parser parser_;
        ///Resolves tags (data types).
        Resolver resolver_;
        ///Constructs YAML data types.
        Constructor constructor_;
        ///Name of the input file or stream, used in error messages.
        string name_ = "<unknown>";

    public:
        @disable this();
        @disable int opCmp(ref Loader);
        @disable bool opEquals(ref Loader);

        /**
         * Construct a Loader to load YAML from a file.
         *
         * Params:  filename = Name of the file to load from.
         *
         * Throws:  YAMLException if the file could not be opened or read.
         */
        this(in string filename)
        {
            name_ = filename;
            try{this(new File(filename));}
            catch(StreamException e)
            {
                throw new YAMLException("Unable to open file " ~ filename ~ 
                                        " for YAML loading: " ~ e.msg);
            }
        }
        
        /**
         * Construct a Loader to load YAML from a _stream.
         *
         * Params:  stream = Stream to read from. Must be readable and seekable.
         *
         * Throws:  YAMLException if stream could not be read.
         */
        this(Stream stream)
        {
            try
            {
                reader_      = new Reader(stream);
                scanner_     = new Scanner(reader_);
                parser_      = new Parser(scanner_);
                resolver_    = defaultResolver_;
                constructor_ = defaultConstructor_;
                Anchor.addReference();
                TagDirectives.addReference();
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to open stream " ~ name_ ~ 
                                        " for YAML loading: " ~ e.msg);
            }
        }

        ///Destroy the Loader.
        ~this()
        {
            Anchor.removeReference();
            TagDirectives.removeReference();
            clear(reader_);
            clear(scanner_);
            clear(parser_);
        }

        ///Set stream _name. Used in debugging messages.
        @property void name(string name)
        {
            name_ = name;
        }

        ///Specify custom Resolver to use.
        @property void resolver(Resolver resolver)
        {
            resolver_ = resolver;
        }

        ///Specify custom Constructor to use.
        @property void constructor(Constructor constructor)
        {
            constructor_ = constructor;
        }

        /**
         * Load single YAML document.
         *
         * If none or more than one YAML document is found, this throws a YAMLException.
         *                  
         * Returns: Root node of the document.
         *
         * Throws:  YAMLException if there wasn't exactly one document
         *          or on a YAML parsing error.
         */
        Node load()
        {
            try
            {
                auto composer = new Composer(parser_, resolver_, constructor_);
                enforce(composer.checkNode(), new YAMLException("No YAML document to load"));
                return composer.getSingleNode();
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to load YAML from stream " ~ 
                                        name_ ~ " : " ~ e.msg);
            }
        }

        /**
         * Load all YAML documents.
         *
         * This is just a shortcut that iterates over all documents and returns
         * them all at once. Calling loadAll after iterating over the node or
         * vice versa will not return any documents, as they have all been parsed
         * already.
         *                  
         * Returns: Array of root nodes of all documents in the file/stream.
         *
         * Throws:  YAMLException on a parsing error.
         */
        Node[] loadAll()
        {
            Node[] nodes;
            foreach(ref node; this){nodes ~= node;}
            return nodes;
        }

        /**
         * Foreach over YAML documents.
         *
         * Parses documents lazily, when they are needed.
         *
         * Throws: YAMLException on a parsing error.
         */
        int opApply(int delegate(ref Node) dg)
        {
            try
            {
                auto composer = new Composer(parser_, resolver_, constructor_);

                int result = 0;
                while(composer.checkNode())
                {
                    auto node = composer.getNode();
                    result = dg(node);
                    if(result){break;}
                }

                return result;
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to load YAML from stream " ~ 
                                        name_ ~ " : " ~ e.msg);
            }
        }

    package:
        //Scan and return all tokens. Used for debugging.
        Token[] scan()
        {
            try
            {
                Token[] result;
                while(scanner_.checkToken()){result ~= scanner_.getToken();}
                return result;
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to scan YAML from stream " ~ 
                                        name_ ~ " : " ~ e.msg);
            }
        }

        //Parse and return all events. Used for debugging.
        Event[] parse()
        {
            try
            {
                Event[] result;
                while(parser_.checkEvent()){result ~= parser_.getEvent();}
                return result;
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to parse YAML from stream " ~ 
                                        name_ ~ " : " ~ e.msg);
            }
        }
}

unittest
{
    import std.stream;
    import std.stdio;
    
    string yaml_input = "red:   '#ff0000'\n"
                        "green: '#00ff00'\n"
                        "blue:  '#0000ff'";
    
    auto colors = Loader(new MemoryStream(cast(char[])yaml_input)).load();
    
    foreach(string color, string value; colors)
    {
        writeln(color, " is ", value, " in HTML/CSS");
    }
}
