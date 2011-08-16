
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.util;

package:


///Is given character YAML whitespace (space or tab)?
bool isSpace(in dchar c){return c == ' ' || c == '\t';}

///Is given character YAML line break?
bool isBreak(in dchar c)
{
    return c == '\n' || c == '\r' || c == '\x85' || c == '\u2028' || c == '\u2029';
}

///Is c the checked character?
bool isChar(dchar checked)(in dchar c){return checked == c;}

///Function that or's specified functions with a character input.
bool or(F ...)(in dchar input) 
{
    foreach(f; F)
    {
        if(f(input)){return true;}
    }
    return false;
}

///Convenience aliases.
alias isChar!'\0' isZero;
alias or!(isZero, isBreak) isBreakOrZero;
