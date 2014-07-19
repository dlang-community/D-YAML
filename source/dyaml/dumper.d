
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML _dumper.
 *
 * Code based on $(LINK2 http://www.pyyaml.org, PyYAML).
 */
module dyaml.dumper;


import std.stream;
import std.typecons;

import dyaml.anchor;
import dyaml.emitter;
import dyaml.encoding;
import dyaml.event;
import dyaml.exception;
import dyaml.linebreak;
import dyaml.node;
import dyaml.representer;
import dyaml.resolver;
import dyaml.serializer;
import dyaml.tagdirective;


/**
 * Dumps YAML documents to files or streams.
 *
 * User specified Representer and/or Resolver can be used to support new 
 * tags / data types.
 *
 * Setters are provided to affect output details (style, encoding, etc.).
 * 
 * Examples: 
 *
 * Write to a file:
 * --------------------
 * auto node = Node([1, 2, 3, 4, 5]);
 * Dumper("file.yaml").dump(node);
 * --------------------
 *
 * Write multiple YAML documents to a file:
 * --------------------
 * auto node1 = Node([1, 2, 3, 4, 5]);
 * auto node2 = Node("This document contains only one string");
 * Dumper("file.yaml").dump(node1, node2);
 *
 * //Or with an array:
 * //Dumper("file.yaml").dump([node1, node2]);
 *
 *
 * --------------------
 *
 * Write to memory:
 * --------------------
 * import std.stream;
 * auto stream = new MemoryStream();
 * auto node = Node([1, 2, 3, 4, 5]);
 * Dumper(stream).dump(node);
 * --------------------
 *
 * Use a custom representer/resolver to support custom data types and/or implicit tags:
 * --------------------
 * auto node = Node([1, 2, 3, 4, 5]);
 * auto representer = new Representer();
 * auto resolver = new Resolver();
 *
 * //Add representer functions / resolver expressions here...
 *
 * auto dumper = Dumper("file.yaml");
 * dumper.representer = representer;
 * dumper.resolver = resolver;
 * dumper.dump(node);
 * --------------------
 */
struct Dumper
{
    unittest
    {
        auto node = Node([1, 2, 3, 4, 5]);
        Dumper(new MemoryStream()).dump(node);
    }
   
    unittest
    {
        auto node1 = Node([1, 2, 3, 4, 5]);
        auto node2 = Node("This document contains only one string");
        Dumper(new MemoryStream()).dump(node1, node2);
    }
       
    unittest
    {
        import std.stream;
        auto stream = new MemoryStream();
        auto node = Node([1, 2, 3, 4, 5]);
        Dumper(stream).dump(node);
    }
       
    unittest
    {
        auto node = Node([1, 2, 3, 4, 5]);
        auto representer = new Representer();
        auto resolver = new Resolver();
        auto dumper = Dumper(new MemoryStream());
        dumper.representer = representer;
        dumper.resolver = resolver;
        dumper.dump(node);
    }

    private:
        ///Resolver to resolve tags.
        Resolver resolver_;
        ///Representer to represent data types.
        Representer representer_;

        ///Stream to write to.
        Stream stream_;

        ///Write scalars in canonical form?
        bool canonical_;
        ///Indentation width.
        int indent_ = 2;
        ///Preferred text width.
        uint textWidth_ = 80;
        ///Line break to use.
        LineBreak lineBreak_ = LineBreak.Unix;
        ///Character encoding to use.
        Encoding encoding_ = Encoding.UTF_8;
        ///YAML version string.
        string YAMLVersion_ = "1.1";
        ///Tag directives to use.
        TagDirective[] tags_ = null;
        ///Always write document start?
        Flag!"explicitStart" explicitStart_ = No.explicitStart;
        ///Always write document end?
        Flag!"explicitEnd" explicitEnd_ = No.explicitEnd;

        ///Name of the output file or stream, used in error messages.
        string name_ = "<unknown>";

    public:
        @disable this();
        @disable bool opEquals(ref Dumper);
        @disable int opCmp(ref Dumper);

        /**
         * Construct a Dumper writing to a file.
         *
         * Params: filename = File name to write to.
         *
         * Throws: YAMLException if the file can not be dumped to (e.g. cannot be opened).
         */
        this(string filename) @trusted
        {
            name_ = filename;
            try{this(new File(filename, FileMode.OutNew));}
            catch(StreamException e)
            {
                throw new YAMLException("Unable to open file " ~ filename ~ 
                                        " for YAML dumping: " ~ e.msg);
            }
        }

        ///Construct a Dumper writing to a _stream. This is useful to e.g. write to memory.
        this(Stream stream) @safe
        {
            resolver_    = new Resolver();
            representer_ = new Representer();
            stream_ = stream;
        }

        ///Destroy the Dumper.
        pure @safe nothrow ~this()
        {
            YAMLVersion_ = null;
        }

        ///Set stream _name. Used in debugging messages.
        @property void name(string name) pure @safe nothrow
        {
            name_ = name;
        }

        ///Specify custom Resolver to use.
        @property void resolver(Resolver resolver) @trusted
        {
            resolver_.destroy();
            resolver_ = resolver;
        }

        ///Specify custom Representer to use.
        @property void representer(Representer representer) @trusted
        {
            representer_.destroy();
            representer_ = representer;
        }

        ///Write scalars in _canonical form?
        @property void canonical(bool canonical) pure @safe nothrow
        {
            canonical_ = canonical;
        }

        ///Set indentation width. 2 by default. Must not be zero.
        @property void indent(uint indent) pure @safe nothrow
        in
        {   
            assert(indent != 0, "Can't use zero YAML indent width");
        }
        body
        {
            indent_ = indent;
        }

        ///Set preferred text _width.
        @property void textWidth(uint width) pure @safe nothrow
        {
            textWidth_ = width;
        }

        ///Set line break to use. Unix by default.
        @property void lineBreak(LineBreak lineBreak) pure @safe nothrow
        {
            lineBreak_ = lineBreak;
        }

        ///Set character _encoding to use. UTF-8 by default.
        @property void encoding(Encoding encoding) pure @safe nothrow
        {
            encoding_ = encoding;
        }    

        ///Always explicitly write document start?
        @property void explicitStart(bool explicit) pure @safe nothrow
        {
            explicitStart_ = explicit ? Yes.explicitStart : No.explicitStart;
        }

        ///Always explicitly write document end?
        @property void explicitEnd(bool explicit) pure @safe nothrow
        {
            explicitEnd_ = explicit ? Yes.explicitEnd : No.explicitEnd;
        }

        ///Specify YAML version string. "1.1" by default.
        @property void YAMLVersion(string YAMLVersion) pure @safe nothrow
        {
            YAMLVersion_ = YAMLVersion;
        }

        /**
         * Specify tag directives. 
         *
         * A tag directive specifies a shorthand notation for specifying _tags.
         * Each tag directive associates a handle with a prefix. This allows for 
         * compact tag notation.
         *
         * Each handle specified MUST start and end with a '!' character
         * (a single character "!" handle is allowed as well).
         *
         * Only alphanumeric characters, '-', and '__' may be used in handles.
         *
         * Each prefix MUST not be empty.
         *
         * The "!!" handle is used for default YAML _tags with prefix 
         * "tag:yaml.org,2002:". This can be overridden.
         *
         * Params:  tags = Tag directives (keys are handles, values are prefixes).
         *
         * Example:
         * --------------------
         * Dumper dumper = Dumper("file.yaml");
         * string[string] directives;
         * directives["!short!"] = "tag:long.org,2011:";
         * //This will emit tags starting with "tag:long.org,2011"
         * //with a "!short!" prefix instead.
         * dumper.tagDirectives(directives);
         * dumper.dump(Node("foo"));
         * --------------------
         */
        @property void tagDirectives(string[string] tags) pure @trusted
        {
            TagDirective[] t;
            foreach(handle, prefix; tags)
            {
                assert(handle.length >= 1 && handle[0] == '!' && handle[$ - 1] == '!',
                       "A tag handle is empty or does not start and end with a "
                       "'!' character : " ~ handle);
                assert(prefix.length >= 1, "A tag prefix is empty");
                t ~= TagDirective(handle, prefix);
            }
            tags_ = t;
        }

        /**
         * Dump one or more YAML _documents to the file/stream.
         *
         * Note that while you can call dump() multiple times on the same 
         * dumper, you will end up writing multiple YAML "files" to the same
         * file/stream.
         *
         * Params:  documents = Documents to _dump (root nodes of the _documents).
         *
         * Throws:  YAMLException on error (e.g. invalid nodes, 
         *          unable to write to file/stream).
         */
        void dump(Node[] documents ...) @trusted
        {
            try
            {
                auto emitter = Emitter(stream_, canonical_, indent_, textWidth_, lineBreak_);
                auto serializer = Serializer(emitter, resolver_, encoding_, explicitStart_,
                                             explicitEnd_, YAMLVersion_, tags_);
                foreach(ref document; documents)
                {
                    representer_.represent(serializer, document);
                }
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to dump YAML to stream " 
                                        ~ name_ ~ " : " ~ e.msg);
            }
        }

    package:
        /*
         * Emit specified events. Used for debugging/testing.
         *
         * Params:  events = Events to emit.
         *
         * Throws:  YAMLException if unable to emit.
         */
        void emit(Event[] events) @system
        {
            try
            {
                auto emitter = Emitter(stream_, canonical_, indent_, textWidth_, lineBreak_);
                foreach(ref event; events)
                {
                    emitter.emit(event);
                }
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to emit YAML to stream " 
                                        ~ name_ ~ " : " ~ e.msg);
            }
        }
}
