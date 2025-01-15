
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
import std.range;
import std.string;
import std.system;
import std.typecons;
import std.utf;

import dyaml.exception;

alias isBreak = among!('\n', '\u0085', '\u2028', '\u2029');

package:


/// Provides an API to read characters from a UTF-8 buffer.
struct Reader
{
    private:
        // Buffer of currently loaded characters.
        char[] buffer_;

        // Current position within buffer. Only data after this position can be read.
        size_t bufferOffset_;

        // Index of the current character in the buffer.
        size_t charIndex_;
        // Number of characters (code points) in buffer_.
        size_t characterCount_;

        // File name
        string name_;
        // Current line in file.
        uint line_;
        // Current column in file.
        uint column_;

        // The number of consecutive ASCII characters starting at bufferOffset_.
        //
        // Used to minimize UTF-8 decoding.
        size_t upcomingASCII_;

        // Index to buffer_ where the last decoded character starts.
        size_t lastDecodedBufferOffset_;
        // Offset, relative to charIndex_, of the last decoded character,
        // in code points, not chars.
        size_t lastDecodedCharOffset_;

    public:
        /// Construct a Reader.
        ///
        /// Params:  buffer = Buffer with YAML data. This may be e.g. the entire
        ///                   contents of a file or a string. $(B will) be modified by
        ///                   the Reader and other parts of D:YAML (D:YAML tries to
        ///                   reuse the buffer to minimize memory allocations)
        ///          name   = File name if the buffer is the contents of a file or
        ///                   `"<unknown>"` if the buffer is the contents of a string.
        ///
        /// Throws:  ReaderException on a UTF decoding error or if there are
        ///          nonprintable Unicode characters illegal in YAML.
        this(char[] buffer, string name = "<unknown>") @safe pure
        {
            name_ = name;
            buffer_ = buffer;

            characterCount_ = buffer.walkLength;
            // Check that all characters in buffer are printable.
            // TODO: add line and column
            enforce(isPrintableValidUTF8(buffer_),
                    new ReaderException("Special unicode characters are not allowed", Mark(name, 0, 0)));

            checkASCII();
        }

        /// Get character at specified index relative to current position.
        ///
        /// Params:  index = Index of the character to get relative to current position
        ///                  in the buffer. Can point outside of the buffer; In that
        ///                  case, '\0' will be returned.
        ///
        /// Returns: Character at specified position or '\0' if outside of the buffer.
        ///
        // XXX removed; search for 'risky' to find why.
        // Throws:  ReaderException if trying to read past the end of the buffer.
        dchar peek(const size_t index) @safe pure
        {
            if(index < upcomingASCII_) { return buffer_[bufferOffset_ + index]; }
            if(characterCount_ <= charIndex_ + index)
            {
                // XXX This is risky; revert this if bugs are introduced. We rely on
                // the assumption that Reader only uses peek() to detect end of buffer.
                // The test suite passes.
                // Revert this case here and in other peek() versions if this causes
                // errors.
                // throw new ReaderException("Trying to read past the end of the buffer");
                return '\0';
            }

            // Optimized path for Scanner code that peeks chars in linear order to
            // determine the length of some sequence.
            if(index == lastDecodedCharOffset_)
            {
                ++lastDecodedCharOffset_;
                const char b = buffer_[lastDecodedBufferOffset_];
                // ASCII
                if(b < 0x80)
                {
                    ++lastDecodedBufferOffset_;
                    return b;
                }
                return decode(buffer_, lastDecodedBufferOffset_);
            }

            // 'Slow' path where we decode everything up to the requested character.
            const asciiToTake = min(upcomingASCII_, index);
            lastDecodedCharOffset_   = asciiToTake;
            lastDecodedBufferOffset_ = bufferOffset_ + asciiToTake;
            dchar d;
            while(lastDecodedCharOffset_ <= index)
            {
                d = decodeNext();
            }

            return d;
        }

        /// Optimized version of peek() for the case where peek index is 0.
        dchar peek() @safe pure
        {
            if(upcomingASCII_ > 0)            { return buffer_[bufferOffset_]; }
            if(characterCount_ <= charIndex_) { return '\0'; }

            lastDecodedCharOffset_   = 0;
            lastDecodedBufferOffset_ = bufferOffset_;
            return decodeNext();
        }

        /// Get byte at specified index relative to current position.
        ///
        /// Params:  index = Index of the byte to get relative to current position
        ///                  in the buffer. Can point outside of the buffer; In that
        ///                  case, '\0' will be returned.
        ///
        /// Returns: Byte at specified position or '\0' if outside of the buffer.
        char peekByte(const size_t index) @safe pure nothrow @nogc
        {
            return characterCount_ > (charIndex_ + index) ? buffer_[bufferOffset_ + index] : '\0';
        }

        /// Optimized version of peekByte() for the case where peek byte index is 0.
        char peekByte() @safe pure nothrow @nogc
        {
            return characterCount_ > charIndex_ ? buffer_[bufferOffset_] : '\0';
        }


        /// Get specified number of characters starting at current position.
        ///
        /// Note: This gets only a "view" into the internal buffer, which will be
        ///       invalidated after other Reader calls.
        ///
        /// Params: length = Number of characters (code points, not bytes) to get. May
        ///                  reach past the end of the buffer; in that case the returned
        ///                  slice will be shorter.
        ///
        /// Returns: Characters starting at current position or an empty slice if out of bounds.
        char[] prefix(const size_t length) @safe pure
        {
            return slice(length);
        }

        /// Get specified number of bytes, not code points, starting at current position.
        ///
        /// Note: This gets only a "view" into the internal buffer, which will be
        ///       invalidated after other Reader calls.
        ///
        /// Params: length = Number bytes (not code points) to get. May NOT reach past
        ///                  the end of the buffer; should be used with peek() to avoid
        ///                  this.
        ///
        /// Returns: Bytes starting at current position.
        char[] prefixBytes(const size_t length) @safe pure nothrow @nogc
        in(length == 0 || bufferOffset_ + length <= buffer_.length, "prefixBytes out of bounds")
        {
            return buffer_[bufferOffset_ .. bufferOffset_ + length];
        }

        /// Get a slice view of the internal buffer, starting at the current position.
        ///
        /// Note: This gets only a "view" into the internal buffer,
        ///       which get invalidated after other Reader calls.
        ///
        /// Params:  end = End of the slice relative to current position. May reach past
        ///                the end of the buffer; in that case the returned slice will
        ///                be shorter.
        ///
        /// Returns: Slice into the internal buffer or an empty slice if out of bounds.
        char[] slice(const size_t end) @safe pure
        {
            // Fast path in case the caller has already peek()ed all the way to end.
            if(end == lastDecodedCharOffset_)
            {
                return buffer_[bufferOffset_ .. lastDecodedBufferOffset_];
            }

            const asciiToTake = min(upcomingASCII_, end, buffer_.length);
            lastDecodedCharOffset_   = asciiToTake;
            lastDecodedBufferOffset_ = bufferOffset_ + asciiToTake;

            // 'Slow' path - decode everything up to end.
            while(lastDecodedCharOffset_ < end &&
                  lastDecodedBufferOffset_ < buffer_.length)
            {
                decodeNext();
            }

            return buffer_[bufferOffset_ .. lastDecodedBufferOffset_];
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
        /// Params:  length = Number or characters (code points, not bytes) to get.
        ///
        /// Returns: Characters starting at current position.
        char[] get(const size_t length) @safe pure
        {
            auto result = slice(length);
            forward(length);
            return result;
        }

        /// Move current position forward.
        ///
        /// Params:  length = Number of characters to move position forward.
        void forward(size_t length) @safe pure
        {
            while(length > 0)
            {
                auto asciiToTake = min(upcomingASCII_, length);
                charIndex_     += asciiToTake;
                length         -= asciiToTake;
                upcomingASCII_ -= asciiToTake;

                for(; asciiToTake > 0; --asciiToTake)
                {
                    const c = buffer_[bufferOffset_++];
                    // c is ASCII, do we only need to check for ASCII line breaks.
                    if(c == '\n' || (c == '\r' && buffer_[bufferOffset_] != '\n'))
                    {
                        ++line_;
                        column_ = 0;
                        continue;
                    }
                    ++column_;
                }

                // If we have used up all upcoming ASCII chars, the next char is
                // non-ASCII even after this returns, so upcomingASCII_ doesn't need to
                // be updated - it's zero.
                if(length == 0) { break; }

                assert(upcomingASCII_ == 0,
                       "Running unicode handling code but we haven't run out of ASCII chars");
                assert(bufferOffset_ < buffer_.length,
                       "Attempted to decode past the end of YAML buffer");
                assert(buffer_[bufferOffset_] >= 0x80,
                       "ASCII must be handled by preceding code");

                ++charIndex_;
                const c = decode(buffer_, bufferOffset_);

                // New line. (can compare with '\n' without decoding since it's ASCII)
                if(c.isBreak || (c == '\r' && buffer_[bufferOffset_] != '\n'))
                {
                    ++line_;
                    column_ = 0;
                }
                else if(c != '\uFEFF') { ++column_; }
                --length;
                checkASCII();
            }

            lastDecodedBufferOffset_ = bufferOffset_;
            lastDecodedCharOffset_ = 0;
        }

        /// Move current position forward by one character.
        void forward() @safe pure
        {
            ++charIndex_;
            lastDecodedBufferOffset_ = bufferOffset_;
            lastDecodedCharOffset_ = 0;

            // ASCII
            if(upcomingASCII_ > 0)
            {
                --upcomingASCII_;
                const c = buffer_[bufferOffset_++];

                if(c == '\n' || (c == '\r' && buffer_[bufferOffset_] != '\n'))
                {
                    ++line_;
                    column_ = 0;
                    return;
                }
                ++column_;
                return;
            }

            // UTF-8
            assert(bufferOffset_ < buffer_.length,
                   "Attempted to decode past the end of YAML buffer");
            assert(buffer_[bufferOffset_] >= 0x80,
                   "ASCII must be handled by preceding code");

            const c = decode(buffer_, bufferOffset_);

            // New line. (can compare with '\n' without decoding since it's ASCII)
            if(c.isBreak || (c == '\r' && buffer_[bufferOffset_] != '\n'))
            {
                ++line_;
                column_ = 0;
            }
            else if(c != '\uFEFF') { ++column_; }

            checkASCII();
        }

        /// Get filename, line and column of current position.
        Mark mark() const pure nothrow @nogc @safe { return Mark(name_, line_, column_); }

        /// Get filename, line and column of current position + some number of chars
        Mark mark(size_t advance) const pure @safe
        {
            auto lineTemp = cast()line_;
            auto columnTemp = cast()column_;
            auto bufferOffsetTemp = cast()bufferOffset_;
            for (size_t pos = 0; pos < advance; pos++)
            {
                if (bufferOffsetTemp >= buffer_.length)
                {
                    break;
                }
                const c = decode(buffer_, bufferOffsetTemp);
                if (c.isBreak || (c == '\r' && buffer_[bufferOffsetTemp] == '\n'))
                {
                    lineTemp++;
                    columnTemp = 0;
                }
                columnTemp++;
            }
            return Mark(name_, lineTemp, columnTemp);
        }

        /// Get file name.
        ref inout(string) name() inout @safe return pure nothrow @nogc { return name_; }

        /// Get current line number.
        uint line() const @safe pure nothrow @nogc { return line_; }

        /// Get current column number.
        uint column() const @safe pure nothrow @nogc { return column_; }

        /// Get index of the current character in the buffer.
        size_t charIndex() const @safe pure nothrow @nogc { return charIndex_; }

private:
        // Update upcomingASCII_ (should be called forward()ing over a UTF-8 sequence)
        void checkASCII() @safe pure nothrow @nogc
        {
            upcomingASCII_ = countASCII(buffer_[bufferOffset_ .. $]);
        }

        // Decode the next character relative to
        // lastDecodedCharOffset_/lastDecodedBufferOffset_ and update them.
        //
        // Does not advance the buffer position. Used in peek() and slice().
        dchar decodeNext() @safe pure
        {
            assert(lastDecodedBufferOffset_ < buffer_.length,
                   "Attempted to decode past the end of YAML buffer");
            const char b = buffer_[lastDecodedBufferOffset_];
            ++lastDecodedCharOffset_;
            // ASCII
            if(b < 0x80)
            {
                ++lastDecodedBufferOffset_;
                return b;
            }

            return decode(buffer_, lastDecodedBufferOffset_);
        }
}

private:

/// Determine if all characters (code points, not bytes) in a string are printable.
bool isPrintableValidUTF8(const char[] chars) @safe pure
{
    import std.uni : isControl, isWhite;
    foreach (dchar chr; chars)
    {
        if (!chr.isValidDchar || (chr.isControl && !chr.isWhite))
        {
            return false;
        }
    }
    return true;
}

/// Counts the number of ASCII characters in buffer until the first UTF-8 sequence.
///
/// Used to determine how many characters we can process without decoding.
size_t countASCII(const(char)[] buffer) @safe pure nothrow @nogc
{
    return buffer.byCodeUnit.until!(x => x > 0x7F).walkLength;
}
// Unittests.

//Issue 257 - https://github.com/dlang-community/D-YAML/issues/257
@safe unittest
{
    import dyaml.loader : Loader;
    auto yaml = "hello ";
    auto root = Loader.fromString(yaml).load();

    assert(root.isValid);
}
