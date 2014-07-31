
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


/// Loads YAML documents from files or streams.
///
/// User specified Constructor and/or Resolver can be used to support new
/// tags / data types.
///
/// Examples:
///
/// Load single YAML document from a file:
/// --------------------
/// auto rootNode = Loader("file.yaml").load();
/// ...
/// --------------------
///
/// Load all YAML documents from a file:
/// --------------------
/// auto nodes = Loader("file.yaml").loadAll();
/// ...
/// --------------------
///
/// Iterate over YAML documents in a file, lazily loading them:
/// --------------------
/// auto loader = Loader("file.yaml");
///
/// foreach(ref node; loader)
/// {
///     ...
/// }
/// --------------------
///
/// Load YAML from memory:
/// --------------------
/// import std.stream;
/// import std.stdio;
///
/// string yaml_input = "red:   '#ff0000'\n"
///                     "green: '#00ff00'\n"
///                     "blue:  '#0000ff'";
///
/// auto colors = Loader.fromString(yaml_input).load();
///
/// foreach(string color, string value; colors)
/// {
///     writeln(color, " is ", value, " in HTML/CSS");
/// }
/// --------------------
///
/// Use a custom constructor/resolver to support custom data types and/or implicit tags:
/// --------------------
/// auto constructor = new Constructor();
/// auto resolver = new Resolver();
///
/// //Add constructor functions / resolver expressions here...
///
/// auto loader = Loader("file.yaml");
/// loader.constructor = constructor;
/// loader.resolver = resolver;
/// auto rootNode = loader.load(node);
/// --------------------
struct Loader
{
    private:
        /// Reads character data from a stream.
        Reader reader_;
        /// Processes character data to YAML tokens.
        Scanner scanner_;
        /// Processes tokens to YAML events.
        Parser parser_;
        /// Resolves tags (data types).
        Resolver resolver_;
        /// Constructs YAML data types.
        Constructor constructor_;
        /// Name of the input file or stream, used in error messages.
        string name_ = "<unknown>";
        /// Are we done loading?
        bool done_ = false;

    public:
        @disable this();
        @disable int opCmp(ref Loader);
        @disable bool opEquals(ref Loader);

        /// Construct a Loader to load YAML from a file.
        ///
        /// Params:  filename = Name of the file to load from.
        ///
        /// Throws:  YAMLException if the file could not be opened or read.
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

        deprecated("Loader.fromString(string) is deprecated. Use Loader.fromString(char[]) instead.")
        static Loader fromString(string data)
        {
            return Loader(cast(ubyte[])data.dup);
        }

        /// Construct a Loader to load YAML from a string (char []).
        ///
        /// Params:  data = String to load YAML from. $(B will) be overwritten during
        ///                 parsing as D:YAML reuses memory. Use data.dup if you don't
        ///                 want to modify the original string.
        ///
        /// Returns: Loader loading YAML from given string.
        ///
        /// Throws:
        ///
        /// YAMLException if data could not be read (e.g. a decoding error)
        static Loader fromString(char[] data) @safe
        {
            return Loader(cast(ubyte[])data);
        }
        ///
        unittest
        {
            assert(Loader.fromString(cast(char[])"42").load().as!int == 42);
        }

        import std.stream;
        deprecated("Loader(Stream) is deprecated. Use Loader(ubyte[]) instead.")
        this(Stream stream) @safe
        {
            try
            {
                import dyaml.streamcompat;
                auto streamBytes  = streamToBytesGC(stream);
                reader_           = new Reader(streamBytes);
                scanner_          = new Scanner(reader_);
                parser_           = new Parser(scanner_);
                resolver_         = new Resolver();
                constructor_      = new Constructor();
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to open stream " ~ name_ ~
                                        " for YAML loading: " ~ e.msg);
            }
        }

        /// Construct a Loader to load YAML from a buffer.
        ///
        /// Params: yamlData = Buffer with YAML data to load. This may be e.g. a file
        ///                    loaded to memory or a string with YAML data. Note that
        ///                    buffer $(B will) be overwritten, as D:YAML minimizes
        ///                    memory allocations by reusing the input _buffer.
        ///
        /// D:YAML looks for byte-order-makrs YAML files encoded in UTF-16/UTF-32
        /// (and sometimes UTF-8) use to specify the encoding and endianness, so it
        /// should be enough to load an entire file to a buffer and pass it to D:YAML,
        /// regardless of Unicode encoding.
        ///
        /// Throws:  YAMLException if yamlData contains data illegal in YAML.
        this(void[] yamlData) @safe
        {
            try
            {
                reader_           = new Reader(cast(ubyte[])yamlData);
                scanner_          = new Scanner(reader_);
                parser_           = new Parser(scanner_);
                resolver_         = new Resolver();
                constructor_      = new Constructor();
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to open " ~ name_ ~
                                        " for YAML loading: " ~ e.msg);
            }
        }

        /// Destroy the Loader.
        @trusted ~this()
        {
            reader_.destroy();
            scanner_.destroy();
            parser_.destroy();
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

        /// Load single YAML document.
        ///
        /// If none or more than one YAML document is found, this throws a YAMLException.
        ///
        /// This can only be called once; this is enforced by contract.
        ///
        /// Returns: Root node of the document.
        ///
        /// Throws:  YAMLException if there wasn't exactly one document
        ///          or on a YAML parsing error.
        Node load() @safe
        in
        {
            assert(!done_, "Loader: Trying to load YAML twice");
        }
        body
        {
            try
            {
                scope(exit) { done_ = true; }
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

        /// Load all YAML documents.
        ///
        /// This is just a shortcut that iterates over all documents and returns them
        /// all at once. Calling loadAll after iterating over the node or vice versa
        /// will not return any documents, as they have all been parsed already.
        ///
        /// This can only be called once; this is enforced by contract.
        ///
        /// Returns: Array of root nodes of all documents in the file/stream.
        ///
        /// Throws:  YAMLException on a parsing error.
        Node[] loadAll() @trusted
        {
            Node[] nodes;
            foreach(ref node; this) 
            {
                nodes.assumeSafeAppend();
                nodes ~= node;
            }
            return nodes;
        }

        /// Foreach over YAML documents.
        ///
        /// Parses documents lazily, when they are needed.
        ///
        /// Foreach over a Loader can only be used once; this is enforced by contract.
        ///
        /// Throws: YAMLException on a parsing error.
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
                throw new YAMLException("Unable to load YAML from stream " ~
                                        name_ ~ " : " ~ e.msg);
            }
        }

    package:
        // Scan and return all tokens. Used for debugging.
        Token[] scan() @trusted
        {
            try
            {
                Token[] result;
                while(scanner_.checkToken())
                {
                    result.assumeSafeAppend();
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
                throw new YAMLException("Unable to parse YAML from stream " ~
                                        name_ ~ " : " ~ e.msg);
            }
        }
}

unittest
{
    import std.stdio;

    string yaml_input = "red:   '#ff0000'\n"
                        "green: '#00ff00'\n"
                        "blue:  '#0000ff'";

    import std.stream;
    auto colors = Loader(new MemoryStream(cast(char[])yaml_input)).load();

    foreach(string color, string value; colors)
    {
        writeln(color, " is ", value, " in HTML/CSS");
    }
}
