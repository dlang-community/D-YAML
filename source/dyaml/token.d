
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// YAML tokens.
/// Code based on PyYAML: http://www.pyyaml.org
module dyaml.token;


import std.conv;

import dyaml.encoding;
import dyaml.exception;
import dyaml.reader;
import dyaml.style;


package:

/// Token types.
enum TokenID : ubyte
{
    Invalid = 0,        /// Invalid (uninitialized) token
    Directive,          /// DIRECTIVE
    DocumentStart,      /// DOCUMENT-START
    DocumentEnd,        /// DOCUMENT-END
    StreamStart,        /// STREAM-START
    StreamEnd,          /// STREAM-END
    BlockSequenceStart, /// BLOCK-SEQUENCE-START
    BlockMappingStart,  /// BLOCK-MAPPING-START
    BlockEnd,           /// BLOCK-END
    FlowSequenceStart,  /// FLOW-SEQUENCE-START
    FlowMappingStart,   /// FLOW-MAPPING-START
    FlowSequenceEnd,    /// FLOW-SEQUENCE-END
    FlowMappingEnd,     /// FLOW-MAPPING-END
    Key,                /// KEY
    Value,              /// VALUE
    BlockEntry,         /// BLOCK-ENTRY
    FlowEntry,          /// FLOW-ENTRY
    Alias,              /// ALIAS
    Anchor,             /// ANCHOR
    Tag,                /// TAG
    Scalar              /// SCALAR
}

/// Token produced by scanner.
///
/// 32 bytes on 64-bit.
struct Token
{
    @disable int opCmp(ref Token);

    // 16B
    /// Value of the token, if any.
    string value;
    // 4B
    /// Start position of the token in file/stream.
    Mark startMark;
    // 4B
    /// End position of the token in file/stream.
    Mark endMark;
    // 1B
    /// Token type.
    TokenID id;
    // 1B
    /// Style of scalar token, if this is a scalar token.
    ScalarStyle style;
    // 1B
    /// Encoding, if this is a stream start token.
    Encoding encoding;
    // 4B
    /// Used to split value into 2 substrings for tokens that need 2 values (tagToken)
    uint valueDivider;

    /// Get string representation of the token ID.
    @property string idString() @safe pure const {return id.to!string;}
}

@safe pure nothrow @nogc:

/// Construct a directive token.
///
/// Params:  start = Start position of the token.
///          end   = End position of the token.
///          value = Value of the token.
Token directiveToken(const Mark start, const Mark end, const string value)
{
    return Token(value, start, end, TokenID.Directive);
}

/// Construct a simple (no value) token with specified type.
///
/// Params:  id    = Type of the token.
///          start = Start position of the token.
///          end   = End position of the token.
Token simpleToken(TokenID id)(const Mark start, const Mark end)
{
    return Token(null, start, end, id);
}

/// Construct a stream start token.
///
/// Params:  start    = Start position of the token.
///          end      = End position of the token.
///          encoding = Encoding of the stream.
Token streamStartToken(const Mark start, const Mark end, const Encoding encoding)
{
    return Token(null, start, end, TokenID.StreamStart, ScalarStyle.Invalid, encoding);
}

/// Aliases for construction of simple token types.
alias simpleToken!(TokenID.StreamEnd)          streamEndToken;
alias simpleToken!(TokenID.BlockSequenceStart) blockSequenceStartToken;
alias simpleToken!(TokenID.BlockMappingStart)  blockMappingStartToken;
alias simpleToken!(TokenID.BlockEnd)           blockEndToken;
alias simpleToken!(TokenID.Key)                keyToken;
alias simpleToken!(TokenID.Value)              valueToken;
alias simpleToken!(TokenID.BlockEntry)         blockEntryToken;
alias simpleToken!(TokenID.FlowEntry)          flowEntryToken;

/// Construct a simple token with value with specified type.
///
/// Params:  id    = Type of the token.
///          start = Start position of the token.
///          end   = End position of the token.
///          value = Value of the token.
Token simpleValueToken(TokenID id)(const Mark start, const Mark end, const string value)
{
    return Token(value, start, end, id);
}

/// Alias for construction of tag token.
alias simpleValueToken!(TokenID.Tag) tagToken;
alias simpleValueToken!(TokenID.Alias) aliasToken;
alias simpleValueToken!(TokenID.Anchor) anchorToken;

/// Construct a scalar token.
///
/// Params:  start = Start position of the token.
///          end   = End position of the token.
///          value = Value of the token.
///          style = Style of the token.
Token scalarToken(const Mark start, const Mark end, const string value, const ScalarStyle style)
{
    return Token(value, start, end, TokenID.Scalar, style);
}
