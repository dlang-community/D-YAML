
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * Class and convenience functions used to load YAML documents.
 */
module dyaml.loader;


import std.exception;
import std.stream;

import dyaml.event;
import dyaml.node;
import dyaml.composer;
import dyaml.constructor;
import dyaml.resolver;
import dyaml.parser;
import dyaml.reader;
import dyaml.scanner;
import dyaml.token;
import dyaml.exception;


/**
 * Load single YAML document from a file.
 *
 * If there is no or more than one YAML document in the file, this will throw.
 * Use $(LREF loadAll) for such files.
 *
 * Params:  filename = Name of the file to _load from.
 *
 * Returns: Root node of the document.
 *
 * Throws:  YAMLException if there wasn't exactly one document in the file, 
 *          the file could not be opened or on a YAML parsing error.
 */
Node load(in string filename)
{
    auto loader = Loader(filename);
    return loader.loadSingleDocument();
}

/**
 * Load single YAML document from a stream.
 *
 * You can use this to e.g _load YAML from memory.
 *
 * If there is no or more than one YAML document in the stream, this will throw.
 * Use $(LREF loadAll) for such files.
 *
 * Params:  input = Stream to read from. Must be readable.
 *          name  = Name of the stream, used in error messages.
 *                  
 * Returns: Root node of the document.
 *
 * Throws:  YAMLException if there wasn't exactly one document in the stream, 
 *          the stream could not be read from or on a YAML parsing error.
 *
 * Examples:
 *
 * Loading YAML from memory:
 * --------------------
 * import std.stream;
 * import std.stdio;
 *
 * string yaml_input = "red:   '#ff0000'\n"
 *                     "green: '#00ff00'\n"
 *                     "blue:  '#0000ff'";
 *
 * auto colors = yaml.load(new MemoryStream(cast(char[])yaml_input));
 *
 * foreach(string color, string value; colors)
 * {
 *     writeln(color, " is ", value, " in HTML/CSS");
 * }
 * --------------------
 */
Node load(Stream input, in string name = "<unknown>")
{
    auto loader = Loader(input, name, new Constructor, new Resolver);
    return loader.loadSingleDocument();
}
unittest
{
    import std.stream;
    import std.stdio;

    string yaml_input = "red:   '#ff0000'\n"
                        "green: '#00ff00'\n"
                        "blue:  '#0000ff'";

    auto colors = load(new MemoryStream(cast(char[])yaml_input));

    foreach(string color, string value; colors)
    {
        writeln(color, " is ", value, " in HTML/CSS");
    }
}

/**
 * Load all YAML documents from a file.
 *
 * Params:  filename = Name of the file to load from.
 *
 * Returns: Array of root nodes of documents in the stream.
 *          If the stream is empty, empty array will be returned.
 *
 * Throws:  YAMLException if the file could not be opened or on a YAML parsing error.
 */
Node[] loadAll(in string filename)
{
    auto loader = Loader(filename);
    Node[] result;
    foreach(ref node; loader){result ~= node;}
    return result;
}


/**
 * Load all YAML documents from a stream.
 *
 * Params:  input = Stream to read from. Must be readable.
 *          name  = Name of the stream, used in error messages.
 *
 * Returns: Array of root nodes of documents in the file.
 *          If the file is empty, empty array will be returned.
 *
 * Throws:  YAMLException if the stream could not be read from or on a YAML parsing error.
 */
Node[] loadAll(Stream input, in string name = "<unknown>")
{
    auto loader = Loader(input, name, new Constructor, new Resolver);
    Node[] result;
    foreach(ref node; loader){result ~= node;}
    return result;
}

///Loads YAML documents from files or streams.
struct Loader
{
    private:
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
        ///Composes YAML nodes.
        Composer composer_;
        ///Name of the input file or stream, used in error messages.
        string name_;
        ///Input file stream, if the stream is created by Loader itself.
        File file_ = null;

    public:
        /**
         * Construct a Loader to load YAML from a file.
         *
         * Params:  filename = Name of the file to load from.
         *
         * Throws:  YAMLException if the file could not be opened or read from.
         */
        this(in string filename)
        {
            try{file_ = new File(filename);}
            catch(StreamException e)
            {
                throw new YAMLException("Unable to load YAML file " ~ filename ~ " : " ~ e.msg);
            }
            this(file_, filename, new Constructor, new Resolver);
        }
        
        /**
         * Construct a Loader to load YAML from a file, with provided _constructor and _resolver.
         *
         * Constructor and _resolver can be used to implement custom data types in YAML.
         *
         * Params:  filename    = Name of the file to load from.
         *          constructor = Constructor to use.
         *          resolver    = Resolver to use.
         *
         * Throws:  YAMLException if the file could not be opened or read from.
         */
        this(in string filename, Constructor constructor, Resolver resolver)
        {
            try{file_ = new File(filename);}
            catch(StreamException e)
            {
                throw new YAMLException("Unable to load YAML file " ~ filename ~ " : " ~ e.msg);
            }

            this(file_, filename, constructor, resolver);
        }
        
        /**
         * Construct a Loader to load YAML from a stream with provided _constructor and _resolver.
         *
         * Stream can be used to load YAML from memory and other sources.
         * Constructor and _resolver can be used to implement custom data types in YAML.
         *
         * Params:  input       = Stream to read from. Must be readable.
         *          name        = Name of the stream. Used in error messages.
         *          constructor = Constructor to use.
         *          resolver    = Resolver to use.
         *
         * Throws:  YAMLException if the stream could not be read from.
         */
        this(Stream input, in string name, Constructor constructor, Resolver resolver)
        {
            try
            {
                reader_      = new Reader(input);
                scanner_     = new Scanner(reader_);
                parser_      = new Parser(scanner_);
                resolver_    = resolver;
                constructor_ = constructor;
                composer_    = new Composer(parser_, resolver_, constructor_);
                name_ = name;
            }
            catch(YAMLException e)
            {
                e.name = name_;
                throw e;
            }
        }

        /**
         * Load single YAML document.
         *
         * If no or more than one YAML document is found, this will throw a YAMLException.
         *                  
         * Returns: Root node of the document.
         *
         * Throws:  YAMLException if there wasn't exactly one document
         *          or on a YAML parsing error.
         */
        Node loadSingleDocument()
        {
            try
            {
                enforce(composer_.checkNode(), new YAMLException("No YAML document to load"));
                return composer_.getSingleNode();
            }
            catch(YAMLException e)
            {
                e.name = name_;
                throw e;
            }
        }

        /**
         * Foreach over YAML documents.
         *
         * Parses documents lazily, as they are needed.
         *
         * Throws: YAMLException on a parsing error.
         */
        int opApply(int delegate(ref Node) dg)
        {
            try
            {
                int result = 0;
                while(composer_.checkNode())
                {
                    auto node = composer_.getNode();
                    result = dg(node);
                    if(result){break;}
                }

                return result;
            }
            catch(YAMLException e)
            {
                e.name = name_;
                throw e;
            }
        }

        ///Destroy the Loader.
        ~this()
        {
            clear(reader_);
            clear(scanner_);
            clear(parser_);
            clear(composer_);
            //Can't clear constructor, resolver: they might be supplied by the user.
            if(file_ !is null){file_.close();}
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
                e.name = name_;
                throw e;
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
                e.name = name_;
                throw e;
            }
        }
}
