//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


// Code that is currently unused but may be useful for future D:YAML releases
module dyaml.unused;



import std.utf;

import tinyendian;

// Decode an UTF-8/16/32 buffer to UTF-32 (for UTF-32 this does nothing).
//
// Params:
//
// input    = The UTF-8/16/32 buffer to decode.
// encoding = Encoding of input.
//
// Returns:
//
// A struct with the following members:
//
// $(D string errorMessage) In case of a decoding error, the error message is stored
//                          here. If there was no error, errorMessage is NULL. Always
//                          check this first before using the other members.
// $(D dchar[] decoded)     A GC-allocated buffer with decoded UTF-32 characters.
auto decodeUTF(ubyte[] input, UTFEncoding encoding) @safe pure nothrow
{
    // Documented in function ddoc.
    struct Result
    {
        string errorMessage;
        dchar[] decoded;
    }

    Result result;

    // Decode input_ if it's encoded as UTF-8 or UTF-16.
    //
    // Params:
    //
    // buffer = The input buffer to decode.
    // result = A Result struct to put decoded result and any error messages to.
    //
    // On error, result.errorMessage will be set.
    static void decode(C)(C[] input, ref Result result) @safe pure nothrow
    {
        // End of part of input that contains complete characters that can be decoded.
        const size_t end = endOfLastUTFSequence(input);
        // If end is 0, there are no full chars.
        // This can happen at the end of file if there is an incomplete UTF sequence.
        if(end < input.length)
        {
            result.errorMessage = "Invalid UTF character at the end of input";
            return;
        }

        const srclength = input.length;
        try for(size_t srcpos = 0; srcpos < srclength;)
        {
            const c = input[srcpos];
            if(c < 0x80)
            {
                result.decoded ~= c;
                ++srcpos;
            }
            else
            {
                result.decoded ~= std.utf.decode(input, srcpos);
            }
        }
        catch(UTFException e)
        {
            result.errorMessage = e.msg;
            return;
        }
        catch(Exception e)
        {
            assert(false, "Unexpected exception in decode(): " ~ e.msg);
        }
    }

    final switch(encoding)
    {
        case UTFEncoding.UTF_8:  decode(cast(char[])input, result); break;
        case UTFEncoding.UTF_16:
            assert(input.length % 2 == 0, "UTF-16 buffer size must be even");
            decode(cast(wchar[])input, result);
            break;
        case UTFEncoding.UTF_32:
            assert(input.length % 4 == 0,
                    "UTF-32 buffer size must be a multiple of 4");
            // No need to decode anything
            result.decoded = cast(dchar[])input;
            break;
    }

    if(result.errorMessage !is null) { return result; }

    return result;
}


// Determine the end of last UTF-8 or UTF-16 sequence in a raw buffer.
size_t endOfLastUTFSequence(C)(const C[] buffer)
    @safe pure nothrow @nogc
{
    static if(is(C == char))
    {
        for(long end = buffer.length - 1; end >= 0; --end)
        {
            const stride = utf8Stride[buffer[cast(size_t)end]];
            if(stride != 0xFF)
            {
                // If stride goes beyond end of the buffer, return end.
                // Otherwise the last sequence ends at buffer.length, so we can
                // return that. (Unless there is an invalid code unit, which is
                // caught at decoding)
                return (stride > buffer.length - end) ? cast(size_t)end : buffer.length;
            }
        }
        return 0;
    }
    else static if(is(C == wchar))
    {
        // TODO this is O(N), which is slow. Find out if we can somehow go
        // from the end backwards with UTF-16.
        size_t end = 0;
        while(end < buffer.length)
        {
            const s = stride(buffer, end);
            if(s + end > buffer.length) { break; }
            end += s;
        }
        return end;
    }
}

// UTF-8 codepoint strides (0xFF are codepoints that can't start a sequence).
immutable ubyte[256] utf8Stride =
[
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
    0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
    0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
    0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
    3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,
    4,4,4,4,4,4,4,4,5,5,5,5,6,6,0xFF,0xFF,
];
