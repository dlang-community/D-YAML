
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.fastcharsearch;


import std.algorithm;
import std.conv;


package:

/**
 * Mixin used for fast searching for a character in string.
 *
 * Creates a lookup table to quickly determine if a character
 * is present in the string. Size of the lookup table is limited;
 * any characters not represented in the table will be checked
 * by ordinary equality comparison.
 *
 * Params:  chars     = String to search in.
 *          tableSize = Maximum number of bytes used by the table.
 *
 * Generated method: 
 *     bool canFind(dchar c)
 *
 *     Determines if a character is in the string.
 */
template FastCharSearch(dstring chars, uint tableSize = 256)
{
    private mixin(searchCode!(chars, tableSize)());
}

/// Generate the search table and the canFind method.
string searchCode(dstring chars, uint tableSize)() @safe pure //nothrow
{
    import std.string;

    const tableSizeStr = tableSize.to!string;
    ubyte[tableSize] table;
    table[] = 0;

    //Characters that don't fit in the table.
    dchar[] specialChars;

    foreach(c; chars)
    {
        if(c < tableSize) { table[c] = 1; }
        else              { specialChars ~= c; }
    }

    string specialCharsCode()
    {
        return specialChars.map!(c => q{cast(uint)c == %s}.format(cast(uint)c)).join(q{ || });
    }

    const caseInTable = 
    q{
            if(c < %s)
            {
                return cast(immutable(bool))table_[c];
            }
    }.format(tableSize);

    string code;
    if(tableSize)
    {
        code ~= 
        q{
            static immutable ubyte table_[%s] = [
            %s];
        }.format(tableSize, table[].map!(c => c ? q{true} : q{false}).join(q{, }));
    }
    code ~= 
    q{
        bool canFind(const dchar c) @safe pure nothrow @nogc 
        {
            %s

            return %s;
        }
    }.format(tableSize ? caseInTable : "", 
             specialChars.length ? specialCharsCode() : q{false});

    return code;
}
