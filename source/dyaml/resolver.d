
//          Copyright Ferdinand Majerech 2011.
//          Copyright Cameron Ross 2020.
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


import std.regex;

import dyaml.node;
import dyaml.schema;


/**
 * Used to implicitly resolve tags of scalar values, according to sets of rules
 * known as schemas.
 */
struct Resolver
{
    private:
        Schema schema;
        /// Arrays of schema rules indexed by their starting characters.
        const(SchemaRule)[][dchar] yamlImplicitResolvers_;

        @disable this();
    public:
        this(Schema schema) @safe pure {
            this.schema = schema;
            foreach(tagResolver; schema.rules)
            {
                addRule(tagResolver);
            }
        }
        /**
         * Add a rule.
         *
         * If a scalar matches regexp and starts with any character in first,
         * its tag is set to the _rule's tag. In case of multiple rules
         * matching, the first specified _rule has higher priority.
         *
         * Params:  rule    = The rule to add.
         */
        void addRule(const SchemaRule rule)
            pure @safe
        {
            foreach(const dchar c; rule.chars)
            {
                yamlImplicitResolvers_.require(c, []) ~= rule;
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
            loader.resolver.addRule(SchemaRule("!tag", regex("A.*"), "A"));

            auto node = loader.load();
            assert(node.tag == "!tag");
        }

        deprecated("Use addRule(SchemaRule) instead")
        void addImplicitResolver(string tag, Regex!char regexp, string first)
            pure @safe
        {
            addRule(SchemaRule(tag, regexp, first));
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
         * If the node has an explicit specific tag, that tag will be returned.
         *
         * Returns: Resolved tag.
         */
        string resolve(const NodeID kind, const string tag, const string value,
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
                        return schema.defaultScalarTag;
                    }

                    //Get the first char of the value.
                    const dchar first = value.empty ? '\0' : value.front;

                    //If regexp matches, return tag.
                    foreach(rule; yamlImplicitResolvers_.get(first, []))
                    {
                        if(!(match(value, rule.regexp).empty))
                        {
                            return rule.tag;
                        }
                    }
                    return schema.defaultScalarTag;
            case NodeID.sequence:
                return schema.defaultSequenceTag;
            case NodeID.mapping:
                return schema.defaultMappingTag;
            case NodeID.invalid:
                assert(false, "Cannot resolve an invalid node");
            }
        }
        @safe unittest
        {
            auto resolver = Resolver(YAML11Schema);

            bool tagMatch(string tag, string[] values) @safe
            {
                const string expected = tag;
                foreach(value; values)
                {
                    const string resolved = resolver.resolve(NodeID.scalar, null, value, true);
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

        ///Returns: Default scalar tag.
        @property string defaultScalarTag() const pure @safe nothrow
        {
            return schema.defaultScalarTag;
        }

        ///Returns: Default sequence tag.
        @property string defaultSequenceTag() const pure @safe nothrow
        {
            return schema.defaultSequenceTag;
        }

        ///Returns: Default mapping tag.
        @property string defaultMappingTag() const pure @safe nothrow
        {
            return schema.defaultMappingTag;
        }
}
