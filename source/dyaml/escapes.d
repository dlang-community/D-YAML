

//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.escapes;


package:

///Translation table from YAML escapes to dchars.
// immutable dchar[dchar] fromEscapes;
///Translation table from dchars to YAML escapes.
immutable dchar[dchar] toEscapes;
// ///Translation table from prefixes of escaped hexadecimal format characters to their lengths.
// immutable uint[dchar]  escapeHexCodes;

/// All YAML escapes.
immutable dchar[] escapes = ['0', 'a', 'b', 't', '\t', 'n', 'v', 'f', 'r', 'e', ' ',
                             '\"', '\\', 'N', '_', 'L', 'P'];

/// YAML hex codes specifying the length of the hex number.
immutable dchar[] escapeHexCodeList = ['x', 'u', 'U'];

/// Covert a YAML escape to a dchar.
///
/// Need a function as associative arrays don't work with @nogc.
/// (And this may be even faster with a function.)
dchar fromEscape(dchar escape) @safe pure nothrow @nogc
{
    switch(escape)
    {
        case '0':  return '\0';
        case 'a':  return '\x07';
        case 'b':  return '\x08';
        case 't':  return '\x09';
        case '\t': return '\x09';
        case 'n':  return '\x0A';
        case 'v':  return '\x0B';
        case 'f':  return '\x0C';
        case 'r':  return '\x0D';
        case 'e':  return '\x1B';
        case ' ':  return '\x20';
        case '\"': return '\"';
        case '\\': return '\\';
        case 'N':  return '\x85'; //'\u0085';
        case '_':  return '\xA0';
        case 'L':  return '\u2028';
        case 'P':  return '\u2029';
        default:   assert(false, "No such YAML escape");
    }
}

/// Get the length of a hexadecimal number determined by its hex code.
///
/// Need a function as associative arrays don't work with @nogc.
/// (And this may be even faster with a function.)
uint escapeHexLength(dchar hexCode) @safe pure nothrow @nogc
{
    switch(hexCode)
    {
        case 'x': return 2;
        case 'u': return 4;
        case 'U': return 8;
        default:  assert(false, "No such YAML hex code");
    }
}


static this()
{
    toEscapes =
        ['\0':     '0',
         '\x07':   'a',
         '\x08':   'b',
         '\x09':   't',
         '\x0A':   'n',
         '\x0B':   'v',
         '\x0C':   'f',
         '\x0D':   'r',
         '\x1B':   'e',
         '\"':     '\"',
         '\\':     '\\',
         '\u0085': 'N',
         '\xA0':   '_',
         '\u2028': 'L',
         '\u2029': 'P'];
}

