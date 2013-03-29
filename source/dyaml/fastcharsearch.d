
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

///Generate the search table and the canFind method.
string searchCode(dstring chars, uint tableSize)() @trusted
{
    const tableSizeStr = to!string(tableSize);
    ubyte[tableSize] table;
    table[] = 0;

    //Characters that don't fit in the table.
    dchar[] specialChars;

    foreach(c; chars)
    {
        if(c < tableSize){table[c] = 1;}
        else             {specialChars ~= c;}
    }

    string tableCode()
    {
        string code = "static immutable ubyte table_[" ~ tableSizeStr ~ "] = [\n";
        foreach(c; table[0 .. $ - 1])
        {
            code ~= c ? "true,\n" : "false,\n";
        }
        code ~= table[$ - 1] ? "true\n" : "false\n";
        code ~= "];\n\n";
        return code;
    }

    string specialCharsCode()
    {
        string code;
        foreach(c; specialChars[0 .. $ - 1])
        {
            code ~= "cast(uint)c == " ~ to!string(cast(uint)c) ~ " || ";
        }
        code ~= "cast(uint)c == " ~ to!string(cast(uint)specialChars[$ - 1]);

        return code;
    }

    string code = tableSize ? tableCode() : "";

    code ~= "bool canFind(in dchar c) pure @safe nothrow\n"
            "{\n";

    if(tableSize)
    {
        code ~= "    if(c < " ~ tableSizeStr ~ ")\n"
                "    {\n"
                "        return cast(immutable(bool))table_[c];\n"
                "    }\n";
    }

    code ~= specialChars.length 
            ? "    return " ~ specialCharsCode() ~ ";\n"
            : "    return false;";
    code ~= "}\n";

    return code;
}
