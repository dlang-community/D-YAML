

//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.escapes;


package:

///Translation table from YAML escapes to dchars.
dchar[dchar] fromEscapes;
///Translation table from dchars to YAML escapes.
dchar[dchar] toEscapes;
///Translation table from prefixes of escaped hexadecimal format characters to their lengths.
uint[dchar]  escapeHexCodes;


static this()
{
    fromEscapes =
        ['0':  '\0',
         'a':  '\x07',
         'b':  '\x08',
         't':  '\x09',
         '\t': '\x09',
         'n':  '\x0A',
         'v':  '\x0B',
         'f':  '\x0C',
         'r':  '\x0D',
         'e':  '\x1B',
         ' ':  '\x20',
         '\"': '\"',
         '\\': '\\',
         'N':  '\u0085',
         '_':  '\xA0',
         'L':  '\u2028',
         'P':  '\u2029'];

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

    escapeHexCodes = ['x': 2, 'u': 4, 'U': 8];
}

