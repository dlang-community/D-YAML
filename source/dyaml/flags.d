
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///Compact storage of multiple boolean values.
module dyaml.flags;


import std.conv;


package:

/**
 * Struct holding multiple named boolean values in a single byte.
 *
 * Can hold at most 8 values.
 */
struct Flags(names ...) if(names.length <= 8)
{
    private:
        @disable int opCmp(ref Flags);

        ///Byte storing the flags.
        ubyte flags_;

        ///Generate a setter and a getter for each flag.
        static string flags(string[] names ...) @safe
        in
        {
            assert(names.length <= 8, "Flags struct can only hold 8 flags");
        }
        body
        {
            string result;
            foreach(index, name; names)
            {
                string istr = to!string(index);
                result ~= "\n" ~
                          "@property bool " ~ name ~ "(bool value) pure @safe nothrow\n" ~
                          "{\n" ~
                          "    flags_ = value ? flags_ | (1 <<" ~ istr ~  ")\n" ~
                          "                   : flags_ & (0xFF ^ (1 << " ~ istr ~"));\n" ~
                          "    return value;\n" ~
                          "}\n" ~
                          "\n" ~
                          "@property bool " ~ name ~ "() const pure @safe nothrow\n" ~
                          "{\n" ~
                          "    return (flags_ >> " ~ istr ~ ") & 1;\n" ~
                          "}\n";
            }
            return result;
        }

    public:
        ///Flag accessors.
        mixin(flags(names));
}
///
@safe unittest
{
    Flags!("empty", "multiline") flags;
    assert(flags.empty == false && flags.multiline == false);
    flags.multiline = true;
    assert(flags.empty == false && flags.multiline == true);
    flags.empty = true;
    assert(flags.empty == true && flags.multiline == true);
    flags.multiline = false;
    assert(flags.empty == true && flags.multiline == false);
    flags.empty = false;
    assert(flags.empty == false && flags.multiline == false);
}
