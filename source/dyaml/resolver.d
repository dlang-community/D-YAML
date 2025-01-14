
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
import std.typecons;
import std.utf;

import dyaml.node;
import dyaml.exception;


/// Type of `regexes`
private alias RegexType = Tuple!(string, "tag", const Regex!char, "regexp", string, "chars");

private immutable RegexType[] regexes = [
    RegexType("tag:yaml.org,2002:bool",
              regex(r"^(?:yes|Yes|YES|no|No|NO|true|True|TRUE" ~
                     "|false|False|FALSE|on|On|ON|off|Off|OFF)$"),
              "yYnNtTfFoO"),
    RegexType("tag:yaml.org,2002:float",
              regex(r"^(?:[-+]?([0-9][0-9_]*)\\.[0-9_]*" ~
                     "(?:[eE][-+][0-9]+)?|[-+]?(?:[0-9][0-9_]" ~
                     "*)?\\.[0-9_]+(?:[eE][-+][0-9]+)?|[-+]?" ~
                     "[0-9][0-9_]*(?::[0-5]?[0-9])+\\.[0-9_]" ~
                     "*|[-+]?\\.(?:inf|Inf|INF)|\\." ~
                     "(?:nan|NaN|NAN))$"),
              "-+0123456789."),
    RegexType("tag:yaml.org,2002:int",
              regex(r"^(?:[-+]?0b[0-1_]+" ~
                     "|[-+]?0[0-7_]+" ~
                     "|[-+]?(?:0|[1-9][0-9_]*)" ~
                     "|[-+]?0x[0-9a-fA-F_]+" ~
                     "|[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)$"),
              "-+0123456789"),
    RegexType("tag:yaml.org,2002:merge", regex(r"^<<$"), "<"),
    RegexType("tag:yaml.org,2002:null",
              regex(r"^$|^(?:~|null|Null|NULL)$"), "~nN\0"),
    RegexType("tag:yaml.org,2002:timestamp",
              regex(r"^[0-9][0-9][0-9][0-9]-[0-9][0-9]-" ~
                     "[0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9]" ~
                     "[0-9]?-[0-9][0-9]?[Tt]|[ \t]+[0-9]" ~
                     "[0-9]?:[0-9][0-9]:[0-9][0-9]" ~
                     "(?:\\.[0-9]*)?(?:[ \t]*Z|[-+][0-9]" ~
                     "[0-9]?(?::[0-9][0-9])?)?$"),
              "0123456789"),
    RegexType("tag:yaml.org,2002:value", regex(r"^=$"), "="),

    //The following resolver is only for documentation purposes. It cannot work
    //because plain scalars cannot start with '!', '&', or '*'.
    RegexType("tag:yaml.org,2002:yaml", regex(r"^(?:!|&|\*)$"), "!&*"),
];

/**
 * Resolves YAML tags (data types).
 *
 * Can be used to implicitly resolve custom data types of scalar values.
 */
struct Resolver
{
    private:
        // Default tag to use for scalars.
        string defaultScalarTag_ = "tag:yaml.org,2002:str";
        // Default tag to use for sequences.
        string defaultSequenceTag_ = "tag:yaml.org,2002:seq";
        // Default tag to use for mappings.
        string defaultMappingTag_ = "tag:yaml.org,2002:map";

        /*
         * Arrays of scalar resolver tuples indexed by starting character of a scalar.
         *
         * Each tuple stores regular expression the scalar must match,
         * and tag to assign to it if it matches.
         */
        Tuple!(string, const Regex!char)[][dchar] yamlImplicitResolvers_;

    package:
        static auto withDefaultResolvers() @safe
        {
            Resolver resolver;
            foreach(pair; regexes)
            {
                resolver.addImplicitResolver(pair.tag, pair.regexp, pair.chars);
            }
            return resolver;
        }

    public:
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
         */
        void addImplicitResolver(string tag, const Regex!char regexp, string first)
            pure @safe
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
        /// Resolve scalars starting with 'A' to !_tag
        @safe unittest
        {
            import std.file : write;
            import std.regex : regex;
            import dyaml.loader : Loader;
            import dyaml.resolver : Resolver;

            write("example.yaml", "A");

            auto loader = Loader.fromFile("example.yaml");
            loader.resolver.addImplicitResolver("!tag", regex("A.*"), "A");

            auto node = loader.load();
            assert(node.tag == "!tag");
        }

    package:
        /**
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
        string resolve(const NodeID kind, const string tag, scope string value,
                    const bool implicit) @safe
        {
            import std.array : empty, front;
            if((tag !is null) && (tag != "!"))
            {
                return tag;
            }

            final switch (kind)
            {
                case NodeID.scalar:
                    if(!implicit)
                    {
                        return defaultScalarTag_;
                    }

                    //Get the first char of the value.
                    const dchar first = value.empty ? '\0' : value.front;

                    auto resolvers = (first in yamlImplicitResolvers_) is null ?
                                     [] : yamlImplicitResolvers_[first];

                    //If regexp matches, return tag.
                    foreach(resolver; resolvers)
                    {
                        // source/dyaml/resolver.d(192,35): Error: scope variable `__tmpfordtorXXX`
                        // assigned to non-scope parameter `this` calling
                        // `std.regex.RegexMatch!string.RegexMatch.~this`
                        bool isEmpty = () @trusted {
                            return match(value, resolver[1]).empty;
                        }();
                        if(!isEmpty)
                        {
                            return resolver[0];
                        }
                    }
                    return defaultScalarTag_;
            case NodeID.sequence:
                return defaultSequenceTag_;
            case NodeID.mapping:
                return defaultMappingTag_;
            case NodeID.invalid:
                assert(false, "Cannot resolve an invalid node");
            }
        }

        ///Returns: Default scalar tag.
        @property string defaultScalarTag()   const pure @safe nothrow {return defaultScalarTag_;}

        ///Returns: Default sequence tag.
        @property string defaultSequenceTag() const pure @safe nothrow {return defaultSequenceTag_;}

        ///Returns: Default mapping tag.
        @property string defaultMappingTag()  const pure @safe nothrow {return defaultMappingTag_;}
}
