
//          Copyright Ferdinand Majerech 2011.
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

import dyaml.fastcharsearch;
import dyaml.encoding;
import dyaml.exception;


package:

///Exception thrown at Reader errors.
class ReaderException : YAMLException
{
    this(string msg, string file = __FILE__, int line = __LINE__)
        @safe pure nothrow
    {
        super("Error reading stream: " ~ msg, file, line);
    }
}

///Lazily reads and decodes data from stream, only storing as much as needed at any moment.
final class Reader
{
    private:
        //Input stream.
        EndianStream stream_;
        //Allocated space for buffer_.
        dchar[] bufferAllocated_ = null;
        //Buffer of currently loaded characters.
        dchar[] buffer_ = null;
        //Current position within buffer. Only data after this position can be read.
        uint bufferOffset_ = 0;
        //Index of the current character in the stream.
        size_t charIndex_ = 0;
        //Current line in file.
        uint line_;
        //Current column in file.
        uint column_;
        //Decoder reading data from file and decoding it to UTF-32.
        UTFFastDecoder decoder_;

    public:
        /*
         * Construct an AbstractReader.
         *
         * Params:  stream = Input stream. Must be readable and seekable.
         *
         * Throws:  ReaderException if the stream is invalid.
         */
        this(Stream stream) @trusted //!nothrow
        in
        {
            assert(stream.readable && stream.seekable, 
                   "Can't read YAML from a stream that is not readable and seekable");
        }
        body
        {
            stream_ = new EndianStream(stream);
            decoder_ = UTFFastDecoder(stream_);
        }

        @trusted nothrow @nogc ~this() 
        {
            //Delete the buffer, if allocated.
            if(bufferAllocated_ is null){return;}
            free(bufferAllocated_.ptr);
            buffer_ = bufferAllocated_ = null;
        }

        /**
         * Get character at specified index relative to current position.
         *
         * Params:  index = Index of the character to get relative to current position 
         *                  in the stream.
         *
         * Returns: Character at specified position.
         *
         * Throws:  ReaderException if trying to read past the end of the stream
         *          or if invalid data is read.
         */
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

        /**
         * Get specified number of characters starting at current position.
         *
         * Note: This gets only a "view" into the internal buffer,
         *       which WILL get invalidated after other Reader calls.
         *
         * Params:  length = Number of characters to get.
         *
         * Returns: Characters starting at current position or an empty slice if out of bounds.
         */
        const(dstring) prefix(size_t length) @safe
        {
            return slice(0, length);
        }

        /**
         * Get a slice view of the internal buffer.
         *
         * Note: This gets only a "view" into the internal buffer,
         *       which WILL get invalidated after other Reader calls.
         *
         * Params:  start = Start of the slice relative to current position.
         *          end   = End of the slice relative to current position.
         *
         * Returns: Slice into the internal buffer or an empty slice if out of bounds.
         */
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

        /**
         * Get the next character, moving stream position beyond it.
         *
         * Returns: Next character.
         *
         * Throws:  ReaderException if trying to read past the end of the stream
         *          or if invalid data is read.
         */
        dchar get() @safe
        {
            const result = peek();
            forward();
            return result;
        }

        /**
         * Get specified number of characters, moving stream position beyond them.
         *
         * Params:  length = Number or characters to get.
         *
         * Returns: Characters starting at current position.
         *
         * Throws:  ReaderException if trying to read past the end of the stream
         *          or if invalid data is read.
         */
        dstring get(size_t length) @safe
        {
            auto result = prefix(length).idup;
            forward(length);
            return result;
        }

        /**
         * Move current position forward.
         *
         * Params:  length = Number of characters to move position forward.
         *
         * Throws:  ReaderException if trying to read past the end of the stream
         *          or if invalid data is read.
         */
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

        ///Get a string describing current stream position, used for error messages.
        @property final Mark mark() const pure @safe nothrow {return Mark(line_, column_);}

        ///Get current line number.
        @property final uint line() const pure @safe nothrow {return line_;}

        ///Get current column number.
        @property final uint column() const pure @safe nothrow {return column_;}

        ///Get index of the current character in the stream.
        @property final size_t charIndex() const pure @safe nothrow {return charIndex_;}

        ///Get encoding of the input stream.
        @property final Encoding encoding() const pure @safe nothrow {return decoder_.encoding;}

    private:
        /**
         * Update buffer to be able to read length characters after buffer offset.
         *
         * If there are not enough characters in the stream, it will get
         * as many as possible.
         *
         * Params:  length = Number of characters we need to read.
         *
         * Throws:  ReaderException if trying to read past the end of the stream
         *          or if invalid data is read.
         */
        void updateBuffer(in size_t length) @system
        {
            //Get rid of unneeded data in the buffer.
            if(bufferOffset_ > 0)
            {
                size_t bufferLength = buffer_.length - bufferOffset_;
                memmove(buffer_.ptr, buffer_.ptr + bufferOffset_,
                        bufferLength * dchar.sizeof);
                buffer_ = buffer_[0 .. bufferLength];
                bufferOffset_ = 0;
            }

            //Load chars in batches of at most 1024 bytes (256 chars)
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

        /**
         * Load more characters to the buffer.
         *
         * Params:  chars = Recommended number of characters to load. 
         *                  More characters might be loaded.
         *                  Less will be loaded if not enough available.
         *
         * Throws:  ReaderException on Unicode decoding error,
         *          if nonprintable characters are detected, or
         *          if there is an error reading from the stream.
         */
        void loadChars(size_t chars) @system
        {
            const oldLength = buffer_.length;
            const oldPosition = stream_.position;

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

        //Handle an exception thrown in loadChars method of any Reader.
        void handleLoadCharsException(Exception e, ulong oldPosition) @system
        {
            try{throw e;}
            catch(UTFException e)
            {
                const position = stream_.position;
                throw new ReaderException(format("Unicode decoding error between bytes %s and %s : %s",
                                          oldPosition, position, e.msg));
            }
            catch(ReadException e)
            {
                throw new ReaderException(e.msg);
            }
        }

        //Code shared by loadEntireFile methods.
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

        //Ensure there is space for at least capacity characters in bufferAllocated_.
        void bufferReserve(in size_t capacity) @system nothrow
        {
            if(bufferAllocated_ !is null && bufferAllocated_.length >= capacity){return;}

            //Handle first allocation as well as reallocation.
            auto ptr = bufferAllocated_ !is null 
                       ? realloc(bufferAllocated_.ptr, capacity * dchar.sizeof)
                       : malloc(capacity * dchar.sizeof);
            bufferAllocated_ = (cast(dchar*)ptr)[0 .. capacity];
            buffer_ = bufferAllocated_[0 .. buffer_.length];
        }
}

private:

alias UTFBlockDecoder!512 UTFFastDecoder;

///Decodes streams to UTF-32 in blocks.
struct UTFBlockDecoder(size_t bufferSize_) if (bufferSize_ % 2 == 0)
{
    private:
        //UTF-8 codepoint strides (0xFF are codepoints that can't start a sequence).
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

        //Encoding of the input stream.
        Encoding encoding_;
        //Maximum number of characters that might be in the stream.
        size_t maxChars_;
        //Bytes available in the stream.
        size_t available_;
        //Input stream.
        EndianStream stream_;

        //Buffer used to store raw UTF-8 or UTF-16 code points.
        union
        {
            char[bufferSize_] rawBuffer8_;
            wchar[bufferSize_ / 2] rawBuffer16_;
        }
        //Used space (in items) in rawBuffer8_/rawBuffer16_.
        size_t rawUsed_;

        //Space used by buffer_.
        dchar[bufferSize_] bufferSpace_;
        //Buffer of decoded, UTF-32 characters. This is a slice into bufferSpace_.
        dchar[] buffer_;

    public:
        ///Construct a UTFBlockDecoder decoding a stream.
        this(EndianStream stream) @trusted //!nothrow
        {
            stream_ = stream;
            available_ = stream_.available;

            //Handle files short enough not to have a BOM.
            if(available_ < 2)
            {
                encoding_ = Encoding.UTF_8;
                maxChars_ = 0;

                if(available_ == 1)
                {
                    bufferSpace_[0] = stream_.getc();
                    buffer_         = bufferSpace_[0 .. 1];
                    maxChars_       = 1;
                }
                return;
            }

            char[] rawBuffer8;
            wchar[] rawBuffer16;
            //readBOM will determine and set stream endianness.
            switch(stream_.readBOM(2))
            {
                case -1: 
                    //readBOM() eats two more bytes in this case so get them back.
                    const wchar bytes = stream_.getcw();
                    rawBuffer8_[0 .. 2] = [cast(ubyte)(bytes % 256), cast(ubyte)(bytes / 256)];
                    rawUsed_ = 2;
                    goto case 0;
                case 0:  
                    maxChars_ = available_;
                    encoding_ = Encoding.UTF_8; 
                    break;
                case 1, 2: 
                    maxChars_ = available_ / 2;
                    //readBOM() eats two more bytes in this case so get them back.
                    encoding_ = Encoding.UTF_16; 
                    rawBuffer16_[0] = stream_.getcw();
                    rawUsed_ = 1;
                    enforce(available_ % 2 == 0, 
                            new ReaderException("Odd byte count in an UTF-16 stream"));
                    break;
                case 3, 4: 
                    maxChars_ = available_ / 4;
                    encoding_ = Encoding.UTF_32;
                    enforce(available_ % 4 == 0, 
                            new ReaderException("Byte count in an UTF-32 stream not divisible by 4"));
                    break;
                default: assert(false, "Unknown UTF BOM");
            }
            available_ = stream_.available;
        }

        ///Get maximum number of characters that might be in the stream.
        @property size_t maxChars() const pure @safe nothrow @nogc { return maxChars_; }

        ///Get encoding we're decoding from.
        @property Encoding encoding() const pure @safe nothrow @nogc { return encoding_; }

        ///Are we done decoding?
        @property bool done() const pure @safe nothrow @nogc
        {   
            return rawUsed_ == 0 && buffer_.length == 0 && available_ == 0;
        }

        ///Get next character.
        dchar getDChar() @safe
        {
            if(buffer_.length)
            {
                const result = buffer_[0];
                buffer_ = buffer_[1 .. $];
                return result;
            }

            assert(available_ > 0 || rawUsed_ > 0);
            updateBuffer();
            return getDChar();
        }

        ///Get as many characters as possible, but at most maxChars. Slice returned will be invalidated in further calls.
        const(dchar[]) getDChars(size_t maxChars = size_t.max) @safe
        {
            if(buffer_.length)
            {
                const slice = min(buffer_.length, maxChars);
                const result = buffer_[0 .. slice];
                buffer_ = buffer_[slice .. $];
                return result;
            }

            assert(available_ > 0 || rawUsed_ > 0);
            updateBuffer();
            return getDChars(maxChars);
        }

    private:
        // Read and decode characters from file and store them in the buffer.
        void updateBuffer() @trusted
        {
            assert(buffer_.length == 0, 
                   "updateBuffer can only be called when the buffer is empty");
            final switch(encoding_)
            {
                case Encoding.UTF_8:
                    const bytes = min(bufferSize_ - rawUsed_, available_);
                    //Current length of valid data in rawBuffer8_.
                    const rawLength = rawUsed_ + bytes;
                    stream_.readExact(rawBuffer8_.ptr + rawUsed_, bytes);
                    available_ -= bytes;
                    decodeRawBuffer(rawBuffer8_, rawLength);
                    break;
                case Encoding.UTF_16:
                    const words = min((bufferSize_ / 2) - rawUsed_, available_ / 2);
                    //Current length of valid data in rawBuffer16_.
                    const rawLength = rawUsed_ + words;
                    foreach(c; rawUsed_ .. rawLength)
                    {
                        stream_.read(rawBuffer16_[c]);
                        available_ -= 2;
                    }
                    decodeRawBuffer(rawBuffer16_, rawLength);
                    break;
                case Encoding.UTF_32:
                    const chars = min(bufferSize_ / 4, available_ / 4);
                    foreach(c; 0 .. chars)
                    {
                        stream_.read(bufferSpace_[c]);
                        available_ -= 4;
                    }
                    buffer_ = bufferSpace_[0 .. chars];
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
                    bufferSpace_[bufpos++] = c;
                    ++srcpos;
                }
                else
                {
                    bufferSpace_[bufpos++] = decode(source, srcpos);
                }
            }
            buffer_ = bufferSpace_[0 .. bufpos]; 
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
        Reader reader = new R(new MemoryStream(data));
        assert(reader.encoding == encoding_expected);
        assert(reader.stream_.endian == endian_expected);
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
    Reader reader = new R(new MemoryStream(data));
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
        Reader reader = new R(new MemoryStream(bytes));
        assert(reader.peek() == 'd');
        assert(reader.peek(1) == 'a');
        assert(reader.peek(2) == 't');
        assert(reader.peek(3) == 'a');
    }
    utf_test!char(to!(char[])(data), BOM.UTF8);
    utf_test!wchar(to!(wchar[])(data), endian == Endian.bigEndian ? BOM.UTF16BE : BOM.UTF16LE);
    utf_test(data, endian == Endian.bigEndian ? BOM.UTF32BE : BOM.UTF32LE);
}

unittest
{
    testEndian!Reader();
    testPeekPrefixForward!Reader();
    testUTF!Reader();
}
