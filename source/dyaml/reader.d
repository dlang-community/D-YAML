
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.reader;


import core.stdc.stdlib;
import core.stdc.string;
import core.thread;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.stdio;
import std.string;
import std.system;
import std.utf;

import tinyendian;

import dyaml.fastcharsearch;
import dyaml.encoding;
import dyaml.exception;
import dyaml.streamcompat;



package:

//XXX VIM STUFF:
//XXX THE f/t COLORING PLUGIN, AND TRY TO REMOVE THE f/t AUTOREPEAT PLUGIN
// (AND MAYBE DO THE REPEAT WITH ALT-T/ALT-F
//XXX DDOC snippets such as $D, $BIGOH, anything else
//    OR MAYBE JUST $ - EXPANDING TO $(${1} ${2})
//    WHERE DEFAULT ${1} IS 'D' AND SPECIAL SNIPPETS FOR SPECIFIC DDOC MACROS
//    (E.G. XREF HAS 2 ARGS)
// XXX DON'T FORGET TO COMMIT DSNIPS CHANGES
// XXX SNIPPETS: WHY CAN'T WE USE NEW IN NEW? FIX!
// XXX ALSO WRITELN VISUAL! (print whatever we have selected)
// XXX AND ``fun`` VISUAL TOO!
// XXX snippet to print variable along its name AND
// OR MULTIPLE VARS - USE std.format!




///Exception thrown at Reader errors.
class ReaderException : YAMLException
{
    this(string msg, string file = __FILE__, int line = __LINE__)
        @safe pure nothrow
    {
        super("Reader error: " ~ msg, file, line);
    }
}

/// Lazily reads and decodes data from a buffer, only storing as much as needed at any
/// moment.
///
/// Adds a '\0' to the end of the data.
final class Reader
{
    private:
        // Buffer of currently loaded characters.
        dchar[] buffer_ = null;
        // Current position within buffer. Only data after this position can be read.
        uint bufferOffset_ = 0;
        // Index of the current character in the buffer.
        size_t charIndex_ = 0;
        // Current line in file.
        uint line_;
        // Current column in file.
        uint column_;
        // Decoder reading data from file and decoding it to UTF-32.
        UTFFastDecoder decoder_;

        version(unittest)
        {
            // Endianness of the input before it was converted (for testing)
            Endian endian_;
        }

    public:
        import std.stream;
        /// Construct a Reader.
        ///
        /// Params:  stream = Input stream. Must be readable and seekable.
        ///
        /// Throws:  ReaderException if the stream is invalid.
        this(Stream stream) @trusted //!nothrow
        {
            auto streamBytes = streamToBytesGC(stream);
            auto result = fixUTFByteOrder(streamBytes);
            if(result.bytesStripped > 0)
            {
                throw new ReaderException("Size of UTF-16 or UTF-32 input not aligned "
                                          "to 2 or 4 bytes, respectively");
            }

            version(unittest) { endian_ = result.endian; }
            decoder_ = UTFFastDecoder(result.array, result.encoding);
            decoder_.decodeAll();
            const msg = decoder_.getAndClearErrorMessage();

            if(msg !is null)
            {
                throw new ReaderException("UTF decoding error: " ~ msg);
            }

            buffer_ = decoder_.decoded;

            // The part of buffer excluding trailing zeroes.
            auto noZeros = buffer_;
            while(!noZeros.empty && noZeros.back == '\0') { noZeros.popBack(); }
            enforce(printable(noZeros[]),
                    new ReaderException("Special unicode characters are not allowed"));
        }

        /// Get character at specified index relative to current position.
        ///
        /// Params:  index = Index of the character to get relative to current position
        ///                  in the buffer.
        ///
        /// Returns: Character at specified position.
        ///
        /// Throws:  ReaderException if trying to read past the end of the buffer
        ///          or if invalid data is read.
        dchar peek(size_t index = 0) @safe pure const
        {
            if(buffer_.length <= bufferOffset_ + index)
            {
                throw new ReaderException("Trying to read past the end of the buffer");
            }

            return buffer_[bufferOffset_ + index];
        }

        /// Get specified number of characters starting at current position.
        ///
        /// Note: This gets only a "view" into the internal buffer,
        ///       which WILL get invalidated after other Reader calls.
        ///
        /// Params:  length = Number of characters to get.
        ///
        /// Returns: Characters starting at current position or an empty slice if out of bounds.
        const(dstring) prefix(size_t length) @safe pure nothrow const @nogc
        {
            return slice(0, length);
        }

        /// Get a slice view of the internal buffer.
        ///
        /// Note: This gets only a "view" into the internal buffer,
        ///       which WILL get invalidated after other Reader calls.
        ///
        /// Params:  start = Start of the slice relative to current position.
        ///          end   = End of the slice relative to current position.
        ///
        /// Returns: Slice into the internal buffer or an empty slice if out of bounds.
        const(dstring) slice(size_t start, size_t end) @trusted pure nothrow const @nogc
        {
            end += bufferOffset_;
            start += bufferOffset_;
            end = min(buffer_.length, end);

            return end > start ? cast(dstring)buffer_[start .. end] : "";
        }

        /// Get the next character, moving buffer position beyond it.
        ///
        /// Returns: Next character.
        ///
        /// Throws:  ReaderException if trying to read past the end of the buffer
        ///          or if invalid data is read.
        dchar get() @safe pure
        {
            const result = peek();
            forward();
            return result;
        }

        /// Get specified number of characters, moving buffer position beyond them.
        ///
        /// Params:  length = Number or characters to get.
        ///
        /// Returns: Characters starting at current position.
        dstring get(size_t length) @safe pure nothrow
        {
            auto result = prefix(length).idup;
            forward(length);
            return result;
        }

        /// Move current position forward.
        ///
        /// Params:  length = Number of characters to move position forward.
        void forward(size_t length = 1) @safe pure nothrow @nogc
        {
            mixin FastCharSearch!"\n\u0085\u2028\u2029"d search;

            for(; length > 0; --length)
            {
                const c = buffer_[bufferOffset_];
                ++bufferOffset_;
                ++charIndex_;
                //New line.
                if(search.canFind(c) || (c == '\r' && buffer_[bufferOffset_] != '\n'))
                {
                    ++line_;
                    column_ = 0;
                }
                else if(c != '\uFEFF') { ++column_; }
            }
        }

        /// Get a string describing current buffer position, used for error messages.
        final Mark mark() @safe pure nothrow const @nogc { return Mark(line_, column_); }

        /// Get current line number.
        final uint line() @safe pure nothrow const @nogc { return line_; }

        /// Get current column number.
        final uint column() @safe pure nothrow const @nogc { return column_; }

        /// Get index of the current character in the buffer.
        final size_t charIndex() @safe pure nothrow const @nogc { return charIndex_; }

        /// Get encoding of the input buffer.
        final Encoding encoding() @safe pure nothrow const @nogc { return decoder_.encoding; }
}

private:

alias UTFDecoder UTFFastDecoder;

struct UTFDecoder
{
    private:
        // UTF-8 codepoint strides (0xFF are codepoints that can't start a sequence).
        static immutable ubyte[256] utf8Stride =
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

        // Encoding of the input buffer.
        UTFEncoding encoding_;
        // Maximum number of characters that might be in the buffer.
        size_t maxChars_;
        // Part of the input buffer that has not yet been decoded.
        ubyte[] input_;

        // Decoded (UTF-32) version of the entire input_. If input is UTF-32, this is
        // just a reference to input_.
        dchar[] decoded_;

        // Current error message.
        //
        // To be fully nothrow, we use return values and the user (Reader) can check
        // for a detailed error message if they get an error return.
        string errorMessage_;

    public:
        /// Construct a UTFBlockDecoder decoding data from a buffer.
        this(ubyte[] buffer, UTFEncoding encoding) @safe pure nothrow @nogc
        {
            input_    = buffer;
            encoding_ = encoding;
            final switch(encoding_)
            {
                case UTFEncoding.UTF_8:  maxChars_ = input_.length;     break;
                case UTFEncoding.UTF_16: maxChars_ = input_.length / 2; break;
                case UTFEncoding.UTF_32: maxChars_ = input_.length / 2; break;
            }
        }

        /// Decode all data passed to the constructor.
        ///
        /// On error, getAndClearErrorMessage() will return a non-null string.
        void decodeAll() @safe
        {
            assert(decoded_ is null, "Calling decodeAll more than once");

            final switch(encoding_)
            {
                case UTFEncoding.UTF_8:  decode(cast(char[])input_); break;
                case UTFEncoding.UTF_16:
                    assert(input_.length % 2 == 0, "UTF-16 buffer size must be even");
                    decode(cast(wchar[])input_);
                    break;
                case UTFEncoding.UTF_32:
                    assert(input_.length % 4 == 0,
                           "UTF-32 buffer size must be a multiple of 4");
                    // No need to decode anything
                    decoded_ = cast(dchar[])input_;
                    break;
            }
            // The buffer must be zero terminated for scanner to detect its end.
            if(decoded_.empty || decoded_.back() != '\0')
            {
                decoded_ ~= cast(dchar)'\0';
            }
        }

        /// Get encoding we're decoding from.
        UTFEncoding encoding() const pure @safe nothrow @nogc { return encoding_; }

        /// Get all decoded characters.
        const(dchar[]) decoded() @safe pure nothrow @nogc { return decoded_; }

        /// Get the error message and clear it.
        string getAndClearErrorMessage() @safe pure nothrow @nogc
        {
            const result = errorMessage_;
            errorMessage_ = null;
            return result;
        }

    private:
        // Decode input_ if it's encoded as UTF-8 or UTF-16.
        //
        // On error, errorMessage_ will be set.
        void decode(C)(C[] buffer) @safe pure nothrow
        {
            // End of part of buffer that contains complete characters that can be decoded.
            const size_t end = endOfLastUTFSequence(buffer);
            // If end is 0, there are no full chars.
            // This can happen at the end of file if there is an incomplete UTF sequence.
            if(end < buffer.length)
            {
                errorMessage_ = "Invalid UTF character at the end of buffer";
                return;
            }

            const srclength = buffer.length;
            try for(size_t srcpos = 0; srcpos < srclength;)
            {
                const c = buffer[srcpos];
                if(c < 0x80)
                {
                    decoded_ ~= c;
                    ++srcpos;
                }
                else
                {
                    decoded_ ~= std.utf.decode(buffer, srcpos);
                }
            }
            catch(UTFException e)
            {
                errorMessage_ = e.msg;
                return;
            }
            catch(Exception e)
            {
                assert(false, "Unexpected exception in decode(): " ~ e.msg);
            }
        }

        // Determine the end of last UTF-8 or UTF-16 sequence in a raw buffer.
        size_t endOfLastUTFSequence(C)(const C[] buffer)
            @safe pure nothrow const @nogc
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
                        // return that. (Unless there is an invalid code point, which is
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
}

/// Determine if all characters in an array are printable.
///
/// Params:  chars = Characters to check.
///
/// Returns: True if all the characters are printable, false otherwise.
bool printable(const dchar[] chars) @safe pure nothrow @nogc
{
    foreach(c; chars)
    {
        if(!((c == 0x09 || c == 0x0A || c == 0x0D || c == 0x85) ||
             (c >= 0x20 && c <= 0x7E) ||
             (c >= 0xA0 && c <= '\uD7FF') ||
             (c >= '\uE000' && c <= '\uFFFD')))
        {
            return false;
        }
    }
    return true;
}

// Unittests.

import std.stream;
void testEndian(R)()
{
    writeln(typeid(R).toString() ~ ": endian unittest");
    void endian_test(ubyte[] data, Encoding encoding_expected, Endian endian_expected)
    {
        auto reader = new R(new MemoryStream(data));
        assert(reader.encoding == encoding_expected);
        assert(reader.endian_ == endian_expected);
    }
    ubyte[] little_endian_utf_16 = [0xFF, 0xFE, 0x7A, 0x00];
    ubyte[] big_endian_utf_16 = [0xFE, 0xFF, 0x00, 0x7A];
    endian_test(little_endian_utf_16, Encoding.UTF_16, Endian.littleEndian);
    endian_test(big_endian_utf_16, Encoding.UTF_16, Endian.bigEndian);
}

void testPeekPrefixForward(R)()
{
    writeln(typeid(R).toString() ~ ": peek/prefix/forward unittest");
    ubyte[] data = ByteOrderMarks[BOM.UTF8] ~ cast(ubyte[])"data";
    auto reader = new R(new MemoryStream(data));
    assert(reader.peek() == 'd');
    assert(reader.peek(1) == 'a');
    assert(reader.peek(2) == 't');
    assert(reader.peek(3) == 'a');
    assert(reader.peek(4) == '\0');
    assert(reader.prefix(4) == "data");
    assert(reader.prefix(6) == "data\0");
    reader.forward(2);
    assert(reader.peek(1) == 'a');
    assert(collectException(reader.peek(3)));
}

void testUTF(R)()
{
    writeln(typeid(R).toString() ~ ": UTF formats unittest");
    dchar[] data = cast(dchar[])"data";
    void utf_test(T)(T[] data, BOM bom)
    {
        ubyte[] bytes = ByteOrderMarks[bom] ~
                        (cast(ubyte*)data.ptr)[0 .. data.length * T.sizeof];
        auto reader = new R(new MemoryStream(bytes));
        assert(reader.peek() == 'd');
        assert(reader.peek(1) == 'a');
        assert(reader.peek(2) == 't');
        assert(reader.peek(3) == 'a');
    }
    utf_test!char(to!(char[])(data), BOM.UTF8);
    utf_test!wchar(to!(wchar[])(data), endian == Endian.bigEndian ? BOM.UTF16BE : BOM.UTF16LE);
    utf_test(data, endian == Endian.bigEndian ? BOM.UTF32BE : BOM.UTF32LE);
}

void test1Byte(R)()
{
    writeln(typeid(R).toString() ~ ": 1 byte file unittest");
    ubyte[] data = [97];

    auto reader = new R(new MemoryStream(data));
    assert(reader.peek() == 'a');
    assert(reader.peek(1) == '\0');
    assert(collectException(reader.peek(2)));
}

unittest
{
    testEndian!Reader();
    testPeekPrefixForward!Reader();
    testUTF!Reader();
    test1Byte!Reader();
}
