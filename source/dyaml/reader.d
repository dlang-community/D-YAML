
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
        char[] buffer8_ = null;

        // Current position within buffer. Only data after this position can be read.
        uint bufferOffset_ = 0;
        size_t bufferOffset8_ = 0;

        // Index of the current character in the buffer.
        size_t charIndex_ = 0;

        // Current line in file.
        uint line_;
        // Current column in file.
        uint column_;

        // Original Unicode encoding of the data.
        Encoding encoding_;

        version(unittest)
        {
            // Endianness of the input before it was converted (for testing)
            Endian endian_;
        }

        // Index to buffer8_ where the last decoded character starts.
        size_t lastDecodedBufferOffset_ = 0;
        // Offset, relative to charIndex_, of the last decoded character, 
        // in code points, not chars.
        size_t lastDecodedCharOffset_ = 0;

        // Number of character decodings done during the life of the Reader.
        //
        // Used for performance testing.
        size_t decodeCount_ = 0;


    public:
        import std.stream;
        /// Construct a Reader.
        ///
        /// Params:  stream = Input stream. Must be readable and seekable.
        ///
        /// Throws:  ReaderException if the stream is invalid, on a UTF decoding error
        ///          or if there are nonprintable unicode characters illegal in YAML.
        this(Stream stream) @trusted //!nothrow
        {
            auto streamBytes = streamToBytesGC(stream);
            auto endianResult = fixUTFByteOrder(streamBytes);
            if(endianResult.bytesStripped > 0)
            {
                throw new ReaderException("Size of UTF-16 or UTF-32 input not aligned "
                                          "to 2 or 4 bytes, respectively");
            }

            version(unittest) { endian_ = endianResult.endian; }
            encoding_ = endianResult.encoding;

            auto decodeResult = decodeUTF(endianResult.array, endianResult.encoding);

            const msg = decodeResult.errorMessage;
            if(msg !is null)
            {
                throw new ReaderException("UTF decoding error: " ~ msg);
            }

            buffer_ = decodeResult.decoded;
            // Check that excluding any trailing zeroes, all character in buffer are 
            // printable.
            auto noZeros = buffer_;
            while(!noZeros.empty && noZeros.back == '\0') { noZeros.popBack(); }
            enforce(printable(noZeros[]),
                    new ReaderException("Special unicode characters are not allowed"));

            //TEMP (UTF-8 will be the default)
            buffer8_ = cast(char[])buffer_.to!string;
            const validateResult = buffer8_.validateUTF8NoGC;
            enforce(validateResult.valid,
                    new ReaderException(validateResult.msg ~ 
                                        validateResult.sequence.to!string));

            this.sliceBuilder  = SliceBuilder(this);
            this.sliceBuilder8 = SliceBuilder8(this);
        }

        /// Get character at specified index relative to current position.
        ///
        /// Params:  index = Index of the character to get relative to current position
        ///                  in the buffer.
        ///
        /// Returns: Character at specified position.
        ///
        // XXX removed; search for 'risky' to find why.
        // Throws:  ReaderException if trying to read past the end of the buffer.
        dchar peek(size_t index = 0) @safe pure nothrow @nogc
        {
            if(buffer_.length <= charIndex_ + index)
            {
                // XXX This is risky; revert this and the 'risky' change in UTF decoder
                // if any bugs are introduced. We rely on the assumption that Reader
                // only uses peek() to detect the of buffer. The test suite passes.
                // throw new ReaderException("Trying to read past the end of the buffer");
                return '\0';
            }

            // Optimized path for Scanner code that peeks chars in linear order to
            // determine the length of some sequence.
            if(index == lastDecodedCharOffset_)
            {

                ++decodeCount_;
                ++lastDecodedCharOffset_;
                const char b = buffer8_[lastDecodedBufferOffset_];
                // ASCII
                if(b < 0x80) 
                {
                    ++lastDecodedBufferOffset_;
                    return b;
                }
                return decodeValidUTF8NoGC(buffer8_, lastDecodedBufferOffset_);
            }


            // 'Slow' path where we decode everything up to the requested character.
            lastDecodedCharOffset_   = 0;
            lastDecodedBufferOffset_ = bufferOffset8_;
            dchar d;
            while(lastDecodedCharOffset_ <= index)
            {
                d = decodeNext();
            }

            return d;
        }

        /// Get specified number of characters starting at current position.
        ///
        /// Note: This gets only a "view" into the internal buffer,
        ///       which get invalidated after other Reader calls.
        ///
        /// Params:  length = Number of characters to get. May reach past the end of the
        ///                   buffer; in that case the returned slice will be shorter.
        ///
        /// Returns: Characters starting at current position or an empty slice if out of bounds.
        dchar[] prefix(size_t length) @safe pure nothrow @nogc
        {
            return slice(0, length);
        }
        char[] prefix8(const size_t length) @safe pure nothrow @nogc
        {
            return slice8(length);
        }

        /// Get a slice view of the internal buffer.
        ///
        /// Note: This gets only a "view" into the internal buffer,
        ///       which get invalidated after other Reader calls.
        ///
        /// Params:  start = Start of the slice relative to current position.
        ///          end   = End of the slice relative to current position. May reach
        ///                  past the end of the buffer; in that case the returned
        ///                  slice will be shorter.
        ///
        /// Returns: Slice into the internal buffer or an empty slice if out of bounds.
        dchar[] slice(size_t start, size_t end) @trusted pure nothrow @nogc
        {
            start += bufferOffset_;
            end    = min(buffer_.length, end + bufferOffset_);
            assert(end >= start, "Trying to read a slice that starts after its end");

            return buffer_[start .. end];
        }
        char[] slice8(const size_t end) @safe pure nothrow @nogc
        {
            // Fast path in case the caller has already peek()ed all the way to end.
            if(end == lastDecodedCharOffset_)
            {
                return buffer8_[bufferOffset8_ .. lastDecodedBufferOffset_];
            }

            lastDecodedCharOffset_   = 0;
            lastDecodedBufferOffset_ = bufferOffset8_;

            // 'Slow' path - decode everything up to end.
            while(lastDecodedCharOffset_ < end &&
                  lastDecodedBufferOffset_ < buffer8_.length)
            {
                decodeNext();
            }

            return buffer8_[bufferOffset8_ .. lastDecodedBufferOffset_];
        }

        /// Get the next character, moving buffer position beyond it.
        ///
        /// Returns: Next character.
        ///
        /// Throws:  ReaderException if trying to read past the end of the buffer
        ///          or if invalid data is read.
        dchar get() @safe pure nothrow @nogc
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
        dchar[] get(size_t length) @safe pure nothrow @nogc
        {
            auto result = prefix(length);
            forward(length);
            return result;
        }
        char[] get8(const size_t length) @safe pure nothrow @nogc
        {
            auto result = prefix8(length);
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
                const c = decodeAndAdvanceCurrent();
                // New line. (can compare with '\n' without decoding since it's ASCII)
                if(search.canFind(c) || (c == '\r' && buffer8_[bufferOffset8_] != '\n'))
                {
                    ++line_;
                    column_ = 0;
                }
                else if(c != '\uFEFF') { ++column_; }
            }

            lastDecodedBufferOffset_ = bufferOffset8_;
            lastDecodedCharOffset_ = 0;
        }

        /// Used to build slices of read data in Reader; to avoid allocations.
        SliceBuilder sliceBuilder;

        /// Get a string describing current buffer position, used for error messages.
        final Mark mark() @safe pure nothrow const @nogc { return Mark(line_, column_); }

        /// Get current line number.
        final uint line() @safe pure nothrow const @nogc { return line_; }

        /// Get current column number.
        final uint column() @safe pure nothrow const @nogc { return column_; }

        /// Get index of the current character in the buffer.
        final size_t charIndex() @safe pure nothrow const @nogc { return charIndex_; }

        /// Get encoding of the input buffer.
        final Encoding encoding() @safe pure nothrow const @nogc { return encoding_; }

private:
        // Decode the next character relative to
        // lastDecodedCharOffset_/lastDecodedBufferOffset_ and update them.
        //
        // Does not advance the buffer position. Used in peek() and slice().
        dchar decodeNext() @safe pure nothrow @nogc 
        {
            assert(lastDecodedBufferOffset_ < buffer8_.length,
                   "Attempted to decode past the end of a string");
            ++decodeCount_;
            const char b = buffer8_[lastDecodedBufferOffset_];
            ++lastDecodedCharOffset_;
            // ASCII
            if(b < 0x80)
            {
                ++lastDecodedBufferOffset_;
                return b;
            }

            return decodeValidUTF8NoGC(buffer8_, lastDecodedBufferOffset_);
        }

        // Decode the character starting at bufferOffset8_ and move to the next
        // character.
        //
        // Used in forward().
        dchar decodeAndAdvanceCurrent() @safe pure nothrow @nogc
        {
            assert(bufferOffset8_ < buffer8_.length,
                   "Attempted to decode past the end of a string");
            const b = buffer8_[bufferOffset8_];
            ++bufferOffset_;
            ++charIndex_;
            ++decodeCount_;
            if(b < 0x80)
            {
                ++bufferOffset8_;
                return b; 
            }

            return decodeValidUTF8NoGC(buffer8_, bufferOffset8_);
        }
}


/// Used to build slices of already read data in Reader buffer, avoiding allocations.
///
/// Usually these slices point to unchanged Reader data, but sometimes the data is 
/// changed due to how YAML interprets certain characters/strings.
///
/// See begin() documentation.
struct SliceBuilder
{
private:
    // No copying by the user.
    @disable this(this);
    @disable void opAssign(ref SliceBuilder);

    // Reader this builder works in.
    Reader reader_;

    // Start of the slice om reader_.buffer_ (size_t.max while no slice being build)
    size_t start_ = size_t.max;
    // End of the slice om reader_.buffer_ (size_t.max while no slice being build)
    size_t end_   = size_t.max;

    // Stack of slice ends to revert to (see Transaction)
    //
    // Very few levels as we don't want arbitrarily nested transactions.
    size_t[4] endStack_;
    // The number of elements currently in endStack_.
    size_t endStackUsed_ = 0;

    @safe pure nothrow const @nogc invariant()
    {
        if(!inProgress) { return; }
        assert(end_ <= reader_.bufferOffset_, "Slice ends after buffer position");
        assert(start_ <= end_, "Slice start after slice end");
    }

    // Is a slice currently being built?
    bool inProgress() @safe pure nothrow const @nogc
    {
        assert(start_ == size_t.max ? end_ == size_t.max :
            end_ != size_t.max, "start_/end_ are not consistent");
        return start_ != size_t.max;
    }

public:
    /// Begin building a slice.
    ///
    /// Only one slice can be built at any given time; before beginning a new slice,
    /// finish the previous one (if any).
    ///
    /// The slice starts at the current position in the Reader buffer. It can only be
    /// extended up to the current position in the buffer; Reader methods get() and
    /// forward() move the position. E.g. it is valid to extend a slice by write()-ing
    /// a string just returned by get() - but not one returned by prefix() unless the
    /// position has changed since the prefix() call.
    void begin() @system pure nothrow @nogc
    {
        assert(!inProgress, "Beginning a slice while another slice is being built");
        assert(endStackUsed_ == 0, "Slice stack not empty at slice begin");

        start_ = reader_.bufferOffset_;
        end_   = reader_.bufferOffset_;
    }

    /// Finish building a slice and return it.
    ///
    /// Any Transactions on the slice must be committed or destroyed before the slice
    /// is finished.
    ///
    /// Returns a string; once a slice is finished it is definitive that its contents
    /// will not be changed.
    dstring finish() @system pure nothrow @nogc
    {
        assert(inProgress, "finish called without begin");
        assert(endStackUsed_ == 0, "Finishing a slice with running transactions.");

        const result = reader_.buffer_[start_ .. end_];
        start_ = end_ = size_t.max;
        return cast(dstring)result;
    }

    /// Write a string to the slice being built.
    ///
    /// Data can only be written up to the current position in the Reader buffer.
    ///
    /// If str is a string returned by a Reader method, and str starts right after the
    /// end of the slice being built, the slice is extended (trivial operation).
    ///
    /// See_Also: begin
    void write(dchar[] str) @system pure nothrow @nogc
    {
        assert(inProgress, "write called without begin");

        // If str starts at the end of the slice (is a string returned by a Reader
        // method), just extend the slice to contain str.
        if(str.ptr == reader_.buffer_.ptr + end_)
        {
            end_ += str.length;
        }
        // Even if str does not start at the end of the slice, it still may be returned
        // by a Reader method and point to buffer. So we need to memmove.
        else
        {
            core.stdc.string.memmove(reader_.buffer_.ptr + end_, cast(dchar*)str.ptr,
                                     str.length * dchar.sizeof);
            end_ += str.length;
        }
    }

    /// Write a character to the slice being built.
    ///
    /// Data can only be written up to the current position in the Reader buffer.
    ///
    /// See_Also: begin
    void write(dchar c) @system pure nothrow @nogc
    {
        assert(inProgress, "write called without begin");

        reader_.buffer_[end_++] = c;
    }

    /// Insert a character into the slice, backwards characters before the end.
    ///
    /// Enlarges the slice by 1 char. Note that the slice can only extend up to the
    /// current position in the Reader buffer.
    void insertBack(dchar c, size_t backwards) @system pure nothrow @nogc
    {
        assert(inProgress, "insertBack called without begin");
        assert(end_ - backwards >= start_, "Trying to insert in front of the slice");

        const point = end_ - backwards;
        core.stdc.string.memmove(reader_.buffer_.ptr + point + 1,
                                 reader_.buffer_.ptr + point, 
                                 backwards * dchar.sizeof);
        ++end_;
        reader_.buffer_[point] = c;
    }

    /// Get the current length of the slice.
    size_t length() @safe pure nothrow const @nogc
    {
        return end_ - start_;
    }

    /// A slice building transaction.
    ///
    /// Can be used to save and revert back to slice state.
    struct Transaction
    {
    private:
        // The slice builder affected by the transaction.
        SliceBuilder* builder_ = null;
        // Index of the return point of the transaction in StringBuilder.endStack_.
        size_t stackLevel_;
        // True after commit() has been called.
        bool committed_;

    public:
        /// Begins a transaction on a SliceBuilder object.
        ///
        /// The transaction must end $(B after) any transactions created within the
        /// transaction but $(B before) the slice is finish()-ed. A transaction can be
        /// ended either by commit()-ing or reverting through the destructor.
        ///
        /// Saves the current state of a slice.
        this(ref SliceBuilder builder) @system pure nothrow @nogc
        {
            builder_ = &builder;
            stackLevel_ = builder_.endStackUsed_;
            builder_.push();
        }

        /// Commit changes to the slice. 
        ///
        /// Ends the transaction - can only be called once, and removes the possibility
        /// to revert slice state.
        ///
        /// Does nothing for a default-initialized transaction (the transaction has not
        /// been started yet).
        void commit() @system pure nothrow @nogc
        {
            assert(!committed_, "Can't commit a transaction more than once");

            if(builder_ is null) { return; }
            assert(builder_.endStackUsed_ == stackLevel_ + 1,
                   "Parent transactions don't fully contain child transactions");
            builder_.apply();
            committed_ = true;
        }

        /// Destroy the transaction and revert it if it hasn't been committed yet.
        ///
        /// Does nothing for a default-initialized transaction.
        ~this() @system pure nothrow @nogc
        {
            if(builder_ is null || committed_) { return; }
            assert(builder_.endStackUsed_ == stackLevel_ + 1,
                   "Parent transactions don't fully contain child transactions");
            builder_.pop();
            builder_ = null;
        }
    }

private:
    // Push the current end of the slice so we can revert to it if needed.
    //
    // Used by Transaction.
    void push() @system pure nothrow @nogc
    {
        assert(inProgress, "push called without begin");
        assert(endStackUsed_ < endStack_.length, "Slice stack overflow");
        endStack_[endStackUsed_++] = end_;
    }

    // Pop the current end of endStack_ and set the end of the slice to the popped
    // value, reverting changes since the old end was pushed.
    //
    // Used by Transaction.
    void pop() @system pure nothrow @nogc
    {
        assert(inProgress, "pop called without begin");
        assert(endStackUsed_ > 0, "Trying to pop an empty slice stack");
        end_ = endStack_[--endStackUsed_];
    }

    // Pop the current end of endStack_, but keep the current end of the slice, applying
    // changes made since pushing the old end.
    //
    // Used by Transaction.
    void apply() @system pure nothrow @nogc
    {
        assert(inProgress, "apply called without begin");
        assert(endStackUsed_ > 0, "Trying to apply an empty slice stack");
        --endStackUsed_;
    }
}

private:

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
// $(D size_t maxChars)     XXX reserved for future
auto decodeUTF(ubyte[] input, UTFEncoding encoding) @safe pure nothrow
{
    // Documented in function ddoc.
    struct Result
    {
        string errorMessage;

        dchar[] decoded;
    }

    Result result;

    final switch(encoding)
    {
        case UTFEncoding.UTF_8:  result.maxChars = input.length;     break;
        case UTFEncoding.UTF_16: result.maxChars = input.length / 2; break;
        case UTFEncoding.UTF_32: result.maxChars = input.length / 2; break;
    }

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

    // XXX This is risky. We rely on the assumption that the scanner only uses
    // peek() to detect the end of the buffer. Should this cause any bugs, revert.
    //
    // The buffer must be zero terminated for scanner to detect its end.
    // if(result.decoded.empty || result.decoded.back() != '\0')
    // {
    //     result.decoded ~= cast(dchar)'\0';
    // }

    return result;
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
    // assert(reader.prefix(6) == "data\0");
    reader.forward(2);
    assert(reader.peek(1) == 'a');
    // assert(collectException(reader.peek(3)));
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
    // assert(collectException(reader.peek(2)));
}

unittest
{
    testEndian!Reader();
    testPeekPrefixForward!Reader();
    testUTF!Reader();
    test1Byte!Reader();
}
