//          Copyright Cameron Ross 2020.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Definitions for YAML schemas. Used to define sets of rules to resolve tags
/// when not explicitly specified.
module dyaml.schema;

import std.regex;

/// A single schema rule
struct SchemaRule {
    /// Tag this rule will be resolved to
    string tag;
    /// The regular expression
    Regex!char regexp;
    /// The character(s) that strings matching this rule will start with.
    /// This is not optional.
    string chars;
}

struct Schema {
    SchemaRule[] rules;
    // Default tag to use for scalars.
    string defaultScalarTag = "tag:yaml.org,2002:str";
    // Default tag to use for sequences.
    string defaultSequenceTag = "tag:yaml.org,2002:seq";
    // Default tag to use for mappings.
    string defaultMappingTag = "tag:yaml.org,2002:map";
}

/// Schema for YAML 1.1 documents
enum YAML11Schema = Schema([
    SchemaRule("tag:yaml.org,2002:bool",
         regex(r"^(?:yes|Yes|YES|no|No|NO|true|True|TRUE" ~
               "|false|False|FALSE|on|On|ON|off|Off|OFF)$"),
         "yYnNtTfFoO"
     ),
    SchemaRule("tag:yaml.org,2002:float",
         regex(r"^(?:[-+]?([0-9][0-9_]*)\\.[0-9_]*" ~
               "(?:[eE][-+][0-9]+)?|[-+]?(?:[0-9][0-9_]" ~
               "*)?\\.[0-9_]+(?:[eE][-+][0-9]+)?|[-+]?" ~
               "[0-9][0-9_]*(?::[0-5]?[0-9])+\\.[0-9_]" ~
               "*|[-+]?\\.(?:inf|Inf|INF)|\\." ~
               "(?:nan|NaN|NAN))$"),
         "-+0123456789."
     ),
    SchemaRule("tag:yaml.org,2002:int",
         regex(r"^(?:[-+]?0b[0-1_]+" ~
               "|[-+]?0[0-7_]+" ~
               "|[-+]?(?:0|[1-9][0-9_]*)" ~
               "|[-+]?0x[0-9a-fA-F_]+" ~
               "|[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)$"),
         "-+0123456789"
     ),
    SchemaRule("tag:yaml.org,2002:merge",
        regex(r"^<<$"),
        "<"
    ),
    SchemaRule("tag:yaml.org,2002:null",
         regex(r"^$|^(?:~|null|Null|NULL)$"),
        "~nN\0"
     ),
    SchemaRule("tag:yaml.org,2002:timestamp",
         regex(r"^[0-9][0-9][0-9][0-9]-[0-9][0-9]-" ~
               "[0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9]" ~
               "[0-9]?-[0-9][0-9]?[Tt]|[ \t]+[0-9]" ~
               "[0-9]?:[0-9][0-9]:[0-9][0-9]" ~
               "(?:\\.[0-9]*)?(?:[ \t]*Z|[-+][0-9]" ~
               "[0-9]?(?::[0-9][0-9])?)?$"),
         "0123456789"
     ),
    SchemaRule("tag:yaml.org,2002:value",
        regex(r"^=$"),
        "="
    ),
    //The following resolver is only for documentation purposes. It cannot work
    //because plain scalars cannot start with '!', '&', or '*'.
    SchemaRule("tag:yaml.org,2002:yaml",
        regex(r"^(?:!|&|\*)$"),
        "!&*"
    )
]);

/// No tags except !str, !map, !seq
enum NullSchema = Schema();

alias DefaultSchema = YAML11Schema;
