
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Class used to load YAML documents.
module dyaml.loader;


import std.exception;
import std.file;
import std.string;

import dyaml.composer;
import dyaml.constructor;
import dyaml.event;
import dyaml.exception;
import dyaml.node;
import dyaml.parser;
import dyaml.reader;
import dyaml.resolver;
import dyaml.scanner;
import dyaml.token;


/** Loads YAML documents from files or char[].
 *
 * User specified Constructor and/or Resolver can be used to support new
 * tags / data types.
 */
struct Loader
{
    private:
        // Reads character data from a stream.
        Reader reader_;
        // Processes character data to YAML tokens.
        Scanner scanner_;
        // Processes tokens to YAML events.
        Parser parser_;
        // Resolves tags (data types).
        Resolver resolver_;
        // Constructs YAML data types.
        Constructor constructor_;
        // Name of the input file or stream, used in error messages.
        string name_ = "<unknown>";
        // Are we done loading?
        bool done_ = false;

    public:
        @disable this();
        @disable int opCmp(ref Loader);
        @disable bool opEquals(ref Loader);

        /** Construct a Loader to load YAML from a file.
         *
         * Params:  filename = Name of the file to load from.
         *
         * Throws:  YAMLException if the file could not be opened or read.
         */
        this(string filename) @trusted
        {
            name_ = filename;
            try
            {
                this(std.file.read(filename));
            }
            catch(FileException e)
            {
                throw new YAMLException("Unable to open file %s for YAML loading: %s"
                                        .format(filename, e.msg));
            }
        }

        /** Construct a Loader to load YAML from a string (char []).
         *
         * Params:  data = String to load YAML from. $(B will) be overwritten during
         *                 parsing as D:YAML reuses memory. Use data.dup if you don't
         *                 want to modify the original string.
         *
         * Returns: Loader loading YAML from given string.
         *
         * Throws:
         *
         * YAMLException if data could not be read (e.g. a decoding error)
         */
        static Loader fromString(char[] data) @safe
        {
            return Loader(cast(ubyte[])data);
        }
        ///
        @safe unittest
        {
            assert(Loader.fromString("42".dup).load().as!int == 42);
        }

        /** Construct a Loader to load YAML from a buffer.
         *
         * Params: yamlData = Buffer with YAML data to load. This may be e.g. a file
         *                    loaded to memory or a string with YAML data. Note that
         *                    buffer $(B will) be overwritten, as D:YAML minimizes
         *                    memory allocations by reusing the input _buffer.
         *                    $(B Must not be deleted or modified by the user  as long
         *                    as nodes loaded by this Loader are in use!) - Nodes may
         *                    refer to data in this buffer.
         *
         * Note that D:YAML looks for byte-order-marks YAML files encoded in
         * UTF-16/UTF-32 (and sometimes UTF-8) use to specify the encoding and
         * endianness, so it should be enough to load an entire file to a buffer and
         * pass it to D:YAML, regardless of Unicode encoding.
         *
         * Throws:  YAMLException if yamlData contains data illegal in YAML.
         */
        this(void[] yamlData) @trusted
        {
            try
            {
                reader_      = new Reader(cast(ubyte[])yamlData);
                scanner_     = new Scanner(reader_);
                parser_      = new Parser(scanner_);
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to open %s for YAML loading: %s"
                                        .format(name_, e.msg));
            }
        }


        /// Set stream _name. Used in debugging messages.
        void name(string name) pure @safe nothrow @nogc
        {
            name_ = name;
        }

        /// Specify custom Resolver to use.
        void resolver(Resolver resolver) pure @safe nothrow @nogc
        {
            resolver_ = resolver;
        }

        /// Specify custom Constructor to use.
        void constructor(Constructor constructor) pure @safe nothrow @nogc
        {
            constructor_ = constructor;
        }

        /** Load single YAML document.
         *
         * If none or more than one YAML document is found, this throws a YAMLException.
         *
         * This can only be called once; this is enforced by contract.
         *
         * Returns: Root node of the document.
         *
         * Throws:  YAMLException if there wasn't exactly one document
         *          or on a YAML parsing error.
         */
        Node load() @safe
        in
        {
            assert(!done_, "Loader: Trying to load YAML twice");
        }
        body
        {
            try
            {
                lazyInitConstructorResolver();
                scope(exit) { done_ = true; }
                auto composer = new Composer(parser_, resolver_, constructor_);
                enforce(composer.checkNode(), new YAMLException("No YAML document to load"));
                return composer.getSingleNode();
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to load YAML from %s : %s"
                                        .format(name_, e.msg));
            }
        }

        /** Load all YAML documents.
         *
         * This is just a shortcut that iterates over all documents and returns them
         * all at once. Calling loadAll after iterating over the node or vice versa
         * will not return any documents, as they have all been parsed already.
         *
         * This can only be called once; this is enforced by contract.
         *
         * Returns: Array of root nodes of all documents in the file/stream.
         *
         * Throws:  YAMLException on a parsing error.
         */
        Node[] loadAll() @safe
        {
            Node[] nodes;
            foreach(ref node; this)
            {
                nodes ~= node;
            }
            return nodes;
        }

        /** Foreach over YAML documents.
         *
         * Parses documents lazily, when they are needed.
         *
         * Foreach over a Loader can only be used once; this is enforced by contract.
         *
         * Throws: YAMLException on a parsing error.
         */
        int opApply(int delegate(ref Node) dg) @trusted
        in
        {
            assert(!done_, "Loader: Trying to load YAML twice");
        }
        body
        {
            scope(exit) { done_ = true; }
            try
            {
                lazyInitConstructorResolver();
                auto composer = new Composer(parser_, resolver_, constructor_);

                int result = 0;
                while(composer.checkNode())
                {
                    auto node = composer.getNode();
                    result = dg(node);
                    if(result) { break; }
                }

                return result;
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to load YAML from %s : %s "
                                        .format(name_, e.msg));
            }
        }

    package:
        // Scan and return all tokens. Used for debugging.
        Token[] scan() @safe
        {
            try
            {
                Token[] result;
                while(scanner_.checkToken())
                {
                    result ~= scanner_.getToken();
                }
                return result;
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to scan YAML from stream " ~
                                        name_ ~ " : " ~ e.msg);
            }
        }

        // Scan all tokens, throwing them away. Used for benchmarking.
        void scanBench() @safe
        {
            try while(scanner_.checkToken())
            {
                scanner_.getToken();
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to scan YAML from stream " ~
                                        name_ ~ " : " ~ e.msg);
            }
        }


        // Parse and return all events. Used for debugging.
        immutable(Event)[] parse() @safe
        {
            try
            {
                immutable(Event)[] result;
                while(parser_.checkEvent())
                {
                    result ~= parser_.getEvent();
                }
                return result;
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to parse YAML from stream %s : %s "
                                        .format(name_, e.msg));
            }
        }

        // Construct default constructor/resolver if the user has not yet specified
        // their own.
        void lazyInitConstructorResolver() @safe
        {
            if(resolver_ is null)    { resolver_    = new Resolver(); }
            if(constructor_ is null) { constructor_ = new Constructor(); }
        }
}
/// Load single YAML document from a file:
@safe unittest
{
    write("example.yaml", "Hello world!");
    auto rootNode = Loader("example.yaml").load();
    assert(rootNode == "Hello world!");
}
/// Load all YAML documents from a file:
@safe unittest
{
    import std.file : write;
    write("example.yaml",
        "---\n"~
        "Hello world!\n"~
        "...\n"~
        "---\n"~
        "Hello world 2!\n"~
        "...\n"
    );
    auto nodes = Loader("example.yaml").loadAll();
    assert(nodes.length == 2);
}
/// Iterate over YAML documents in a file, lazily loading them:
@safe unittest
{
    import std.file : write;
    write("example.yaml",
        "---\n"~
        "Hello world!\n"~
        "...\n"~
        "---\n"~
        "Hello world 2!\n"~
        "...\n"
    );
    auto loader = Loader("example.yaml");

    foreach(ref node; loader)
    {
        //Do something
    }
}
/// Load YAML from a string:
@safe unittest
{
    char[] yaml_input = ("red:   '#ff0000'\n" ~
                        "green: '#00ff00'\n" ~
                        "blue:  '#0000ff'").dup;

    auto colors = Loader.fromString(yaml_input).load();

    foreach(string color, string value; colors)
    {
        import std.stdio;
        writeln(color, " is ", value, " in HTML/CSS");
    }
}

/// Load a file into a buffer in memory and then load YAML from that buffer:
@safe unittest
{
    import std.file : read, write;
    import std.stdio : writeln;
    // Create a yaml document
    write("example.yaml",
        "---\n"~
        "Hello world!\n"~
        "...\n"~
        "---\n"~
        "Hello world 2!\n"~
        "...\n"
    );
    try
    {
        void[] buffer = read("example.yaml");
        auto yamlNode = Loader(buffer);

        // Read data from yamlNode here...
    }
    catch(FileException e)
    {
        writeln("Failed to read file 'example.yaml'");
    }
}
/// Use a custom constructor/resolver to support custom data types and/or implicit tags:
@safe unittest
{
    import std.file : write;
    // Create a yaml document
    write("example.yaml",
        "---\n"~
        "Hello world!\n"~
        "...\n"
    );
    auto constructor = new Constructor();
    auto resolver = new Resolver();

    // Add constructor functions / resolver expressions here...

    auto loader = Loader("example.yaml");
    loader.constructor = constructor;
    loader.resolver = resolver;
    auto rootNode = loader.load();
}
