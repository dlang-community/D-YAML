// Copyright Ferdinand Majerech 2014, Digital Mars 2000-2012, Andrei Alexandrescu 2008- and Jonathan M Davis 2011-.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// @nogc versions of or alternatives to Phobos functions that are not yet @nogc and
/// wrappers to simplify their use.
module dyaml.nogcutil;



import std.traits;
import std.typecons;
import std.typetuple;
import std.range;


/// Result of a validateUTF8NoGC call.
struct ValidateResult
{
    /// Is the validated string valid?
    bool   valid;
    /// Number of characters in the string.
    ///
    /// If the string is not valid, this is the number of valid characters before
    /// hitting the first invalid sequence.
    size_t characterCount;
    /// If the string is not valid, error message with details is here.
    string msg;
}

/// Validate a UTF-8 string, checking if it is well-formed Unicode.
///
/// See_Also: ValidateResult
ValidateResult validateUTF8NoGC(const(char[]) str) @safe pure nothrow @nogc
{
    immutable len = str.length;
    size_t characterCount;
    outer: for (size_t index = 0; index < len; )
    {
        if(str[index] < 0x80)
        {
            ++index;
            ++characterCount;
            continue;
        }

        auto decoded = decodeUTF8NoGC!(No.validated)(str, index);
        if(decoded.errorMessage !is null)
        {
            return ValidateResult(false, characterCount, decoded.errorMessage);
        }
        ++characterCount;
    }

    return ValidateResult(true, characterCount);
}

/// @nogc version of std.utf.decode() for char[].
///
/// The caller $(B must) handle ASCII (< 0x80) characters manually; this is asserted to
/// force code using this function to be efficient.
///
/// Params:
///
/// validated = If ture, assume str is a valid UTF-8 string and don't generate any
///             error-checking code. If validated is true, str $(B must) be a valid
///             character, otherwise undefined behavior will occur. Also affects the
///             return type.
/// str       = Will decode the first code point from this string.
/// index     = Index in str where the code point starts. Will be updated to point to
///             the next code point.
///
/// Returns: If validated is true, the decoded character.
///          Otherwise a struct with a 'decoded' member - the decoded character, and a
///          'string errorMessage' member that is null on success and otherwise stores
///          the error message.
auto decodeUTF8NoGC(Flag!"validated" validated)(const(char[]) str, ref size_t index)
{
    static if(!validated) struct Result
    {
        dchar decoded;
        string errorMessage;
    }
    else alias Result = dchar;

    /// Dchar bitmask for different numbers of UTF-8 code units.
    enum bitMask     = tuple((1 << 7) - 1, (1 << 11) - 1, (1 << 16) - 1, (1 << 21) - 1);

    auto pstr = str[index..$];

    immutable length = str.length - index;
    ubyte fst = pstr[0];

    assert(fst & 0x80);
    enum invalidUTFMsg = "Invalid UTF-8 sequence";
    static if(!validated) { enum invalidUTF = Result(cast(dchar)int.max, invalidUTFMsg); }

    // starter must have at least 2 first bits set
    static if(validated)
    {
        assert((fst & 0b1100_0000) == 0b1100_0000, invalidUTFMsg);
    }
    else if((fst & 0b1100_0000) != 0b1100_0000)
    {
        return invalidUTF;
    }

    ubyte tmp = void;
    dchar d = fst; // upper control bits are masked out later
    fst <<= 1;


    foreach (i; TypeTuple!(1, 2, 3))
    {
        static if(validated) { assert(i != length, "Decoding out of bounds"); }
        else if(i == length) { return Result(cast(dchar)int.max, "Decoding out of bounds"); }

        tmp = pstr[i];
        static if(validated)          { assert((tmp & 0xC0) == 0x80, invalidUTFMsg); }
        else if((tmp & 0xC0) != 0x80) { return invalidUTF; }

        d = (d << 6) | (tmp & 0x3F);
        fst <<= 1;

        if (!(fst & 0x80)) // no more bytes
        {
            d &= bitMask[i]; // mask out control bits

            // overlong, could have been encoded with i bytes
            static if(validated) { assert((d & ~bitMask[i - 1]) != 0, invalidUTFMsg); }
            else if((d & ~bitMask[i - 1]) == 0) { return invalidUTF; }

            // check for surrogates only needed for 3 bytes
            static if (i == 2)
            {
                static if(validated)      { assert(isValidDchar(d), invalidUTFMsg); }
                else if(!isValidDchar(d)) { return invalidUTF; }
            }

            index += i + 1;
            static if (i == 3)
            {
                static if(validated)   { assert(d <= dchar.max, invalidUTFMsg); }
                else if(d > dchar.max) { return invalidUTF; }
            }

            return Result(d);
        }
    }

    static if(validated) { assert(false, invalidUTFMsg); }
    else                 { return invalidUTF; }
}

/// ditto
alias decodeValidUTF8NoGC = decodeUTF8NoGC!(Yes.validated);

/// @nogc version of std.utf.encode() for char[].
///
/// The caller $(B must) handle ASCII (< 0x80) characters manually; this is asserted to
/// force code using this function to be efficient.
///
/// Params:
/// validated = If true, asssume c is a valid, non-surrogate UTF-32 code point and don't
///             generate any error-checking code. If validated is true, c $(B must) be
///             a valid character, otherwise undefined behavior will occur. Also affects
///             the return type.
/// buf       = Buffer to write the encoded result to.
/// c         = Character to encode.
///
/// Returns: If validated is true, number of bytes the encoded character takes up in buf.
///          Otherwise a struct with a 'bytes' member specifying the number of bytes of
///          the endocded character, and a 'string errorMessage' member that is null
///          if there was no error and otherwise stores the error message.
auto encodeCharNoGC(Flag!"validated" validated)(ref char[4] buf, dchar c)
    @safe pure nothrow @nogc
{
    static if(!validated) struct Result
    {
        size_t bytes;
        string errorMessage;
    }
    else alias Result = size_t;

    // Force the caller to optimize ASCII (the 1-byte case)
    assert(c >= 0x80, "Caller should explicitly handle ASCII chars");
    if (c <= 0x7FF)
    {
        assert(isValidDchar(c));
        buf[0] = cast(char)(0xC0 | (c >> 6));
        buf[1] = cast(char)(0x80 | (c & 0x3F));
        return Result(2);
    }
    if (c <= 0xFFFF)
    {
        static if(validated)
        {
            assert(0xD800 > c || c > 0xDFFF,
                   "Supposedly valid code point is a surrogate code point");
        }
        else if(0xD800 <= c && c <= 0xDFFF)
        {
            return Result(size_t.max, "Can't encode a surrogate code point in UTF-8");
        }

        assert(isValidDchar(c));
        buf[0] = cast(char)(0xE0 | (c >> 12));
        buf[1] = cast(char)(0x80 | ((c >> 6) & 0x3F));
        buf[2] = cast(char)(0x80 | (c & 0x3F));
        return Result(3);
    }
    if (c <= 0x10FFFF)
    {
        assert(isValidDchar(c));
        buf[0] = cast(char)(0xF0 | (c >> 18));
        buf[1] = cast(char)(0x80 | ((c >> 12) & 0x3F));
        buf[2] = cast(char)(0x80 | ((c >> 6) & 0x3F));
        buf[3] = cast(char)(0x80 | (c & 0x3F));
        return Result(4);
    }

    assert(!isValidDchar(c));
    static if(!validated)
    {
        return Result(size_t.max, "Can't encode an invalid code point in UTF-8");
    }
    else
    {
        assert(false, "Supposedly valid code point is invalid");
    }
}

/// ditto
alias encodeValidCharNoGC = encodeCharNoGC!(Yes.validated);

/// @nogc version of std.utf.isValidDchar
bool isValidDchar(dchar c) @safe pure nothrow @nogc
{
    return c < 0xD800 || (c > 0xDFFF && c <= 0x10FFFF);
}
