
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.reader;


import core.stdc.string;

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
    {
        super("Error reading stream: " ~ msg, file, line);
    }
}

///Reads data from a stream and converts it to UTF-32 (dchar) data.
final class Reader
{
    private:
        ///Input stream.
        EndianStream stream_;
        ///Buffer of currently loaded characters.
        dchar[] buffer_;
        ///Current position within buffer. Only data after this position can be read.
        uint bufferOffset_ = 0;
        ///Index of the current character in the stream.
        size_t charIndex_ = 0;
        ///Encoding of the input stream.
        Encoding encoding_;
        ///Current line in file.
        uint line_;
        ///Current column in file.
        uint column_;
        ///Number of bytes still available (not read) in the stream.
        size_t available_;

        ///Capacity of raw buffers.
        static immutable bufferLength8_ = 8;
        ///Capacity of raw buffers.
        static immutable bufferLength16_ = bufferLength8_ / 2;

        union
        {
            ///Buffer to hold UTF-8 data before decoding.
            char[bufferLength8_ + 1] rawBuffer8_;
            ///Buffer to hold UTF-16 data before decoding.
            wchar[bufferLength16_ + 1] rawBuffer16_;
        }
        ///Number of elements held in the used raw buffer.
        uint rawUsed_ = 0;

    public:
        /**
         * Construct a Reader.
         *
         * Params:  stream = Input stream. Must be readable and seekable.
         *
         * Throws:  ReaderException if the stream is invalid.
         */
        this(Stream stream)
        in
        {
            assert(stream.readable && stream.seekable, 
                   "Can't read YAML from a stream that is not readable and seekable");
        }
        body
        {
            stream_ = new EndianStream(stream);
            available_ = stream_.available;

            //handle files short enough not to have a BOM
            if(available_ < 2)
            {
                encoding_ = Encoding.UTF_8;
                return;
            }

            //readBOM will determine and set stream endianness
            switch(stream_.readBOM(2))
            {
                case -1: 
                    //readBOM() eats two more bytes in this case so get them back
                    wchar bytes = stream_.getcw();
                    rawBuffer8_[0] = cast(char)(bytes % 256);
                    rawBuffer8_[1] = cast(char)(bytes / 256);
                    rawUsed_ = 2;
                    goto case 0;
                case 0:  encoding_ = Encoding.UTF_8; break;
                case 1, 2: 
                    //readBOM() eats two more bytes in this case so get them back
                    encoding_ = Encoding.UTF_16; 
                    rawBuffer16_[0] = stream_.getcw();
                    rawUsed_ = 1;
                    enforce(available_ % 2 == 0, 
                            new ReaderException("Odd byte count in an UTF-16 stream"));
                    break;
                case 3, 4: 
                    enforce(available_ % 4 == 0, 
                            new ReaderException("Byte count in an UTF-32 stream not divisible by 4"));
                    encoding_ = Encoding.UTF_32;
                    break;
                default: assert(false, "Unknown UTF BOM");
            }
            available_ = stream_.available;
        }

        ///Destroy the Reader.
        ~this()
        {
            clear(buffer_);
            buffer_ = null;
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
        dchar peek(in size_t index = 0)
        {
            updateBuffer(index + 1);

            if(buffer_.length < bufferOffset_ + index + 1)
            {
                throw new ReaderException("Trying to read past the end of the stream");
            }

            return buffer_[bufferOffset_ + index];
        }

        /**
         * Get specified number of characters starting at current position.
         *
         * Params: length = Number of characters to get.
         *
         * Returns: Characters starting at current position.
         *
         * Throws:  ReaderException if trying to read past the end of the stream
         *          or if invalid data is read.
         */
        dstring prefix(in size_t length)
        {
            if(length == 0){return "";}
            updateBuffer(length);
            const end = min(buffer_.length, bufferOffset_ + length);
            //need to duplicate as we change buffer content with C functions
            //and could end up with returned string referencing changed data
            return cast(dstring)buffer_[bufferOffset_ .. end].dup;
        }

        /**
         * Get the next character, moving stream position beyond it.
         *
         * Returns: Next character.
         *
         * Throws:  ReaderException if trying to read past the end of the stream
         *          or if invalid data is read.
         */
        dchar get()
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
        dstring get(in size_t length)
        {
            dstring result = prefix(length);
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
        void forward(size_t length = 1)
        {
            mixin FastCharSearch!"\n\u0085\u2028\u2029"d search;
            updateBuffer(length + 1);

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
        @property Mark mark() const {return Mark(line_, column_);}

        ///Get current line number.
        @property uint line() const {return line_;}

        ///Get current line number.
        @property uint column() const {return column_;}

        ///Get index of the current character in the stream.
        @property size_t charIndex() const {return charIndex_;}

        ///Get encoding of the input stream.
        @property Encoding encoding() const {return encoding_;}

    private:
        /**
         * Update buffer to be able to read length characters after buffer offset.
         *
         * If there are not enough characters in the stream, it will get
         * as many as possible.
         *
         * Params:  length = Mimimum number of characters we need to read.
         *
         * Throws:  ReaderException if trying to read past the end of the stream
         *          or if invalid data is read.
         */
        void updateBuffer(in size_t length)
        {
            if(buffer_.length > bufferOffset_ + length){return;}

            //get rid of unneeded data in the buffer
            if(bufferOffset_ > 0)
            {
                size_t bufferLength = buffer_.length - bufferOffset_;
                memmove(buffer_.ptr, buffer_.ptr + bufferOffset_,
                        bufferLength * dchar.sizeof);
                buffer_.length = bufferLength;
                bufferOffset_ = 0;
            }

            ////Load chars in batches of at most 1024 bytes (256 chars)
            while(buffer_.length <= bufferOffset_ + length)
            {
                loadChars(256);

                if(done)
                {
                    if(buffer_.length == 0 || buffer_[$ - 1] != '\0')
                    {
                        buffer_ ~= '\0';
                    }
                    break;
                }
            }
        }

        /**
         * Load at most specified number of characters.
         *
         * Params:  chars = Maximum number of characters to load.
         *
         * Throws:  ReaderException on Unicode decoding error,
         *          if nonprintable characters are detected, or
         *          if there is an error reading from the stream.
         */
        void loadChars(size_t chars)
        {
            ///Get next character from the stream.
            dchar getDChar()
            {
                switch(encoding_)
                {
                    case Encoding.UTF_8:
                        //Temp buffer for moving data in rawBuffer8_.
                        char[bufferLength8_] temp;
                        //Shortcut for ASCII.
                        if(rawUsed_ > 0 && rawBuffer8_[0] < 128)
                        {
                            //Get the first byte (one char in ASCII).
                            const dchar result = rawBuffer8_[0];
                            --rawUsed_;
                            //Move the data.
                            *(cast(ulong*)temp.ptr) = *(cast(ulong*)(rawBuffer8_.ptr + 1));
                            *(cast(ulong*)rawBuffer8_.ptr) = *(cast(ulong*)temp.ptr);
                            return result;
                        }

                        //Bytes to read.
                        const readBytes = min(available_, bufferLength8_ - rawUsed_);
                        available_ -= readBytes;
                        //Length of data in rawBuffer8_ after reading.
                        const len = rawUsed_ + readBytes;
                        //Read the data.
                        stream_.readExact(rawBuffer8_.ptr + rawUsed_, readBytes);

                        //After decoding, this will point to the first byte not decoded.
                        size_t idx = 0;
                        const dchar result = decode(rawBuffer8_, idx);
                        rawUsed_ = cast(uint)(len - idx);

                        //Move the data.
                        temp[0 .. rawUsed_] = rawBuffer8_[idx .. len];
                        rawBuffer8_[0 .. rawUsed_] = temp[0 .. rawUsed_];
                        return result;
                    case Encoding.UTF_16: 
                        //Temp buffer for moving data in rawBuffer8_.
                        wchar[bufferLength16_] temp;
                        //Words to read.
                        size_t readWords = min(available_ / 2, bufferLength16_ - rawUsed_);
                        available_ -= readWords * 2;
                        //Length of data in rawBuffer16_ after reading.
                        size_t len = rawUsed_;
                        //Read the data.
                        while(readWords > 0)
                        {
                            //Due to a bug in std.stream, we have to use getcw here.
                            rawBuffer16_[len] = stream_.getcw(); 
                            --readWords;
                            ++len;
                        }

                        //After decoding, this will point to the first word not decoded.
                        size_t idx = 0;
                        const dchar result = decode(rawBuffer16_, idx);
                        rawUsed_ = cast(uint)(len - idx);

                        //Move the data.
                        temp[0 .. rawUsed_] = rawBuffer16_[idx .. len];
                        rawBuffer16_[0 .. rawUsed_] = temp[0 .. rawUsed_];
                        return result;
                    case Encoding.UTF_32:
                        dchar result;
                        available_ -= 4;
                        stream_.read(result);
                        return result;
                    default: assert(false);
                }
            }

            const oldLength = buffer_.length;
            const oldPosition = stream_.position;

            //Preallocating memory to limit GC reallocations.
            buffer_.length = buffer_.length + chars;
            scope(exit)
            {
                buffer_.length = buffer_.length - chars;
                enforce(printable(buffer_[oldLength .. $]), 
                        new ReaderException("Special unicode characters are not allowed"));
            }

            try for(uint c = 0; chars; --chars, ++c)
            {
                if(done){break;}
                buffer_[oldLength + c] = getDChar();
            }
            catch(UtfException e)
            {
                const position = stream_.position;
                throw new ReaderException(format("Unicode decoding error between bytes ",
                                          oldPosition, " and ", position, " : ", e.msg));
            }
            catch(ReadException e)
            {
                throw new ReaderException(e.msg);
            }
        }

        /**
         * Determine if all characters in an array are printable.
         *
         * Params:  chars = Characters to check.
         *
         * Returns: True if all the characters are printable, false otherwise.
         */
        static bool printable(const ref dchar[] chars)
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

        ///Are we done reading?
        @property bool done()
        {   
            return (available_ == 0 && 
                    ((encoding_ == Encoding.UTF_8  && rawUsed_ == 0) ||
                     (encoding_ == Encoding.UTF_16 && rawUsed_ == 0) ||
                     encoding_ == Encoding.UTF_32));
        }

    unittest
    {
        writeln("D:YAML reader endian unittest");
        void endian_test(ubyte[] data, Encoding encoding_expected, Endian endian_expected)
        {
            auto reader = new Reader(new MemoryStream(data));
            assert(reader.encoding_ == encoding_expected);
            assert(reader.stream_.endian == endian_expected);
        }
        ubyte[] little_endian_utf_16 = [0xFF, 0xFE, 0x7A, 0x00];
        ubyte[] big_endian_utf_16 = [0xFE, 0xFF, 0x00, 0x7A];
        endian_test(little_endian_utf_16, Encoding.UTF_16, Endian.littleEndian);
        endian_test(big_endian_utf_16, Encoding.UTF_16, Endian.bigEndian);
    }
    unittest
    {
        writeln("D:YAML reader peek/prefix/forward unittest");
        ubyte[] data = ByteOrderMarks[BOM.UTF8] ~ cast(ubyte[])"data";
        auto reader = new Reader(new MemoryStream(data));
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
    unittest
    {
        writeln("D:YAML reader UTF formats unittest");
        dchar[] data = cast(dchar[])"data";
        void utf_test(T)(T[] data, BOM bom)
        {
            ubyte[] bytes = ByteOrderMarks[bom] ~ 
                            (cast(ubyte*)data.ptr)[0 .. data.length * T.sizeof];
            auto reader = new Reader(new MemoryStream(bytes));
            assert(reader.peek() == 'd');
            assert(reader.peek(1) == 'a');
            assert(reader.peek(2) == 't');
            assert(reader.peek(3) == 'a');
        }
        utf_test!char(to!(char[])(data), BOM.UTF8);
        utf_test!wchar(to!(wchar[])(data), endian == Endian.bigEndian ? BOM.UTF16BE : BOM.UTF16LE);
        utf_test(data, endian == Endian.bigEndian ? BOM.UTF32BE : BOM.UTF32LE);
    }
}
