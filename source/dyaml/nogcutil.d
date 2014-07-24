//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


// @nogc versions of Phobos functions that are not yet @nogc.
module dyaml.nogcutil;



import std.traits;
import std.range;



/// A NoGC version of std.conv.parse for integer types.
///
/// Differences:
///    overflow parameter - bool set to true if there was integer overflow.
///    Asserts that at least one character was parsed instead of throwing an exception.
///    The caller must validate the inputs before calling parseNoGC.
Target parseNoGC(Target, Source)(ref Source s, uint radix, out bool overflow)
    @safe pure nothrow @nogc
    if (isSomeChar!(ElementType!Source) &&
        isIntegral!Target && !is(Target == enum)) 
in { assert(radix >= 2 && radix <= 36); }
body
{
    immutable uint beyond = (radix < 10 ? '0' : 'a'-10) + radix;

    Target v = 0;
    size_t atStart = true;

    for (; !s.empty; s.popFront())
    {
        uint c = s.front;
        if (c < '0')
            break;
        if (radix < 10)
        {
            if (c >= beyond)
                break;
        }
        else
        {
            if (c > '9')
            {
                c |= 0x20;//poorman's tolower
                if (c < 'a' || c >= beyond) { break; }
                c -= 'a'-10-'0';
            }
        }
        auto blah = cast(Target) (v * radix + c - '0');
        if (blah < v)
        {
            overflow = true;
            return Target.max;
        }
        v = blah;
        atStart = false;
    }
    assert(!atStart, "Nothing to parse in parse()");
    return v;
}
