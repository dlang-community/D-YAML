// Copyright Ferdinand Majerech 2014, Digital Mars 2000-2012, Andrei Alexandrescu 2008- and Jonathan M Davis 2011-.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// @nogc versions of or alternatives to Phobos functions that are not yet @nogc and
/// wrappers to simplify their use.
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

    // We can safely foreach over individual code points.
    // Even with UTF-8 any digit is ASCII and anything not ASCII (such as the start of
    // a UTF-8 sequence) is not a digit.
    foreach(i; 0 .. s.length)
    {
        dchar c = s[i];
        // We can just take a char instead of decoding because anything non-ASCII is not
        // going to be a decodable digit, i.e. we will end at such a byte.
        if (c < '0' || c >= 0x80)
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


/// Buils a message to a buffer similarly to writef/writefln, but without
/// using GC.
///
/// C snprintf would be better, but it isn't pure.
/// formattedWrite isn't completely @nogc yet (although it isn't GC-heavy).
///
/// The user has to ensure buffer is long enough - an assert checks that we don't run
/// out of space. Currently this can only write strings and dchars.
char[] printNoGC(S...)(char[] buffer, S args) @safe pure nothrow @nogc
{
    auto appender = appenderNoGC(buffer);

    foreach(arg; args)
    {
        alias A = typeof(arg);
        static if(is(A == char[]) || is(A == string)) { appender.put(arg); }
        else static if(is(Unqual!A == dchar))         { appender.putDChar(arg); }
        else static assert(false, "printNoGC does not support " ~ A.stringof);
    }

    return appender.data;
}


/// A UFCS utility function to write a dchar to an AppenderNoGCFixed using writeDCharTo.
///
/// The char $(B must) be a valid dchar.
void putDChar(ref AppenderNoGCFixed!(char[], char) appender, dchar c)
    @safe pure nothrow @nogc
{
    char[4] dcharBuf;
    if(c < 0x80)
    {
        dcharBuf[0] = cast(char)c;
        appender.put(dcharBuf[0 .. 1]);
        return;
    }
    // Should be safe to use as the first thing Reader does is validate everything.
    const bytes = encodeValidCharNoGC(dcharBuf, c);
    appender.put(dcharBuf[0 .. bytes]);
}

/// Convenience function that returns an $(D AppenderNoGCFixed!A) using with $(D array)
/// for storage.
AppenderNoGCFixed!(E[]) appenderNoGC(A : E[], E)(A array)
{
    return AppenderNoGCFixed!(E[])(array);
}

/// A gutted, NoGC version of std.array.appender.
///
/// Works on a fixed-size buffer.
struct AppenderNoGCFixed(A : T[], T)
{
    import std.array;

    private struct Data
    {
        size_t capacity;
        Unqual!T[] arr;
        bool canExtend = false;
    }

    private Data _data;

    @nogc:

    /// Construct an appender that will work with given buffer.
    ///
    /// Data written to the appender will overwrite the buffer from the start.
    this(T[] arr) @trusted pure nothrow
    {
        // initialize to a given array.
        _data.arr = cast(Unqual!T[])arr[0 .. 0]; //trusted
        _data.capacity = arr.length;
    }

    /**
     * Returns the capacity of the array (the maximum number of elements the
     * managed array can accommodate before triggering a reallocation).  If any
     * appending will reallocate, $(D capacity) returns $(D 0).
     */
    @property size_t capacity() const @safe pure nothrow
    {
        return _data.capacity;
    }

    /**
     * Returns the managed array.
     */
    @property inout(T)[] data() inout @trusted pure nothrow
    {
        /* @trusted operation:
         * casting Unqual!T[] to inout(T)[]
         */
        return cast(typeof(return))(_data.arr);
    }

    // ensure we can add nelems elements, resizing as necessary
    private void ensureAddable(size_t nelems) @safe pure nothrow
    {
        assert(_data.capacity >= _data.arr.length + nelems,
                "AppenderFixed ran out of space");
    }

    void put(U)(U[] items) if (is(Unqual!U == T))
    {
        // make sure we have enough space, then add the items
        ensureAddable(items.length);
        immutable len = _data.arr.length;
        immutable newlen = len + items.length;

        auto bigDataFun() @trusted nothrow { return _data.arr.ptr[0 .. newlen];}
        auto bigData = bigDataFun();

        alias UT = Unqual!T;

        bigData[len .. newlen] = items[];

        //We do this at the end, in case of exceptions
        _data.arr = bigData;
    }

    // only allow overwriting data on non-immutable and non-const data
    static if (isMutable!T)
    {
        /**
         * Clears the managed array.  This allows the elements of the array to be reused
         * for appending.
         *
         * Note that clear is disabled for immutable or const element types, due to the
         * possibility that $(D AppenderNoGCFixed) might overwrite immutable data.
         */
        void clear() @safe pure nothrow
        {
            _data.arr = ()@trusted{ return _data.arr.ptr[0 .. 0]; }();
        }
    }
    else
    {
        /// Clear is not available for const/immutable data.
        @disable void clear();
    }
}
unittest
{
    char[256] buffer;
    auto appender = appenderNoGC(buffer[]);
    appender.put("found unsupported escape character: ");
    appender.putDChar('a');
    appender.putDChar('á');
    assert(appender.data == "found unsupported escape character: aá");
}


/// Result of a validateUTF8NoGC call.
struct ValidateResult
{
    /// Is the validated string valid?
    bool   valid;
    /// If the string is not valid, error message with details is here.
    string msg;
    /// If the string is not valid, the first invalid sequence of bytes is here.
    const(uint)[] sequence() @safe pure nothrow const @nogc
    {
        return sequenceBuffer[0 .. sequenceLength];
    }

private:
    // Buffer for the invalid sequence of bytes if valid == false.
    uint[4] sequenceBuffer;
    // Number of used bytes in sequenceBuffer.
    size_t  sequenceLength;
}

/// Validate a UTF-8 string, checking if it is well-formed Unicode.
///
/// See_Also: ValidateResult
ValidateResult validateUTF8NoGC(const(char[]) str) @trusted pure nothrow @nogc
{
    immutable len = str.length;
    outer: for (size_t index = 0; index < len; )
    {
        if(str[index] < 0x80)
        {
            index++;
            continue;
        }

        // The following encodings are valid, except for the 5 and 6 byte combinations:
        //  0xxxxxxx
        //  110xxxxx 10xxxxxx
        //  1110xxxx 10xxxxxx 10xxxxxx
        //  11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        //  111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
        //  1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx

        // Dchar bitmask for different numbers of UTF-8 code units.
        import std.typecons;
        enum bitMask     = tuple((1 << 7) - 1, (1 << 11) - 1, (1 << 16) - 1, (1 << 21) - 1);
        auto pstr        = str.ptr + index;
        immutable length = str.length - index;
        ubyte fst        = pstr[0];

        static ValidateResult error(const(char[]) str, string msg) @safe pure nothrow @nogc
        {
            ValidateResult result;
            size_t i;

            do
            {
                result.sequenceBuffer[i] = str[i];
            } while (++i < str.length && i < 4 && (str[i] & 0xC0) == 0x80);

            result.valid          = false;
            result.msg            = msg;
            result.sequenceLength = i;
            return result;
        }

        static ValidateResult invalidUTF(const(char[]) str) @safe pure nothrow @nogc
        {
            return error(str, "Invalid UTF-8 sequence");
        }
        static ValidateResult outOfBounds(const(char[]) str) @safe pure nothrow @nogc
        {
            return error(str, "Attempted to decode past the end of a string");
        }

        assert(fst & 0x80);
        ubyte tmp = void;
        dchar d = fst; // upper control bits are masked out later
        fst <<= 1;

        foreach (i; TypeTuple!(1, 2, 3))
        {
            if(i == length) { return outOfBounds(pstr[0 .. length]); }

            tmp = pstr[i];

            if ((tmp & 0xC0) != 0x80) { return invalidUTF(pstr[0 .. length]); }

            d = (d << 6) | (tmp & 0x3F);
            fst <<= 1;

            if (!(fst & 0x80)) // no more bytes
            {
                d &= bitMask[i]; // mask out control bits

                // overlong, could have been encoded with i bytes
                if ((d & ~bitMask[i - 1]) == 0) { return invalidUTF(pstr[0 .. length]); }

                // check for surrogates only needed for 3 bytes
                static if(i == 2)
                {
                    if (!isValidDchar(d)) { return invalidUTF(pstr[0 .. length]); }
                }

                index += i + 1;
                static if(i == 3)
                {
                    if (d > dchar.max) { return invalidUTF(pstr[0 .. length]); }
                }
                continue outer;
            }
        }

        return invalidUTF(pstr[0 .. length]);
    }

    return ValidateResult(true);
}

/// @nogc version of std.utf.decode() for (char[]), but assumes str is valid UTF-8.
///
/// The caller $(B must) handle ASCII (< 0x80) characters manually; this is asserted to
/// force code using this function to be efficient.
///
/// Params:
///
/// str   = Will decode the first code point from this string. Must be valid UTF-8,
///         otherwise undefined behavior WILL occur.
/// index = Index in str where the code point starts. Will be updated to point to the
///         next code point.
dchar decodeValidUTF8NoGC(const(char[]) str, ref size_t index)
    @trusted pure nothrow @nogc
{
    /// Dchar bitmask for different numbers of UTF-8 code units.
    enum bitMask = [(1 << 7) - 1, (1 << 11) - 1, (1 << 16) - 1, (1 << 21) - 1];

    auto pstr = str.ptr + index;

    immutable length = str.length - index;
    ubyte fst = pstr[0];

    assert(fst & 0x80);
    ubyte tmp = void;
    dchar d = fst; // upper control bits are masked out later
    fst <<= 1;

    enum invalidUTFMsg = "Invalid UTF-8 sequence in supposedly validated string";
    foreach (i; TypeTuple!(1, 2, 3))
    {
        assert(i != length, "Decoding out of bounds in supposedly validated UTF-8");
        tmp = pstr[i];
        assert((tmp & 0xC0) == 0x80, invalidUTFMsg);

        d = (d << 6) | (tmp & 0x3F);
        fst <<= 1;

        if (!(fst & 0x80)) // no more bytes
        {
            d &= bitMask[i]; // mask out control bits

            // overlong, could have been encoded with i bytes
            assert((d & ~bitMask[i - 1]) != 0, invalidUTFMsg);

            // check for surrogates only needed for 3 bytes
            static if (i == 2) { assert(isValidDchar(d), invalidUTFMsg); }

            index += i + 1;
            static if (i == 3) { assert(d <= dchar.max, invalidUTFMsg); }
            return d;
        }
    }

    assert(false, invalidUTFMsg);
}

/// @nogc version of std.utf.endoce() for char[], but assumes c is a valid UTF-32 char.
///
/// The caller $(B must) handle ASCII (< 0x80) characters manually; this is asserted to
/// force code using this function to be efficient.
///
/// Params:
///
/// buf = Buffer to write the encoded result to.
/// c   = Character to encode. Must be valid UTF-32, otherwise undefined behavior
///       $(D will) occur.
///
/// Returns: Number of bytes the encoded character takes up in buf.
size_t encodeValidCharNoGC(ref char[4] buf, dchar c) @safe pure nothrow @nogc
{
    assert(isValidDchar(c));
    // Force the caller to optimize ASCII (the 1-byte case)
    assert(c >= 0x80, "Caller should explicitly handle ASCII chars");
    if (c <= 0x7FF)
    {
        buf[0] = cast(char)(0xC0 | (c >> 6));
        buf[1] = cast(char)(0x80 | (c & 0x3F));
        return 2;
    }
    if (c <= 0xFFFF)
    {
        assert(0xD800 > c || c > 0xDFFF,
               "Supposedly valid code point is a surrogate code point");

        buf[0] = cast(char)(0xE0 | (c >> 12));
        buf[1] = cast(char)(0x80 | ((c >> 6) & 0x3F));
        buf[2] = cast(char)(0x80 | (c & 0x3F));
        return 3;
    }
    if (c <= 0x10FFFF)
    {
        buf[0] = cast(char)(0xF0 | (c >> 18));
        buf[1] = cast(char)(0x80 | ((c >> 12) & 0x3F));
        buf[2] = cast(char)(0x80 | ((c >> 6) & 0x3F));
        buf[3] = cast(char)(0x80 | (c & 0x3F));
        return 4;
    }
    assert(false, "This should not be reached for valid dchars");
}

/// @nogc version of std.utf.isValidDchar
bool isValidDchar(dchar c) @safe pure nothrow @nogc
{
    return c < 0xD800 || (c > 0xDFFF && c <= 0x10FFFF);
}
