
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * Implements a class that resolves YAML tags. This can be used to implicitly
 * resolve tags for custom data types, removing the need to explicitly 
 * specify tags in YAML. A tutorial can be found 
 * $(LINK2 ../tutorials/custom_types.html, here).    
 * 
 * Code based on $(LINK2 http://www.pyyaml.org, PyYAML).
 */
module dyaml.resolver;


import std.conv;
import std.regex;
import std.stdio;
import std.typecons;
import std.utf;

import dyaml.node;
import dyaml.exception;
import dyaml.tag;


/**
 * Resolves YAML tags (data types).
 *
 * Can be used to implicitly resolve custom data types of scalar values.
 */
final class Resolver 
{
    private:
        // Default tag to use for scalars.
        Tag defaultScalarTag_;
        // Default tag to use for sequences.
        Tag defaultSequenceTag_;
        // Default tag to use for mappings.
        Tag defaultMappingTag_;

        /* 
         * Arrays of scalar resolver tuples indexed by starting character of a scalar.
         *
         * Each tuple stores regular expression the scalar must match,
         * and tag to assign to it if it matches.
         */
        Tuple!(Tag, Regex!char)[][dchar] yamlImplicitResolvers_;

    public:
        @disable bool opEquals(ref Resolver);
        @disable int opCmp(ref Resolver);

        /**
         * Construct a Resolver.
         *
         * If you don't want to implicitly resolve default YAML tags/data types,
         * you can use defaultImplicitResolvers to disable default resolvers.
         *
         * Params:  defaultImplicitResolvers = Use default YAML implicit resolvers?
         */
        this(Flag!"useDefaultImplicitResolvers" defaultImplicitResolvers = Yes.useDefaultImplicitResolvers) 
            @safe
        {
            defaultScalarTag_   = Tag("tag:yaml.org,2002:str");
            defaultSequenceTag_ = Tag("tag:yaml.org,2002:seq");
            defaultMappingTag_  = Tag("tag:yaml.org,2002:map");
            if(defaultImplicitResolvers){addImplicitResolvers();}
        }

        ///Destroy the Resolver.
        pure @safe nothrow ~this()
        {
            yamlImplicitResolvers_.destroy();
            yamlImplicitResolvers_ = null;
        }

        /**
         * Add an implicit scalar resolver. 
         *
         * If a scalar matches regexp and starts with any character in first, 
         * its _tag is set to tag. If it matches more than one resolver _regexp
         * resolvers added _first override ones added later. Default resolvers 
         * override any user specified resolvers, but they can be disabled in
         * Resolver constructor.
         *
         * If a scalar is not resolved to anything, it is assigned the default
         * YAML _tag for strings.
         *
         * Params:  tag    = Tag to resolve to.
         *          regexp = Regular expression the scalar must match to have this _tag.
         *          first  = String of possible starting characters of the scalar.
         *
         * Examples:
         *
         * Resolve scalars starting with 'A' to !_tag :
         * --------------------
         * import std.regex;
         *
         * import dyaml.all;
         *
         * void main()
         * {
         *     auto loader = Loader("file.txt");
         *     auto resolver = new Resolver();
         *     resolver.addImplicitResolver("!tag", std.regex.regex("A.*"), "A");
         *     loader.resolver = resolver;
         *     
         *     //Note that we have no constructor from tag "!tag", so we can't
         *     //actually load anything that resolves to this tag.
         *     //See Constructor API documentation and tutorial for more information.
         *
         *     auto node = loader.load();
         * }
         * --------------------
         */
        void addImplicitResolver(string tag, Regex!char regexp, string first) 
            pure @safe 
        {
            foreach(const dchar c; first)
            {
                if((c in yamlImplicitResolvers_) is null)
                {
                    yamlImplicitResolvers_[c] = [];
                }
                yamlImplicitResolvers_[c] ~= tuple(Tag(tag), regexp);
            }
        }

    package:
        /*
         * Resolve tag of a node.
         *
         * Params:  kind     = Type of the node.
         *          tag      = Explicit tag of the node, if any.
         *          value    = Value of the node, if any.
         *          implicit = Should the node be implicitly resolved?
         *
         * If the tag is already specified and not non-specific, that tag will
         * be returned.
         *
         * Returns: Resolved tag.
         */
        Tag resolve(const NodeID kind, const Tag tag, const string value, 
                    const bool implicit) @safe 
        {
            if(!tag.isNull() && tag.get() != "!"){return tag;}

            if(kind == NodeID.Scalar)
            {
                if(!implicit){return defaultScalarTag_;}

                //Get the first char of the value.
                size_t dummy;
                const dchar first = value.length == 0 ? '\0' : decode(value, dummy);

                auto resolvers = (first in yamlImplicitResolvers_) is null ? 
                                 [] : yamlImplicitResolvers_[first];

                //If regexp matches, return tag.
                foreach(resolver; resolvers) if(!(match(value, resolver[1]).empty))
                {
                    return resolver[0];
                }
                return defaultScalarTag_;
            }
            else if(kind == NodeID.Sequence){return defaultSequenceTag_;}
            else if(kind == NodeID.Mapping) {return defaultMappingTag_;}
            assert(false, "This line of code should never be reached");
        }
        unittest
        {
            writeln("D:YAML Resolver unittest");

            auto resolver = new Resolver();

            bool tagMatch(string tag, string[] values)
            {
                Tag expected = Tag(tag);
                foreach(value; values)
                {
                    Tag resolved = resolver.resolve(NodeID.Scalar, Tag(), value, true);
                    if(expected != resolved)
                    {
                        return false;
                    }
                }
                return true;
            }

            assert(tagMatch("tag:yaml.org,2002:bool", 
                   ["yes", "NO", "True", "on"]));
            assert(tagMatch("tag:yaml.org,2002:float", 
                   ["6.8523015e+5", "685.230_15e+03", "685_230.15", 
                    "190:20:30.15", "-.inf", ".NaN"]));
            assert(tagMatch("tag:yaml.org,2002:int", 
                   ["685230", "+685_230", "02472256", "0x_0A_74_AE",
                    "0b1010_0111_0100_1010_1110", "190:20:30"]));
            assert(tagMatch("tag:yaml.org,2002:merge", ["<<"]));
            assert(tagMatch("tag:yaml.org,2002:null", ["~", "null", ""]));
            assert(tagMatch("tag:yaml.org,2002:str", 
                            ["abcd", "9a8b", "9.1adsf"]));
            assert(tagMatch("tag:yaml.org,2002:timestamp", 
                   ["2001-12-15T02:59:43.1Z",
                   "2001-12-14t21:59:43.10-05:00",
                   "2001-12-14 21:59:43.10 -5",
                   "2001-12-15 2:59:43.10",
                   "2002-12-14"]));
            assert(tagMatch("tag:yaml.org,2002:value", ["="]));
            assert(tagMatch("tag:yaml.org,2002:yaml", ["!", "&", "*"]));
        }

        ///Return default scalar tag.
        @property Tag defaultScalarTag()   const pure @safe nothrow {return defaultScalarTag_;}

        ///Return default sequence tag.
        @property Tag defaultSequenceTag() const pure @safe nothrow {return defaultSequenceTag_;}

        ///Return default mapping tag.
        @property Tag defaultMappingTag()  const pure @safe nothrow {return defaultMappingTag_;}

    private:
        // Add default implicit resolvers.
        void addImplicitResolvers() @safe
        {
            addImplicitResolver("tag:yaml.org,2002:bool",
                                regex(r"^(?:yes|Yes|YES|no|No|NO|true|True|TRUE"
                                       "|false|False|FALSE|on|On|ON|off|Off|OFF)$"),
                                "yYnNtTfFoO");
            addImplicitResolver("tag:yaml.org,2002:float",
                                regex(r"^(?:[-+]?([0-9][0-9_]*)\\.[0-9_]*"
                                      "(?:[eE][-+][0-9]+)?|[-+]?(?:[0-9][0-9_]"
                                      "*)?\\.[0-9_]+(?:[eE][-+][0-9]+)?|[-+]?"
                                      "[0-9][0-9_]*(?::[0-5]?[0-9])+\\.[0-9_]"
                                      "*|[-+]?\\.(?:inf|Inf|INF)|\\."
                                      "(?:nan|NaN|NAN))$"),
                                "-+0123456789.");
            addImplicitResolver("tag:yaml.org,2002:int",
                                regex(r"^(?:[-+]?0b[0-1_]+"
                                       "|[-+]?0[0-7_]+"
                                       "|[-+]?(?:0|[1-9][0-9_]*)"
                                       "|[-+]?0x[0-9a-fA-F_]+"
                                       "|[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)$"),
                                "-+0123456789");
            addImplicitResolver("tag:yaml.org,2002:merge", regex(r"^<<$"), "<");
            addImplicitResolver("tag:yaml.org,2002:null", 
                                regex(r"^$|^(?:~|null|Null|NULL)$"), "~nN\0");
            addImplicitResolver("tag:yaml.org,2002:timestamp", 
                                regex(r"^[0-9][0-9][0-9][0-9]-[0-9][0-9]-"
                                       "[0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9]"
                                       "[0-9]?-[0-9][0-9]?[Tt]|[ \t]+[0-9]"
                                       "[0-9]?:[0-9][0-9]:[0-9][0-9]"
                                       "(?:\\.[0-9]*)?(?:[ \t]*Z|[-+][0-9]"
                                       "[0-9]?(?::[0-9][0-9])?)?$"), 
                                "0123456789");
            addImplicitResolver("tag:yaml.org,2002:value", regex(r"^=$"), "=");


            //The following resolver is only for documentation purposes. It cannot work
            //because plain scalars cannot start with '!', '&', or '*'.
            addImplicitResolver("tag:yaml.org,2002:yaml", regex(r"^(?:!|&|\*)$"), "!&*");
        }
}
