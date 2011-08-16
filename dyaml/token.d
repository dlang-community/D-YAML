
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML tokens.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dyaml.token;


import dyaml.exception;
import dyaml.reader;


package:
///Token types.
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

///Scalar styles.
enum ScalarStyle : ubyte
{
    Invalid = 0,  /// Invalid (uninitialized) style
    Literal,      /// | (Literal block style)
    Folded,       /// > (Folded block style)
    Plain,        /// Plain scalar
    SingleQuoted, /// Single quoted scalar
    DoubleQuoted  /// Double quoted scalar
}

/**
 * Token produced by scanner.
 *
 * 32 bytes on 64-bit.
 */
immutable struct Token 
{
    ///Value of the token, if any.
    string value;
    ///Start position of the token in file/stream.
    Mark startMark;
    ///End position of the token in file/stream.
    Mark endMark;
    ///Token type.
    TokenID id;
    ///Style of scalar token, if this is a scalar token.
    ScalarStyle style;
}

/**
 * Construct a directive token.
 *
 * Params:  start = Start position of the token.
 *          end   = End position of the token. 
 *          value = Value of the token.
 */
Token directiveToken(in Mark start, in Mark end, in string value) pure
{
    return Token(value, start, end, TokenID.Directive);
}

/**
 * Construct a simple (no value) token with specified type.
 * 
 * Params:  id    = Type of the token.
 *          start = Start position of the token.
 *          end   = End position of the token.
 */
Token simpleToken(TokenID id)(in Mark start, in Mark end) pure
{
    return Token(null, start, end, id);
}

///Aliases for construction of simple token types.
alias simpleToken!(TokenID.StreamStart)        streamStartToken;
alias simpleToken!(TokenID.StreamEnd)          streamEndToken;
alias simpleToken!(TokenID.BlockSequenceStart) blockSequenceStartToken;
alias simpleToken!(TokenID.BlockMappingStart)  blockMappingStartToken;
alias simpleToken!(TokenID.BlockEnd)           blockEndToken;
alias simpleToken!(TokenID.Key)                keyToken;
alias simpleToken!(TokenID.Value)              valueToken;
alias simpleToken!(TokenID.BlockEntry)         blockEntryToken;
alias simpleToken!(TokenID.FlowEntry)          flowEntryToken;

/**
 * Construct a simple token with value with specified type.
 * 
 * Params:  id    = Type of the token.
 *          start = Start position of the token.
 *          end   = End position of the token.
 *          value = Value of the token.
 */
Token simpleValueToken(TokenID id)(in Mark start, in Mark end, string value) pure
{
    return Token(value, start, end, id);
}

///Alias for construction of tag token.
alias simpleValueToken!(TokenID.Tag) tagToken;
alias simpleValueToken!(TokenID.Alias) aliasToken;
alias simpleValueToken!(TokenID.Anchor) anchorToken;

/**
 * Construct a scalar token.
 *
 * Params:  start = Start position of the token.
 *          end   = End position of the token. 
 *          value = Value of the token.
 *          style = Style of the token.
 */
Token scalarToken(in Mark start, in Mark end, in string value, in ScalarStyle style) pure
{
    return Token(value, start, end, TokenID.Scalar, style);
}
