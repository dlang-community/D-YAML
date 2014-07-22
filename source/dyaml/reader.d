
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.reader;


import core.stdc.stdlib;
import core.stdc.string;
import core.thread;

import std.algorithm;
import std.conv;
import std.exception;
import std.stdio;
import std.stream;
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
        super("Error reading stream: " ~ msg, file, line);
    }
}

/// Lazily reads and decodes data from stream, only storing as much as needed at any moment.
///
/// Adds a '\0' to the end of the stream.
final class Reader
{
    private:
        // Allocated space for buffer_.
        dchar[] bufferAllocated_ = null;
        // Buffer of currently loaded characters.
        dchar[] buffer_ = null;
        // Current position within buffer. Only data after this position can be read.
        uint bufferOffset_ = 0;
        // Index of the current character in the stream.
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
        }

        @trusted nothrow @nogc ~this()
        {
            // Delete the buffer, if allocated.
            if(bufferAllocated_ is null){return;}
            free(bufferAllocated_.ptr);
            buffer_ = bufferAllocated_ = null;
        }

        /// Get character at specified index relative to current position.
        ///
        /// Params:  index = Index of the character to get relative to current position
        ///                  in the stream.
        ///
        /// Returns: Character at specified position.
        ///
        /// Throws:  ReaderException if trying to read past the end of the stream
        ///          or if invalid data is read.
        dchar peek(size_t index = 0) @trusted
        {
            if(buffer_.length < bufferOffset_ + index + 1)
            {
                updateBuffer(index + 1);
            }

            if(buffer_.length <= bufferOffset_ + index)
            {
                throw new ReaderException("Trying to read past the end of the stream");
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
        const(dstring) prefix(size_t length) @safe
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
        const(dstring) slice(size_t start, size_t end) @trusted
        {
            if(buffer_.length <= bufferOffset_ + end)
            {
                updateBuffer(end);
            }

            end += bufferOffset_;
            start += bufferOffset_;
            end = min(buffer_.length, end);

            return end > start ? cast(dstring)buffer_[start .. end] : "";
        }

        /// Get the next character, moving stream position beyond it.
        ///
        /// Returns: Next character.
        ///
        /// Throws:  ReaderException if trying to read past the end of the stream
        ///          or if invalid data is read.
        dchar get() @safe
        {
            const result = peek();
            forward();
            return result;
        }

        /// Get specified number of characters, moving stream position beyond them.
        ///
        /// Params:  length = Number or characters to get.
        ///
        /// Returns: Characters starting at current position.
        ///
        /// Throws:  ReaderException if trying to read past the end of the stream
        ///          or if invalid data is read.
        dstring get(size_t length) @safe
        {
            auto result = prefix(length).idup;
            forward(length);
            return result;
        }

        /// Move current position forward.
        ///
        /// Params:  length = Number of characters to move position forward.
        ///
        /// Throws:  ReaderException if trying to read past the end of the stream
        ///          or if invalid data is read.
        void forward(size_t length = 1) @trusted
        {
            if(buffer_.length <= bufferOffset_ + length + 1)
            {
                updateBuffer(length + 1);
            }

            mixin FastCharSearch!"\n\u0085\u2028\u2029"d search;

            while(length > 0)
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
                else if(c != '\uFEFF'){++column_;}
                --length;
            }
        }

        /// Get a string describing current stream position, used for error messages.
        final Mark mark() @safe pure nothrow const @nogc { return Mark(line_, column_); }

        /// Get current line number.
        final uint line() @safe pure nothrow const @nogc { return line_; }

        /// Get current column number.
        final uint column() @safe pure nothrow const @nogc { return column_; }

        /// Get index of the current character in the stream.
        final size_t charIndex() @safe pure nothrow const @nogc { return charIndex_; }

        /// Get encoding of the input stream.
        final Encoding encoding() @safe pure nothrow const @nogc { return decoder_.encoding; }

    private:
        // Update buffer to be able to read length characters after buffer offset.
        //
        // If there are not enough characters in the stream, it will get
        // as many as possible.
        //
        // Params:  length = Number of characters we need to read.
        //
        // Throws:  ReaderException if trying to read past the end of the stream
        //          or if invalid data is read.
        void updateBuffer(const size_t length) @system
        {
            // Get rid of unneeded data in the buffer.
            if(bufferOffset_ > 0)
            {
                const size_t bufferLength = buffer_.length - bufferOffset_;
                memmove(buffer_.ptr, buffer_.ptr + bufferOffset_,
                        bufferLength * dchar.sizeof);
                buffer_ = buffer_[0 .. bufferLength];
                bufferOffset_ = 0;
            }

            // Load chars in batches of at most 1024 bytes (256 chars)
            while(buffer_.length <= bufferOffset_ + length)
            {
                loadChars(512);

                if(decoder_.done)
                {
                    if(buffer_.length == 0 || buffer_[$ - 1] != '\0')
                    {
                        bufferReserve(buffer_.length + 1);
                        buffer_ = bufferAllocated_[0 .. buffer_.length + 1];
                        buffer_[$ - 1] = '\0';
                    }
                    break;
                }
            }
        }

        // Load more characters to the buffer.
        //
        // Params:  chars = Recommended number of characters to load.
        //                  More characters might be loaded.
        //                  Less will be loaded if not enough available.
        //
        // Throws:  ReaderException on Unicode decoding error,
        //          if nonprintable characters are detected, or
        //          if there is an error reading from the stream.
        //
        void loadChars(size_t chars) @system
        {
            const oldLength = buffer_.length;
            const oldPosition = decoder_.position;

            bufferReserve(buffer_.length + chars);
            buffer_ = bufferAllocated_[0 .. buffer_.length + chars];
            scope(success)
            {
                buffer_ = buffer_[0 .. $ - chars];
                enforce(printable(buffer_[oldLength .. $]),
                        new ReaderException("Special unicode characters are not allowed"));
            }

            try for(size_t c = 0; chars && !decoder_.done;)
            {
                const slice = decoder_.getDChars(chars);
                buffer_[oldLength + c .. oldLength + c + slice.length] = slice[];
                c += slice.length;
                chars -= slice.length;
            }
            catch(Exception e)
            {
                handleLoadCharsException(e, oldPosition);
            }
        }

        // Handle an exception thrown in loadChars method of any Reader.
        void handleLoadCharsException(Exception e, ulong oldPosition) @system
        {
            try{throw e;}
            catch(UTFException e)
            {
                const position = decoder_.position;
                throw new ReaderException(format("Unicode decoding error between bytes %s and %s : %s",
                                          oldPosition, position, e.msg));
            }
            catch(ReadException e)
            {
                throw new ReaderException(e.msg);
            }
        }

        // Code shared by loadEntireFile methods.
        void loadEntireFile_() @system
        {
            const maxChars = decoder_.maxChars;
            bufferReserve(maxChars + 1);
            loadChars(maxChars);

            if(buffer_.length == 0 || buffer_[$ - 1] != '\0')
            {
                buffer_ = bufferAllocated_[0 .. buffer_.length + 1];
                buffer_[$ - 1] = '\0';
            }
        }

        // Ensure there is space for at least capacity characters in bufferAllocated_.
        void bufferReserve(const size_t capacity) @system nothrow
        {
            if(bufferAllocated_ !is null && bufferAllocated_.length >= capacity){return;}

            // Handle first allocation as well as reallocation.
            auto ptr = bufferAllocated_ !is null
                       ? realloc(bufferAllocated_.ptr, capacity * dchar.sizeof)
                       : malloc(capacity * dchar.sizeof);
            bufferAllocated_ = (cast(dchar*)ptr)[0 .. capacity];
            buffer_ = bufferAllocated_[0 .. buffer_.length];
        }
}

private:

alias UTFBlockDecoder!512 UTFFastDecoder;

/// Decodes streams to UTF-32 in blocks.
struct UTFBlockDecoder(size_t bufferSize_) if (bufferSize_ % 2 == 0)
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

        // Encoding of the input stream.
        UTFEncoding encoding_;
        // Maximum number of characters that might be in the stream.
        size_t maxChars_;
        // The entire input buffer.
        ubyte[] inputAll_;
        // Part of the input buffer that has not yet been decoded.
        ubyte[] input_;

        // Buffer used to store raw UTF-8 or UTF-16 code points.
        union
        {
            char[bufferSize_] rawBuffer8_;
            wchar[bufferSize_ / 2] rawBuffer16_;
        }
        // Used space (in items) in rawBuffer8_/rawBuffer16_.
        size_t rawUsed_;

        // Space used by decoded_.
        dchar[bufferSize_] decodedSpace_;
        // Buffer of decoded, UTF-32 characters. This is a slice into decodedSpace_.
        dchar[] decoded_;

    public:
        /// Construct a UTFBlockDecoder decoding data from a buffer.
        this(ubyte[] buffer, UTFEncoding encoding) @trusted
        {
            inputAll_ = buffer;
            input_    = inputAll_[];
            encoding_ = encoding;
            final switch(encoding_)
            {
                case UTFEncoding.UTF_8:  maxChars_ = input_.length;     break;
                case UTFEncoding.UTF_16: maxChars_ = input_.length / 2; break;
                case UTFEncoding.UTF_32: maxChars_ = input_.length / 2; break;
            }
        }

        /// Get maximum number of characters that might be in the stream.
        size_t maxChars() const pure @safe nothrow @nogc { return maxChars_; }

        /// Get encoding we're decoding from.
        UTFEncoding encoding() const pure @safe nothrow @nogc { return encoding_; }

        /// Get the current position in buffer.
        size_t position() @trusted { return inputAll_.length - input_.length; }

        /// Are we done decoding?
        bool done() const pure @safe nothrow @nogc
        {
            return rawUsed_ == 0 && decoded_.length == 0 && input_.length == 0;
        }

        /// Get next character.
        dchar getDChar()
            @safe
        {
            if(decoded_.length)
            {
                const result = decoded_[0];
                decoded_ = decoded_[1 .. $];
                return result;
            }

            assert(input_.length > 0 || rawUsed_ > 0);
            updateBuffer();
            return getDChar();
        }

        /// Get as many characters as possible, but at most maxChars. Slice returned will be invalidated in further calls.
        const(dchar[]) getDChars(size_t maxChars = size_t.max)
            @safe
        {
            if(decoded_.length)
            {
                const slice = min(decoded_.length, maxChars);
                const result = decoded_[0 .. slice];
                decoded_ = decoded_[slice .. $];
                return result;
            }

            assert(input_.length > 0 || rawUsed_ > 0);
            updateBuffer();
            return getDChars(maxChars);
        }

    private:
        // Read and decode characters from file and store them in the buffer.
        void updateBuffer() @trusted
        {
            assert(decoded_.length == 0,
                   "updateBuffer can only be called when the buffer is empty");
            final switch(encoding_)
            {
                case UTFEncoding.UTF_8:
                    const bytes = min(bufferSize_ - rawUsed_, input_.length);
                    // Current length of valid data in rawBuffer8_.
                    const rawLength = rawUsed_ + bytes;
                    rawBuffer8_[rawUsed_ .. rawUsed_ + bytes] = cast(char[])input_[0 .. bytes];
                    input_ = input_[bytes .. $];
                    decodeRawBuffer(rawBuffer8_, rawLength);
                    break;
                case UTFEncoding.UTF_16:
                    const words = min((bufferSize_ / 2) - rawUsed_, input_.length / 2);
                    // Current length of valid data in rawBuffer16_.
                    const rawLength = rawUsed_ + words;
                    foreach(c; rawUsed_ .. rawLength)
                    {
                        rawBuffer16_[c] = *cast(wchar*)input_.ptr;
                        input_ = input_[2 .. $];
                    }
                    decodeRawBuffer(rawBuffer16_, rawLength);
                    break;
                case UTFEncoding.UTF_32:
                    const chars = min(bufferSize_ / 4, input_.length / 4);
                    foreach(c; 0 .. chars)
                    {
                        decodedSpace_[c] = *cast(dchar*)input_.ptr;
                        input_ = input_[4 .. $];
                    }
                    decoded_ = decodedSpace_[0 .. chars];
                    break;
            }
        }

        // Decode contents of a UTF-8 or UTF-16 raw buffer.
        void decodeRawBuffer(C)(C[] buffer, const size_t length)
            @safe pure
        {
            // End of part of rawBuffer8_ that contains
            // complete characters and can be decoded.
            const end = endOfLastUTFSequence(buffer, length);
            // If end is 0, there are no full UTF-8 chars.
            // This can happen at the end of file if there is an incomplete UTF-8 sequence.
            enforce(end > 0,
                    new ReaderException("Invalid UTF-8 character at the end of stream"));

            decodeUTF(buffer[0 .. end]);

            // After decoding, any code points not decoded go to the start of raw buffer.
            rawUsed_ = length - end;
            foreach(i; 0 .. rawUsed_) { buffer[i] = buffer[i + end]; }
        }

        // Determine the end of last UTF-8 or UTF-16 sequence in a raw buffer.
        size_t endOfLastUTFSequence(C)(const C[] buffer, const size_t max)
            @safe pure nothrow const @nogc
        {
            static if(is(C == char))
            {
                for(long end = max - 1; end >= 0; --end)
                {
                    const s = utf8Stride[buffer[cast(size_t)end]];
                    if(s != 0xFF)
                    {
                        // If stride goes beyond end of the buffer (max), return end.
                        // Otherwise the last sequence ends at max, so we can return that.
                        // (Unless there is an invalid code point, which is
                        // caught at decoding)
                        return (s > max - end) ?  cast(size_t)end : max;
                    }
                }
                return 0;
            }
            else
            {
                size_t end = 0;
                while(end < max)
                {
                    const s = stride(buffer, end);
                    if(s + end > max) { break; }
                    end += s;
                }
                return end;
            }
        }

        // Decode a UTF-8 or UTF-16 buffer (with no incomplete sequences at the end).
        void decodeUTF(C)(const C[] source) @safe pure
        {
            size_t bufpos = 0;
            const srclength = source.length;
            for(size_t srcpos = 0; srcpos < srclength;)
            {
                const c = source[srcpos];
                if(c < 0x80)
                {
                    decodedSpace_[bufpos++] = c;
                    ++srcpos;
                }
                else
                {
                    decodedSpace_[bufpos++] = decode(source, srcpos);
                }
            }
            decoded_ = decodedSpace_[0 .. bufpos];
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

//Unittests.

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
