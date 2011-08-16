
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


/**
 * Resolves YAML tags (data types).
 *
 * Can be used to implicitly resolve custom data types of scalar values.
 */
final class Resolver 
{
    private:
        ///Default tag to use for scalars.
        static string defaultScalarTag_   = "tag:yaml.org,2002:str";
        ///Default tag to use for sequences.
        static string defaultSequenceTag_ = "tag:yaml.org,2002:seq";
        ///Default tag to use for mappings.
        static string defaultMappingTag_  = "tag:yaml.org,2002:map";
        /**
         * Arrays of scalar resolver tuples indexed by starting character of a scalar.
         *
         * Each tuple stores regular expression the scalar must match,
         * and tag to assign to it if it matches.
         */
        Tuple!(string, Regex!char)[][dchar] yamlImplicitResolvers_;

    public:
        /**
         * Construct a Resolver.
         *
         * If you don't want to implicitly resolve default YAML tags/data types,
         * you can use defaultImplicitResolvers to disable default resolvers.
         *
         * Params:  defaultImplicitResolvers = Use default YAML implicit resolvers?
         */
        this(in bool defaultImplicitResolvers = true)
        {
            if(defaultImplicitResolvers){addImplicitResolvers();}
        }

        ///Destroy the Resolver.
        ~this()
        {
            clear(yamlImplicitResolvers_);
            yamlImplicitResolvers_ = null;
        }

        /**
         * Add an implicit scalar resolver. 
         *
         * If a scalar matches regexp and starts with one of the characters in first, 
         * its _tag is set to tag.  If the scalar matches more than one resolver 
         * regular expression, resolvers added _first override those added later. 
         * Default resolvers override any user specified resolvers.
         *
         * If a scalar is not resolved to anything, it is assigned the default
         * YAML _tag for strings.
         *
         * Params:  tag    = Tag to resolve to.
         *          regexp = Regular expression the scalar must match to have this _tag.
         *          first  = String of possible starting characters of the scalar.
         */
        void addImplicitResolver(string tag, Regex!char regexp, in string first)
        {
            foreach(const dchar c; first)
            {
                if((c in yamlImplicitResolvers_) is null)
                {
                    yamlImplicitResolvers_[c] = [];
                }
                yamlImplicitResolvers_[c] ~= tuple(tag, regexp);
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
        string resolve(NodeID kind, string tag, string value, in bool implicit)
        {
            if(tag !is null && tag != "!"){return tag;}

            if(kind == NodeID.Scalar)
            {
                if(implicit)
                {
                    //Get the first char of the value.
                    size_t dummy;
                    const dchar first = value.length == 0 ? '\0' : decode(value, dummy);

                    auto resolvers = (first in yamlImplicitResolvers_) is null ? 
                                     [] : yamlImplicitResolvers_[first];

                    foreach(resolver; resolvers)
                    {
                        tag = resolver[0];
                        auto regexp = resolver[1];
                        if(!(match(value, regexp).empty)){return tag;}
                    }
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
                foreach(value; values)
                {
                    if(tag != resolver.resolve(NodeID.Scalar, null, value, true))
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

    private:
        ///Add default implicit resolvers.
        void addImplicitResolvers()
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
                                regex(r"^(?:~|null|Null|NULL|\0)?$"), "~nN\0");
            addImplicitResolver("tag:yaml.org,2002:timestamp", 
                                regex(r"^[0-9][0-9][0-9][0-9]-[0-9][0-9]-"
                                       "[0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9]"
                                       "[0-9]?-[0-9][0-9]?[Tt]|[ \t]+[0-9]"
                                       "[0-9]?:[0-9][0-9]:[0-9][0-9]"
                                       "(?:\\.[0-9]*)?(?:[ \t]*Z|[-+][0-9]"
                                       "[0-9]?(?::[0-9][0-9])?)?$"), "0123456789");
            addImplicitResolver("tag:yaml.org,2002:value", regex(r"^=$"), "=");


            //The following resolver is only for documentation purposes. It cannot work
            //because plain scalars cannot start with '!', '&', or '*'.
            addImplicitResolver("tag:yaml.org,2002:yaml", regex(r"^(?:!|&|\*)$"), "!&*");
        }
}
