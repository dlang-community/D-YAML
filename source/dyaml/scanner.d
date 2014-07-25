
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML scanner.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dyaml.scanner;


import core.stdc.string;

import std.algorithm;
import std.array;
import std.container;
import std.conv;
import std.ascii : isAlphaNum, isDigit, isHexDigit;
import std.exception;
import std.string;
import std.typecons;
import std.traits : Unqual;
import std.utf;

import dyaml.fastcharsearch;
import dyaml.escapes;
import dyaml.exception;
import dyaml.nogcutil;
import dyaml.queue;
import dyaml.reader;
import dyaml.style;
import dyaml.token;

package:
/**
 * Scanner produces tokens of the following types:
 * STREAM-START
 * STREAM-END
 * DIRECTIVE(name, value)
 * DOCUMENT-START
 * DOCUMENT-END
 * BLOCK-SEQUENCE-START
 * BLOCK-MAPPING-START
 * BLOCK-END
 * FLOW-SEQUENCE-START
 * FLOW-MAPPING-START
 * FLOW-SEQUENCE-END
 * FLOW-MAPPING-END
 * BLOCK-ENTRY
 * FLOW-ENTRY
 * KEY
 * VALUE
 * ALIAS(value)
 * ANCHOR(value)
 * TAG(value)
 * SCALAR(value, plain, style)
 */


/**
 * Marked exception thrown at scanner errors.
 *
 * See_Also: MarkedYAMLException
 */
class ScannerException : MarkedYAMLException
{
    mixin MarkedExceptionCtors;
}

private alias ScannerException Error;
private alias MarkedYAMLExceptionData ErrorData;

/// Generates tokens from data provided by a Reader.
final class Scanner
{
    private:
        /// A simple key is a key that is not denoted by the '?' indicator.
        /// For example:
        ///   ---
        ///   block simple key: value
        ///   ? not a simple key:
        ///   : { flow simple key: value }
        /// We emit the KEY token before all keys, so when we find a potential simple
        /// key, we try to locate the corresponding ':' indicator. Simple keys should be
        /// limited to a single line and 1024 characters.
        ///
        /// 16 bytes on 64-bit.
        static struct SimpleKey
        {
            /// Character index in reader where the key starts.
            uint charIndex = uint.max;
            /// Index of the key token from start (first token scanned being 0).
            uint tokenIndex;
            /// Line the key starts at.
            uint line;
            /// Column the key starts at.
            ushort column;
            /// Is this required to be a simple key?
            bool required;
            /// Is this struct "null" (invalid)?.
            bool isNull;
        }

        /// Block chomping types.
        enum Chomping
        {
            /// Strip all trailing line breaks. '-' indicator.
            Strip,
            /// Line break of the last line is preserved, others discarded. Default.
            Clip,
            /// All trailing line breaks are preserved. '+' indicator.
            Keep
        }

        /// Reader used to read from a file/stream.
        Reader reader_;
        /// Are we done scanning?
        bool done_;

        /// Level of nesting in flow context. If 0, we're in block context.
        uint flowLevel_;
        /// Current indentation level.
        int indent_ = -1;
        /// Past indentation levels. Used as a stack.
        Array!int indents_;

        /// Processed tokens not yet emitted. Used as a queue.
        Queue!Token tokens_;

        /// Number of tokens emitted through the getToken method.
        uint tokensTaken_;

        /// Can a simple key start at the current position? A simple key may start:
        /// - at the beginning of the line, not counting indentation spaces
        ///       (in block context),
        /// - after '{', '[', ',' (in the flow context),
        /// - after '?', ':', '-' (in the block context).
        /// In the block context, this flag also signifies if a block collection
        /// may start at the current position.
        bool allowSimpleKey_ = true;

        /// Possible simple keys indexed by flow levels.
        SimpleKey[] possibleSimpleKeys_;

        /// Used for constructing strings while limiting reallocation.
        Appender!(dchar[]) appender_;


        /// Set on error by nothrow/@nogc inner functions along with errorData_.
        ///
        /// Non-nothrow/GC-using caller functions can then throw an exception using
        /// data stored in errorData_.
        bool error_;

        /// Data for the exception to throw if error_ is true.
        ErrorData errorData_;

        /// Error messages can be built in this buffer without using the GC.
        ///
        /// ScannerException (MarkedYAMLException) copies string data passed to its
        /// constructor so it's safe to use slices of this buffer as parameters for
        /// exceptions that may outlive the Scanner. The GC allocation when creating the
        /// error message is removed, but the allocation when creating an exception is
        /// not.
        char[256] msgBuffer_;

    public:
        /// Construct a Scanner using specified Reader.
        this(Reader reader) @safe nothrow
        {
            // Return the next token, but do not delete it from the queue
            reader_   = reader;
            appender_ = appender!(dchar[])();
            fetchStreamStart();
        }

        /// Destroy the scanner.
        @trusted ~this()
        {
            tokens_.destroy();
            indents_.destroy();
            possibleSimpleKeys_.destroy();
            possibleSimpleKeys_ = null;
            appender_.destroy();
            reader_ = null;
        }

        /**
         * Check if the next token is one of specified types.
         *
         * If no types are specified, checks if any tokens are left.
         *
         * Params:  ids = Token IDs to check for.
         *
         * Returns: true if the next token is one of specified types,
         *          or if there are any tokens left if no types specified.
         *          false otherwise.
         */
        bool checkToken(const TokenID[] ids ...) @safe
        {
            //Check if the next token is one of specified types.
            while(needMoreTokens()){fetchToken();}
            if(!tokens_.empty)
            {
                if(ids.length == 0){return true;}
                else
                {
                    const nextId = tokens_.peek().id;
                    foreach(id; ids)
                    {
                        if(nextId == id){return true;}
                    }
                }
            }
            return false;
        }

        /**
         * Return the next token, but keep it in the queue.
         *
         * Must not be called if there are no tokens left.
         */
        ref const(Token) peekToken() @safe
        {
            while(needMoreTokens){fetchToken();}
            if(!tokens_.empty){return tokens_.peek();}
            assert(false, "No token left to peek");
        }

        /**
         * Return the next token, removing it from the queue.
         *
         * Must not be called if there are no tokens left.
         */
        Token getToken() @safe
        {
            while(needMoreTokens){fetchToken();}
            if(!tokens_.empty)
            {
                ++tokensTaken_;
                return tokens_.pop();
            }
            assert(false, "No token left to get");
        }

    private:
        /// Build an error message in msgBuffer_ and return it as a string.
        string buildMsg(S ...)(S args) @trusted pure nothrow @nogc
        {
            return cast(string)msgBuffer_.printNoGC(args);
        }

        /// If error_ is true, throws a ScannerException constructed from errorData_ and
        /// sets error_ to false.
        void throwIfError() @safe pure
        {
            if(!error_) { return; }
            error_ = false;
            throw new ScannerException(errorData_);
        }

        /// Called by internal nothrow/@nogc methods to set an error to be thrown by
        /// their callers.
        ///
        /// See_Also: dyaml.exception.MarkedYamlException
        void setError(string context, const Mark contextMark, string problem,
                      const Mark problemMark) @safe pure nothrow @nogc
        {
            assert(error_ == false,
                   "Setting an error when there already is a not yet thrown error");
            error_     = true;
            errorData_ = MarkedYAMLExceptionData(context, contextMark, problem, problemMark);
        }

        ///Determine whether or not we need to fetch more tokens before peeking/getting a token.
        bool needMoreTokens() @safe pure
        {
            if(done_)        {return false;}
            if(tokens_.empty){return true;}

            ///The current token may be a potential simple key, so we need to look further.
            stalePossibleSimpleKeys();
            return nextPossibleSimpleKey() == tokensTaken_;
        }

        ///Fetch at token, adding it to tokens_.
        void fetchToken() @safe
        {
            ///Eat whitespaces and comments until we reach the next token.
            scanToNextToken();

            //Remove obsolete possible simple keys.
            stalePossibleSimpleKeys();

            //Compare current indentation and column. It may add some tokens
            //and decrease the current indentation level.
            unwindIndent(reader_.column);

            //Get the next character.
            const dchar c = reader_.peek();

            //Fetch the token.
            if(c == '\0')                  {return fetchStreamEnd();}
            if(checkDirective())           {return fetchDirective();}
            if(checkDocumentStart())       {return fetchDocumentStart();}
            if(checkDocumentEnd())         {return fetchDocumentEnd();}
            //Order of the following checks is NOT significant.
            if(c == '[')                   {return fetchFlowSequenceStart();}
            if(c == '{')                   {return fetchFlowMappingStart();}
            if(c == ']')                   {return fetchFlowSequenceEnd();}
            if(c == '}')                   {return fetchFlowMappingEnd();}
            if(c == ',')                   {return fetchFlowEntry();}
            if(checkBlockEntry())          {return fetchBlockEntry();}
            if(checkKey())                 {return fetchKey();}
            if(checkValue())               {return fetchValue();}
            if(c == '*')                   {return fetchAlias();}
            if(c == '&')                   {return fetchAnchor();}
            if(c == '!')                   {return fetchTag();}
            if(c == '|' && flowLevel_ == 0){return fetchLiteral();}
            if(c == '>' && flowLevel_ == 0){return fetchFolded();}
            if(c == '\'')                  {return fetchSingle();}
            if(c == '\"')                  {return fetchDouble();}
            if(checkPlain())               {return fetchPlain();}

            throw new Error(format("While scanning for the next token, found "
                                   "character \'%s\', index %s that cannot start any token"
                                   , c, to!int(c)), reader_.mark);
        }


        ///Return the token number of the nearest possible simple key.
        uint nextPossibleSimpleKey() @safe pure nothrow @nogc
        {
            uint minTokenNumber = uint.max;
            foreach(k, ref simpleKey; possibleSimpleKeys_)
            {
                if(simpleKey.isNull){continue;}
                minTokenNumber = min(minTokenNumber, simpleKey.tokenIndex);
            }
            return minTokenNumber;
        }

        /**
         * Remove entries that are no longer possible simple keys.
         *
         * According to the YAML specification, simple keys
         * - should be limited to a single line,
         * - should be no longer than 1024 characters.
         * Disabling this will allow simple keys of any length and
         * height (may cause problems if indentation is broken though).
         */
        void stalePossibleSimpleKeys() @safe pure
        {
            foreach(level, ref key; possibleSimpleKeys_)
            {
                if(key.isNull){continue;}
                if(key.line != reader_.line || reader_.charIndex - key.charIndex > 1024)
                {
                    enforce(!key.required,
                            new Error("While scanning a simple key",
                                      Mark(key.line, key.column),
                                      "could not find expected ':'", reader_.mark));
                    key.isNull = true;
                }
            }
        }

        /**
         * Check if the next token starts a possible simple key and if so, save its position.
         *
         * This function is called for ALIAS, ANCHOR, TAG, SCALAR(flow), '[', and '{'.
         */
        void savePossibleSimpleKey() @safe pure
        {
            //Check if a simple key is required at the current position.
            const required = (flowLevel_ == 0 && indent_ == reader_.column);
            assert(allowSimpleKey_ || !required, "A simple key is required only if it is "
                   "the first token in the current line. Therefore it is always allowed.");

            if(!allowSimpleKey_){return;}

            //The next token might be a simple key, so save its number and position.
            removePossibleSimpleKey();
            const tokenCount = tokensTaken_ + cast(uint)tokens_.length;

            const line = reader_.line;
            const column = reader_.column;
            const key = SimpleKey(cast(uint)reader_.charIndex,
                                  tokenCount,
                                  line,
                                  column < ushort.max ? cast(ushort)column : ushort.max,
                                  required);

            if(possibleSimpleKeys_.length <= flowLevel_)
            {
                const oldLength = possibleSimpleKeys_.length;
                possibleSimpleKeys_.length = flowLevel_ + 1;
                //No need to initialize the last element, it's already done in the next line.
                possibleSimpleKeys_[oldLength .. flowLevel_] = SimpleKey.init;
            }
            possibleSimpleKeys_[flowLevel_] = key;
        }

        ///Remove the saved possible key position at the current flow level.
        void removePossibleSimpleKey() @safe pure
        {
            if(possibleSimpleKeys_.length <= flowLevel_){return;}

            if(!possibleSimpleKeys_[flowLevel_].isNull)
            {
                const key = possibleSimpleKeys_[flowLevel_];
                enforce(!key.required,
                        new Error("While scanning a simple key", Mark(key.line, key.column),
                                  "could not find expected ':'", reader_.mark));
                possibleSimpleKeys_[flowLevel_].isNull = true;
            }
        }

        /**
         * Decrease indentation, removing entries in indents_.
         *
         * Params:  column = Current column in the file/stream.
         */
        void unwindIndent(const int column) @trusted
        {
            if(flowLevel_ > 0)
            {
                //In flow context, tokens should respect indentation.
                //The condition should be `indent >= column` according to the spec.
                //But this condition will prohibit intuitively correct
                //constructions such as
                //key : {
                //}

                //In the flow context, indentation is ignored. We make the scanner less
                //restrictive than what the specification requires.
                //if(pedantic_ && flowLevel_ > 0 && indent_ > column)
                //{
                //    throw new Error("Invalid intendation or unclosed '[' or '{'",
                //                    reader_.mark)
                //}
                return;
            }

            //In block context, we may need to issue the BLOCK-END tokens.
            while(indent_ > column)
            {
                indent_ = indents_.back;
                indents_.length = indents_.length - 1;
                tokens_.push(blockEndToken(reader_.mark, reader_.mark));
            }
        }

        /**
         * Increase indentation if needed.
         *
         * Params:  column = Current column in the file/stream.
         *
         * Returns: true if the indentation was increased, false otherwise.
         */
        bool addIndent(int column) @trusted
        {
            if(indent_ >= column){return false;}
            indents_ ~= indent_;
            indent_ = column;
            return true;
        }


        ///Add STREAM-START token.
        void fetchStreamStart() @safe nothrow
        {
            tokens_.push(streamStartToken(reader_.mark, reader_.mark, reader_.encoding));
        }

        ///Add STREAM-END token.
        void fetchStreamEnd() @safe
        {
            //Set intendation to -1 .
            unwindIndent(-1);
            removePossibleSimpleKey();
            allowSimpleKey_ = false;
            possibleSimpleKeys_.destroy;

            tokens_.push(streamEndToken(reader_.mark, reader_.mark));
            done_ = true;
        }

        ///Add DIRECTIVE token.
        void fetchDirective() @safe
        {
            //Set intendation to -1 .
            unwindIndent(-1);
            //Reset simple keys.
            removePossibleSimpleKey();
            allowSimpleKey_ = false;

            tokens_.push(scanDirective());
        }

        ///Add DOCUMENT-START or DOCUMENT-END token.
        void fetchDocumentIndicator(TokenID id)() @safe
            if(id == TokenID.DocumentStart || id == TokenID.DocumentEnd)
        {
            //Set indentation to -1 .
            unwindIndent(-1);
            //Reset simple keys. Note that there can't be a block collection after '---'.
            removePossibleSimpleKey();
            allowSimpleKey_ = false;

            Mark startMark = reader_.mark;
            reader_.forward(3);
            tokens_.push(simpleToken!id(startMark, reader_.mark));
        }

        ///Aliases to add DOCUMENT-START or DOCUMENT-END token.
        alias fetchDocumentIndicator!(TokenID.DocumentStart) fetchDocumentStart;
        alias fetchDocumentIndicator!(TokenID.DocumentEnd) fetchDocumentEnd;

        ///Add FLOW-SEQUENCE-START or FLOW-MAPPING-START token.
        void fetchFlowCollectionStart(TokenID id)() @trusted
        {
            //'[' and '{' may start a simple key.
            savePossibleSimpleKey();
            //Simple keys are allowed after '[' and '{'.
            allowSimpleKey_ = true;
            ++flowLevel_;

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(simpleToken!id(startMark, reader_.mark));
        }

        ///Aliases to add FLOW-SEQUENCE-START or FLOW-MAPPING-START token.
        alias fetchFlowCollectionStart!(TokenID.FlowSequenceStart) fetchFlowSequenceStart;
        alias fetchFlowCollectionStart!(TokenID.FlowMappingStart) fetchFlowMappingStart;

        ///Add FLOW-SEQUENCE-START or FLOW-MAPPING-START token.
        void fetchFlowCollectionEnd(TokenID id)() @safe
        {
            //Reset possible simple key on the current level.
            removePossibleSimpleKey();
            //No simple keys after ']' and '}'.
            allowSimpleKey_ = false;
            --flowLevel_;

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(simpleToken!id(startMark, reader_.mark));
        }

        ///Aliases to add FLOW-SEQUENCE-START or FLOW-MAPPING-START token/
        alias fetchFlowCollectionEnd!(TokenID.FlowSequenceEnd) fetchFlowSequenceEnd;
        alias fetchFlowCollectionEnd!(TokenID.FlowMappingEnd) fetchFlowMappingEnd;

        ///Add FLOW-ENTRY token;
        void fetchFlowEntry() @safe
        {
            //Reset possible simple key on the current level.
            removePossibleSimpleKey();
            //Simple keys are allowed after ','.
            allowSimpleKey_ = true;

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(flowEntryToken(startMark, reader_.mark));
        }

        /**
         * Additional checks used in block context in fetchBlockEntry and fetchKey.
         *
         * Params:  type = String representing the token type we might need to add.
         *          id   = Token type we might need to add.
         */
        void blockChecks(string type, TokenID id)() @safe
        {
            //Are we allowed to start a key (not neccesarily a simple one)?
            enforce(allowSimpleKey_, new Error(type ~ " keys are not allowed here",
                                               reader_.mark));

            if(addIndent(reader_.column))
            {
                tokens_.push(simpleToken!id(reader_.mark, reader_.mark));
            }
        }

        ///Add BLOCK-ENTRY token. Might add BLOCK-SEQUENCE-START in the process.
        void fetchBlockEntry() @safe
        {
            if(flowLevel_ == 0){blockChecks!("Sequence", TokenID.BlockSequenceStart)();}

            //It's an error for the block entry to occur in the flow context,
            //but we let the parser detect this.

            //Reset possible simple key on the current level.
            removePossibleSimpleKey();
            //Simple keys are allowed after '-'.
            allowSimpleKey_ = true;

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(blockEntryToken(startMark, reader_.mark));
        }

        ///Add KEY token. Might add BLOCK-MAPPING-START in the process.
        void fetchKey() @safe
        {
            if(flowLevel_ == 0){blockChecks!("Mapping", TokenID.BlockMappingStart)();}

            //Reset possible simple key on the current level.
            removePossibleSimpleKey();
            //Simple keys are allowed after '?' in the block context.
            allowSimpleKey_ = (flowLevel_ == 0);

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(keyToken(startMark, reader_.mark));
        }

        ///Add VALUE token. Might add KEY and/or BLOCK-MAPPING-START in the process.
        void fetchValue() @safe
        {
            //Do we determine a simple key?
            if(possibleSimpleKeys_.length > flowLevel_ &&
               !possibleSimpleKeys_[flowLevel_].isNull)
            {
                const key = possibleSimpleKeys_[flowLevel_];
                possibleSimpleKeys_[flowLevel_].isNull = true;
                Mark keyMark = Mark(key.line, key.column);
                const idx = key.tokenIndex - tokensTaken_;

                assert(idx >= 0);

                //Add KEY.
                //Manually inserting since tokens are immutable (need linked list).
                tokens_.insert(keyToken(keyMark, keyMark), idx);

                //If this key starts a new block mapping, we need to add BLOCK-MAPPING-START.
                if(flowLevel_ == 0 && addIndent(key.column))
                {
                    tokens_.insert(blockMappingStartToken(keyMark, keyMark), idx);
                }

                //There cannot be two simple keys in a row.
                allowSimpleKey_ = false;
            }
            //Part of a complex key
            else
            {
                //We can start a complex value if and only if we can start a simple key.
                enforce(flowLevel_ > 0 || allowSimpleKey_,
                        new Error("Mapping values are not allowed here", reader_.mark));

                //If this value starts a new block mapping, we need to add
                //BLOCK-MAPPING-START. It'll be detected as an error later by the parser.
                if(flowLevel_ == 0 && addIndent(reader_.column))
                {
                    tokens_.push(blockMappingStartToken(reader_.mark, reader_.mark));
                }

                //Reset possible simple key on the current level.
                removePossibleSimpleKey();
                //Simple keys are allowed after ':' in the block context.
                allowSimpleKey_ = (flowLevel_ == 0);
            }

            //Add VALUE.
            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(valueToken(startMark, reader_.mark));
        }

        ///Add ALIAS or ANCHOR token.
        void fetchAnchor_(TokenID id)() @trusted
            if(id == TokenID.Alias || id == TokenID.Anchor)
        {
            //ALIAS/ANCHOR could be a simple key.
            savePossibleSimpleKey();
            //No simple keys after ALIAS/ANCHOR.
            allowSimpleKey_ = false;

            tokens_.push(scanAnchor(id));
        }

        ///Aliases to add ALIAS or ANCHOR token.
        alias fetchAnchor_!(TokenID.Alias) fetchAlias;
        alias fetchAnchor_!(TokenID.Anchor) fetchAnchor;

        ///Add TAG token.
        void fetchTag() @trusted
        {
            //TAG could start a simple key.
            savePossibleSimpleKey();
            //No simple keys after TAG.
            allowSimpleKey_ = false;

            tokens_.push(scanTag());
            throwIfError();
        }

        ///Add block SCALAR token.
        void fetchBlockScalar(ScalarStyle style)() @trusted
            if(style == ScalarStyle.Literal || style == ScalarStyle.Folded)
        {
            //Reset possible simple key on the current level.
            removePossibleSimpleKey();
            //A simple key may follow a block scalar.
            allowSimpleKey_ = true;

            tokens_.push(scanBlockScalar(style));
        }

        /// Aliases to add literal or folded block scalar.
        alias fetchBlockScalar!(ScalarStyle.Literal) fetchLiteral;
        alias fetchBlockScalar!(ScalarStyle.Folded) fetchFolded;

        /// Add quoted flow SCALAR token.
        void fetchFlowScalar(ScalarStyle quotes)() @safe
        {
            // A flow scalar could be a simple key.
            savePossibleSimpleKey();
            // No simple keys after flow scalars.
            allowSimpleKey_ = false;

            // Scan and add SCALAR.
            const scalar = scanFlowScalar(quotes);
            throwIfError();
            tokens_.push(scalar);
        }

        /// Aliases to add single or double quoted block scalar.
        alias fetchFlowScalar!(ScalarStyle.SingleQuoted) fetchSingle;
        alias fetchFlowScalar!(ScalarStyle.DoubleQuoted) fetchDouble;

        /// Add plain SCALAR token.
        void fetchPlain() @safe
        {
            // A plain scalar could be a simple key
            savePossibleSimpleKey();
            // No simple keys after plain scalars. But note that scanPlain() will
            // change this flag if the scan is finished at the beginning of the line.
            allowSimpleKey_ = false;
            const plain = scanPlain();
            throwIfError();

            // Scan and add SCALAR. May change allowSimpleKey_
            tokens_.push(plain);
        }

        ///Check if the next token is DIRECTIVE:        ^ '%' ...
        bool checkDirective() @safe pure nothrow @nogc
        {
            return reader_.peek() == '%' && reader_.column == 0;
        }

        /// Check if the next token is DOCUMENT-START:   ^ '---' (' '|'\n')
        bool checkDocumentStart() @safe
        {
            // Check one char first, then all 3, to prevent reading outside the buffer.
            return reader_.column    == 0     &&
                   reader_.peek()    == '-'   &&
                   reader_.prefix(3) == "---" &&
                   " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(3));
        }

        /// Check if the next token is DOCUMENT-END:     ^ '...' (' '|'\n')
        bool checkDocumentEnd() @safe pure nothrow @nogc
        {
            // Check one char first, then all 3, to prevent reading outside the buffer.
            return reader_.column    == 0     &&
                   reader_.peek()    == '.'   &&
                   reader_.prefix(3) == "..." &&
                   " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(3));
        }

        ///Check if the next token is BLOCK-ENTRY:      '-' (' '|'\n')
        bool checkBlockEntry() @safe pure nothrow @nogc
        {
            return reader_.peek() == '-' &&
                   " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(1));
        }

        /**
         * Check if the next token is KEY(flow context):    '?'
         *
         * or KEY(block context):   '?' (' '|'\n')
         */
        bool checkKey() @safe pure nothrow @nogc
        {
            return reader_.peek() == '?' &&
                   (flowLevel_ > 0 ||
                   " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(1)));
        }

        /**
         * Check if the next token is VALUE(flow context):  ':'
         *
         * or VALUE(block context): ':' (' '|'\n')
         */
        bool checkValue() @safe pure nothrow @nogc
        {
            return reader_.peek() == ':' &&
                   (flowLevel_ > 0 ||
                   " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(1)));
        }

        /**
         * Check if the next token is a plain scalar.
         *
         * A plain scalar may start with any non-space character except:
         *   '-', '?', ':', ',', '[', ']', '{', '}',
         *   '#', '&', '*', '!', '|', '>', '\'', '\"',
         *   '%', '@', '`'.
         *
         * It may also start with
         *   '-', '?', ':'
         * if it is followed by a non-space character.
         *
         * Note that we limit the last rule to the block context (except the
         * '-' character) because we want the flow context to be space
         * independent.
         */
        bool checkPlain() @safe pure nothrow @nogc
        {
            const c = reader_.peek();
            return !("-?:,[]{}#&*!|>\'\"%@` \t\0\n\r\u0085\u2028\u2029"d.canFind(c)) ||
                    (!" \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(1)) &&
                     (c == '-' || (flowLevel_ == 0 && "?:"d.canFind(c))));
        }

        /// Move to the next non-space character.
        void findNextNonSpace() @safe pure nothrow @nogc
        {
            while(reader_.peek() == ' ') { reader_.forward(); }
        }

        /// Scan a string of alphanumeric or "-_" characters.
        dchar[] scanAlphaNumeric(string name)(const Mark startMark) @safe pure
        {
            uint length = 0;
            dchar c = reader_.peek();
            while(isAlphaNum(c) || "-_"d.canFind(c))
            {
                ++length;
                c = reader_.peek(length);
            }

            enforce(length > 0,
                    new Error("While scanning " ~ name, startMark,
                              "expected alphanumeric, - or _, but found " ~ to!string(c),
                              reader_.mark));

            return reader_.get(length);
        }

        /// Scan all characters until next line break.
        dchar[] scanToNextBreak() @safe pure nothrow @nogc
        {
            uint length = 0;
            while(!"\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(length)))
            {
                ++length;
            }
            return reader_.get(length);
        }

        /**
         * Move to next token in the file/stream.
         *
         * We ignore spaces, line breaks and comments.
         * If we find a line break in the block context, we set
         * allowSimpleKey` on.
         *
         * We do not yet support BOM inside the stream as the
         * specification requires. Any such mark will be considered as a part
         * of the document.
         */
        void scanToNextToken() @safe pure nothrow @nogc
        {
            //TODO(PyYAML): We need to make tab handling rules more sane. A good rule is:
            //  Tabs cannot precede tokens
            //  BLOCK-SEQUENCE-START, BLOCK-MAPPING-START, BLOCK-END,
            //  KEY(block), VALUE(block), BLOCK-ENTRY
            //So the checking code is
            //  if <TAB>:
            //      allowSimpleKey_ = false
            //We also need to add the check for `allowSimpleKey_ == true` to
            //`unwindIndent` before issuing BLOCK-END.
            //Scanners for block, flow, and plain scalars need to be modified.

            for(;;)
            {
                findNextNonSpace();

                if(reader_.peek() == '#'){scanToNextBreak();}
                if(scanLineBreak() != '\0')
                {
                    if(flowLevel_ == 0){allowSimpleKey_ = true;}
                }
                else{break;}
            }
        }

        ///Scan directive token.
        Token scanDirective() @safe pure
        {
            Mark startMark = reader_.mark;
            //Skip the '%'.
            reader_.forward();

            auto name  = scanDirectiveName(startMark);
            auto value = name == "YAML" ? scanYAMLDirectiveValue(startMark):
                         name == "TAG"  ? scanTagDirectiveValue(startMark) : "";

            Mark endMark = reader_.mark;

            if(!["YAML"d, "TAG"d].canFind(name)){scanToNextBreak();}
            scanDirectiveIgnoredLine(startMark);

            //Storing directive name and value in a single string, separated by zero.
            return directiveToken(startMark, endMark, utf32To8(name ~ '\0' ~ value));
        }

        ///Scan name of a directive token.
        dchar[] scanDirectiveName(const Mark startMark) @safe pure
        {
            //Scan directive name.
            auto name = scanAlphaNumeric!"a directive"(startMark);

            enforce(" \0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()),
                    new Error("While scanning a directive", startMark,
                              "expected alphanumeric, - or _, but found "
                              ~ to!string(reader_.peek()), reader_.mark));
            return name;
        }

        ///Scan value of a YAML directive token. Returns major, minor version separated by '.'.
        dchar[] scanYAMLDirectiveValue(const Mark startMark) @safe pure
        {
            findNextNonSpace();

            dchar[] result = scanYAMLDirectiveNumber(startMark);
            enforce(reader_.peek() == '.',
                    new Error("While scanning a directive", startMark,
                              "expected a digit or '.', but found: "
                              ~ to!string(reader_.peek()), reader_.mark));
            //Skip the '.'.
            reader_.forward();

            result ~= '.' ~ scanYAMLDirectiveNumber(startMark);
            enforce(" \0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()),
                    new Error("While scanning a directive", startMark,
                              "expected a digit or '.', but found: "
                              ~ to!string(reader_.peek()), reader_.mark));
            return result;
        }

        /// Scan a number from a YAML directive.
        dchar[] scanYAMLDirectiveNumber(const Mark startMark) @safe pure
        {
            enforce(isDigit(reader_.peek()),
                    new Error("While scanning a directive", startMark,
                              "expected a digit, but found: " ~
                              reader_.peek().to!string, reader_.mark));

            // Already found the first digit in the enforce(), so set length to 1.
            uint length = 1;
            while(isDigit(reader_.peek(length))) { ++length; }

            return reader_.get(length);
        }

        /// Scan value of a tag directive.
        dstring scanTagDirectiveValue(const Mark startMark) @safe pure
        {
            findNextNonSpace();
            const handle = scanTagDirectiveHandle(startMark);
            findNextNonSpace();
            return handle ~ '\0' ~ scanTagDirectivePrefix(startMark);
        }

        ///Scan handle of a tag directive.
        dstring scanTagDirectiveHandle(const Mark startMark) @trusted pure
        {
            reader_.sliceBuilder.begin();
            {
                scope(failure) { reader_.sliceBuilder.finish(); }
                scanTagHandleToSlice!"directive"(startMark);
                throwIfError();
            }
            auto value = reader_.sliceBuilder.finish();
            enforce(reader_.peek() == ' ',
                    new Error("While scanning a directive handle", startMark,
                              "expected ' ', but found: " ~ to!string(reader_.peek()),
                              reader_.mark));
            return value;
        }

        /// Scan prefix of a tag directive.
        dstring scanTagDirectivePrefix(const Mark startMark) @trusted pure
        {
            reader_.sliceBuilder.begin();
            {
                scope(failure) { reader_.sliceBuilder.finish(); }
                scanTagURIToSlice!"directive"(startMark);
                throwIfError();
            }
            auto value = reader_.sliceBuilder.finish();
            enforce(" \0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()),
                    new Error("While scanning a directive prefix", startMark,
                              "expected ' ', but found" ~ reader_.peek().to!string,
                              reader_.mark));

            return value;
        }

        ///Scan (and ignore) ignored line after a directive.
        void scanDirectiveIgnoredLine(const Mark startMark) @safe pure
        {
            findNextNonSpace();
            if(reader_.peek() == '#'){scanToNextBreak();}
            enforce("\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()),
                    new Error("While scanning a directive", startMark,
                              "expected comment or a line break, but found"
                              ~ to!string(reader_.peek()), reader_.mark));
            scanLineBreak();
        }


        /**
         * Scan an alias or an anchor.
         *
         * The specification does not restrict characters for anchors and
         * aliases. This may lead to problems, for instance, the document:
         *   [ *alias, value ]
         * can be interpteted in two ways, as
         *   [ "value" ]
         * and
         *   [ *alias , "value" ]
         * Therefore we restrict aliases to ASCII alphanumeric characters.
         */
        Token scanAnchor(TokenID id) @safe pure
        {
            const startMark = reader_.mark;

            const dchar i = reader_.get();

            dchar[] value = i == '*' ? scanAlphaNumeric!("an alias")(startMark)
                                     : scanAlphaNumeric!("an anchor")(startMark);

            enforce((" \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()) ||
                     ("?:,]}%@").canFind(reader_.peek())),
                    new Error("While scanning an " ~ (i == '*') ? "alias" : "anchor",
                                         startMark, "expected alphanumeric, - or _, but found "~
                                         to!string(reader_.peek()), reader_.mark));

            if(id == TokenID.Alias)
            {
                return aliasToken(startMark, reader_.mark, value.utf32To8);
            }
            else if(id == TokenID.Anchor)
            {
                return anchorToken(startMark, reader_.mark, value.utf32To8);
            }
            assert(false, "This code should never be reached");
        }

        /// Scan a tag token.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        Token scanTag() @trusted pure nothrow
        {
            const startMark = reader_.mark;
            dchar c = reader_.peek(1);

            reader_.sliceBuilder.begin();
            scope(failure) { reader_.sliceBuilder.finish(); }
            // Index where tag handle ends and tag suffix starts in the tag value
            // (slice) we will produce.
            uint handleEnd;

            if(c == '<')
            {
                reader_.forward(2);

                handleEnd = 0;
                scanTagURIToSlice!"tag"(startMark);
                if(error_) { return Token.init; }
                if(reader_.peek() != '>')
                {
                    setError("While scanning a tag", startMark,
                             buildMsg("expected '>' but found ", reader_.peek()),
                             reader_.mark);
                    return Token.init;
                }
                reader_.forward();
            }
            else if(" \t\0\n\r\u0085\u2028\u2029"d.canFind(c))
            {
                reader_.forward();
                handleEnd = 0;
                reader_.sliceBuilder.write('!');
            }
            else
            {
                uint length = 1;
                bool useHandle = false;

                while(!" \0\n\r\u0085\u2028\u2029"d.canFind(c))
                {
                    if(c == '!')
                    {
                        useHandle = true;
                        break;
                    }
                    ++length;
                    c = reader_.peek(length);
                }

                if(useHandle)
                {
                    scanTagHandleToSlice!"tag"(startMark);
                    handleEnd = cast(uint)reader_.sliceBuilder.length;
                    if(error_) { return Token.init; }
                }
                else
                {
                    reader_.forward();
                    reader_.sliceBuilder.write('!');
                    handleEnd = cast(uint)reader_.sliceBuilder.length;
                }

                scanTagURIToSlice!"tag"(startMark);
                if(error_) { return Token.init; }
            }

            if(!" \0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()))
            {
                setError("While scanning a tag", startMark,
                         buildMsg("expected ' ' but found ", reader_.peek()),
                         reader_.mark);
                return Token.init;
            }
            const slice = reader_.sliceBuilder.finish();
            return tagToken(startMark, reader_.mark, slice.utf32To8, handleEnd);
        }

        ///Scan a block scalar token with specified style.
        Token scanBlockScalar(const ScalarStyle style) @trusted pure
        {
            const startMark = reader_.mark;

            //Scan the header.
            reader_.forward();

            const indicators = scanBlockScalarIndicators(startMark);
            throwIfError();

            const chomping   = indicators[0];
            const increment  = indicators[1];
            scanBlockScalarIgnoredLine(startMark);
            throwIfError();

            //Determine the indentation level and go to the first non-empty line.
            Mark endMark;
            dstring breaks;
            uint indent = max(1, indent_ + 1);
            if(increment == int.min)
            {
                auto indentation = scanBlockScalarIndentation();
                breaks  = indentation[0];
                endMark = indentation[2];
                indent  = max(indent, indentation[1]);
            }
            else
            {
                indent += increment - 1;
                auto scalarBreaks = scanBlockScalarBreaks(indent);
                breaks  = scalarBreaks[0];
                endMark = scalarBreaks[1];
            }

            dchar[] lineBreak = ""d.dup;

            //Using appender_, so clear it when we're done.
            scope(exit){appender_.clear();}

            //Scan the inner part of the block scalar.
            while(reader_.column == indent && reader_.peek() != '\0')
            {
                appender_.put(breaks);
                const bool leadingNonSpace = !" \t"d.canFind(reader_.peek());
                appender_.put(scanToNextBreak());
                lineBreak = [scanLineBreak()];

                auto scalarBreaks = scanBlockScalarBreaks(indent);
                breaks  = scalarBreaks[0];
                endMark = scalarBreaks[1];

                if(reader_.column == indent && reader_.peek() != '\0')
                {
                    //Unfortunately, folding rules are ambiguous.

                    //This is the folding according to the specification:
                    if(style == ScalarStyle.Folded && lineBreak == "\n" &&
                       leadingNonSpace && !" \t"d.canFind(reader_.peek()))
                    {
                        if(breaks.length == 0){appender_.put(' ');}
                    }
                    else{appender_.put(lineBreak);}
                    ////this is Clark Evans's interpretation (also in the spec
                    ////examples):
                    //
                    //if(style == ScalarStyle.Folded && lineBreak == "\n"d)
                    //{
                    //    if(breaks.length == 0)
                    //    {
                    //        if(!" \t"d.canFind(reader_.peek())){appender_.put(' ');}
                    //        else{chunks ~= lineBreak;}
                    //    }
                    //}
                    //else{appender_.put(lineBreak);}
                }
                else{break;}
            }
            if(chomping != Chomping.Strip){appender_.put(lineBreak);}
            if(chomping == Chomping.Keep){appender_.put(breaks);}

            return scalarToken(startMark, endMark, utf32To8(appender_.data), style);
        }

        /// Scan chomping and indentation indicators of a scalar token.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        Tuple!(Chomping, int) scanBlockScalarIndicators(const Mark startMark)
            @safe pure nothrow @nogc
        {
            auto chomping = Chomping.Clip;
            int increment = int.min;
            dchar c       = reader_.peek();

            /// Indicators can be in any order.
            if(getChomping(c, chomping))
            {
                getIncrement(c, increment, startMark);
                if(error_) { return tuple(Chomping.init, int.max); }
            }
            else
            {
                const gotIncrement = getIncrement(c, increment, startMark);
                if(error_)       { return tuple(Chomping.init, int.max); }
                if(gotIncrement) { getChomping(c, chomping); }
            }

            if(!" \0\n\r\u0085\u2028\u2029"d.canFind(c))
            {
                setError("While scanning a block scalar", startMark,
                         buildMsg("expected chomping or indentation indicator, but found ", c),
                         reader_.mark);
                return tuple(Chomping.init, int.max);
            }

            return tuple(chomping, increment);
        }

        /// Get chomping indicator, if detected. Return false otherwise.
        ///
        /// Used in scanBlockScalarIndicators.
        ///
        /// Params:
        ///
        /// c        = The character that may be a chomping indicator.
        /// chomping = Write the chomping value here, if detected.
        bool getChomping(ref dchar c, ref Chomping chomping) @safe pure nothrow @nogc
        {
            if(!"+-"d.canFind(c)) { return false; }
            chomping = c == '+' ? Chomping.Keep : Chomping.Strip;
            reader_.forward();
            c = reader_.peek();
            return true;
        }

        /// Get increment indicator, if detected. Return false otherwise.
        ///
        /// Used in scanBlockScalarIndicators.
        ///
        /// Params:
        ///
        /// c         = The character that may be an increment indicator.
        ///             If an increment indicator is detected, this will be updated to
        ///             the next character in the Reader.
        /// increment = Write the increment value here, if detected.
        /// startMark = Mark for error messages.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        bool getIncrement(ref dchar c, ref int increment, const Mark startMark)
            @safe pure nothrow @nogc
        {
            if(!c.isDigit) { return false; }
            // Convert a digit to integer.
            increment = c - '0';
            assert(increment < 10 && increment >= 0, "Digit has invalid value");
            if(increment == 0)
            {
                setError("While scanning a block scalar", startMark,
                         "expected indentation indicator in range 1-9, but found 0",
                         reader_.mark);
                return false;
            }
            reader_.forward();
            c = reader_.peek();
            return true;
        }

        /// Scan (and ignore) ignored line in a block scalar.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        void scanBlockScalarIgnoredLine(const Mark startMark) @safe pure nothrow @nogc
        {
            findNextNonSpace();
            if(reader_.peek()== '#') { scanToNextBreak(); }

            if(!"\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()))
            {
                setError("While scanning a block scalar", startMark,
                         buildMsg("expected comment or line break, but found ", reader_.peek()),
                         reader_.mark);
                return;
            }
            scanLineBreak();
        }

        /// Scan indentation in a block scalar, returning line breaks, max indent and end mark.
        Tuple!(dstring, uint, Mark) scanBlockScalarIndentation() 
            @system pure nothrow @nogc
        {
            reader_.sliceBuilder.begin();
            uint maxIndent;
            Mark endMark = reader_.mark;

            while(" \n\r\u0085\u2028\u2029"d.canFind(reader_.peek()))
            {
                if(reader_.peek() != ' ')
                {
                    reader_.sliceBuilder.write(scanLineBreak());
                    endMark = reader_.mark;
                    continue;
                }
                reader_.forward();
                maxIndent = max(reader_.column, maxIndent);
            }

            return tuple(reader_.sliceBuilder.finish(), maxIndent, endMark);
        }

        /// Scan line breaks at lower or specified indentation in a block scalar.
        Tuple!(dstring, Mark) scanBlockScalarBreaks(const uint indent)
            @trusted pure nothrow @nogc
        {
            reader_.sliceBuilder.begin();
            Mark endMark = reader_.mark;

            for(;;)
            {
                while(reader_.column < indent && reader_.peek() == ' ') { reader_.forward(); }
                if(!"\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()))  { break; }
                reader_.sliceBuilder.write(scanLineBreak());
                endMark = reader_.mark;
            }

            return tuple(reader_.sliceBuilder.finish(), endMark);
        }

        /// Scan a qouted flow scalar token with specified quotes.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        Token scanFlowScalar(const ScalarStyle quotes) @trusted pure nothrow
        {
            const startMark = reader_.mark;
            const quote     = reader_.get();

            reader_.sliceBuilder.begin();
            scope(exit) if(error_) { reader_.sliceBuilder.finish(); }

            scanFlowScalarNonSpacesToSlice(quotes, startMark);
            if(error_) { return Token.init; }

            while(reader_.peek() != quote)
            {
                scanFlowScalarSpacesToSlice(startMark);
                if(error_) { return Token.init; }
                scanFlowScalarNonSpacesToSlice(quotes, startMark);
                if(error_) { return Token.init; }
            }
            reader_.forward();

            auto slice = reader_.sliceBuilder.finish();
            return scalarToken(startMark, reader_.mark, slice.utf32To8, quotes);
        }

        /// Scan nonspace characters in a flow scalar.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        void scanFlowScalarNonSpacesToSlice(const ScalarStyle quotes, const Mark startMark)
            @system pure nothrow @nogc
        {
            for(;;) with(ScalarStyle)
            {
                dchar c = reader_.peek();

                mixin FastCharSearch!" \t\0\n\r\u0085\u2028\u2029\'\"\\"d search;

                size_t length = 0;
                // This is an optimized way of writing:
                // while(!search.canFind(reader_.peek(length))){++length;}
                outer: for(;;)
                {
                    const slice = reader_.slice(length, length + 32);
                    if(slice.empty)
                    {
                        setError("While reading a flow scalar", startMark,
                                 "reached end of file", reader_.mark);
                        return;
                    }
                    foreach(ch; slice)
                    {
                        if(search.canFind(ch)) { break outer; }
                        ++length;
                    }
                }

                reader_.sliceBuilder.write(reader_.get(length));

                c = reader_.peek();
                if(quotes == SingleQuoted && c == '\'' && reader_.peek(1) == '\'')
                {
                    reader_.forward(2);
                    reader_.sliceBuilder.write('\'');
                }
                else if((quotes == DoubleQuoted && c == '\'') ||
                        (quotes == SingleQuoted && "\"\\"d.canFind(c)))
                {
                    reader_.forward();
                    reader_.sliceBuilder.write(c);
                }
                else if(quotes == DoubleQuoted && c == '\\')
                {
                    reader_.forward();
                    c = reader_.peek();
                    if(dyaml.escapes.escapes.canFind(c))
                    {
                        reader_.forward();
                        reader_.sliceBuilder.write(dyaml.escapes.fromEscape(c));
                    }
                    else if(dyaml.escapes.escapeHexCodeList.canFind(c))
                    {
                        const hexLength = dyaml.escapes.escapeHexLength(c);
                        reader_.forward();

                        foreach(i; 0 .. hexLength) if(!reader_.peek(i).isHexDigit())
                        {
                            setError("While scanning a double quoted scalar", startMark,
                                     "found an unexpected character; expected escape "
                                     "sequence of hexadecimal numbers.", reader_.mark);
                            return;
                        }

                        dchar[] hex = reader_.get(hexLength);
                        bool overflow;
                        const decoded = cast(dchar)parseNoGC!int(hex, 16u, overflow);
                        if(overflow)
                        {
                            setError("While scanning a double quoted scalar", startMark,
                                     "overflow when parsing an escape sequence of "
                                     "hexadecimal numbers.", reader_.mark);
                            return;
                        }
                        reader_.sliceBuilder.write(decoded);
                    }
                    else if("\n\r\u0085\u2028\u2029"d.canFind(c))
                    {
                        scanLineBreak();
                        scanFlowScalarBreaksToSlice(startMark);
                        if(error_) { return; }
                    }
                    else
                    {
                        setError("While scanning a double quoted scalar", startMark,
                                 buildMsg("found unsupported escape " "character", c),
                                 reader_.mark);
                        return;
                    }
                }
                else { return; }
            }
        }

        /// Scan space characters in a flow scalar.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// spaces into that slice.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        void scanFlowScalarSpacesToSlice(const Mark startMark)
            @system pure nothrow @nogc
        {
            // Increase length as long as we see whitespace.
            size_t length = 0;
            while(" \t"d.canFind(reader_.peek(length))) { ++length; }
            auto whitespaces = reader_.prefix(length + 1);

            const c = whitespaces[$ - 1];
            if(c == '\0')
            {
                setError("While scanning a quoted scalar", startMark,
                         "found unexpected end of buffer", reader_.mark);
                return;
            }

            // Spaces not followed by a line break.
            if(!"\n\r\u0085\u2028\u2029"d.canFind(c))
            {
                reader_.forward(length);
                reader_.sliceBuilder.write(whitespaces[0 .. $ - 1]);
                return;
            }

            // There's a line break after the spaces.
            reader_.forward(length);
            const lineBreak = scanLineBreak();

            if(lineBreak != '\n') { reader_.sliceBuilder.write(lineBreak); }

            // If we have extra line breaks after the first, scan them into the
            // slice.
            const bool extraBreaks = scanFlowScalarBreaksToSlice(startMark);
            if(error_) { return; }

            // No extra breaks, one normal line break. Replace it with a space.
            if(lineBreak == '\n' && !extraBreaks) { reader_.sliceBuilder.write(' '); }
        }

        /// Scan line breaks in a flow scalar.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// line breaks into that slice.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        bool scanFlowScalarBreaksToSlice(const Mark startMark)
            @system pure nothrow @nogc
        {
            // True if at least one line break was found.
            bool anyBreaks;
            for(;;)
            {
                // Instead of checking indentation, we check for document separators.
                const prefix = reader_.prefix(3);
                if((prefix == "---"d || prefix == "..."d) &&
                   " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(3)))
                {
                    setError("While scanning a quoted scalar", startMark,
                             "found unexpected document separator", reader_.mark);
                    return false;
                }

                // Skip any whitespaces.
                while(" \t"d.canFind(reader_.peek())) { reader_.forward(); }

                // Encountered a non-whitespace non-linebreak character, so we're done.
                if(!"\n\r\u0085\u2028\u2029"d.canFind(reader_.peek())) { break; }

                const lineBreak = scanLineBreak();
                anyBreaks = true;
                reader_.sliceBuilder.write(lineBreak);
            }
            return anyBreaks;
        }

        /// Scan plain scalar token (no block, no quotes).
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        Token scanPlain() @trusted pure nothrow
        {
            // We keep track of the allowSimpleKey_ flag here.
            // Indentation rules are loosed for the flow context
            const startMark = reader_.mark;
            Mark endMark = startMark;
            const indent = indent_ + 1;

            // We allow zero indentation for scalars, but then we need to check for
            // document separators at the beginning of the line.
            // if(indent == 0) { indent = 1; }

            mixin FastCharSearch!" \t\0\n\r\u0085\u2028\u2029"d search;

            reader_.sliceBuilder.begin();

            alias Transaction = SliceBuilder.Transaction;
            Transaction spacesTransaction;
            // Stop at a comment.
            while(reader_.peek() != '#')
            {
                // Scan the entire plain scalar.
                uint length = 0;
                dchar c;
                for(;;)
                {
                    c = reader_.peek(length);
                    const bool done = search.canFind(c) || (flowLevel_ == 0 && c == ':' &&
                                      search.canFind(reader_.peek(length + 1))) ||
                                      (flowLevel_ > 0 && ",:?[]{}"d.canFind(c));
                    if(done) { break; }
                    ++length;
                }

                // It's not clear what we should do with ':' in the flow context.
                if(flowLevel_ > 0 && c == ':' &&
                   !search.canFind(reader_.peek(length + 1)) &&
                   !",[]{}"d.canFind(reader_.peek(length + 1)))
                {
                    // This is an error; throw the slice away.
                    spacesTransaction.commit();
                    reader_.sliceBuilder.finish();
                    reader_.forward(length);
                    setError("While scanning a plain scalar", startMark,
                             "found unexpected ':' . Please check "
                             "http://pyyaml.org/wiki/YAMLColonInFlowContext "
                             "for details.", reader_.mark);
                    return Token.init;
                }

                if(length == 0) { break; }

                allowSimpleKey_ = false;

                reader_.sliceBuilder.write(reader_.get(length));

                endMark = reader_.mark;

                spacesTransaction.commit();
                spacesTransaction = Transaction(reader_.sliceBuilder);

                const bool anySpaces = scanPlainSpacesToSlice(startMark);
                if(!anySpaces || (flowLevel_ == 0 && reader_.column < indent))
                {
                    break;
                }
            }

            spacesTransaction.__dtor();
            const slice = reader_.sliceBuilder.finish();

            return scalarToken(startMark, endMark, slice.utf32To8, ScalarStyle.Plain);
        }

        /// Scan spaces in a plain scalar.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the spaces
        /// into that slice.
        bool scanPlainSpacesToSlice(const Mark startMark) @system pure nothrow @nogc
        {
            // The specification is really confusing about tabs in plain scalars.
            // We just forbid them completely. Do not use tabs in YAML!

            // Get as many plain spaces as there are.
            size_t length = 0;
            while(reader_.peek(length) == ' ') { ++length; }
            dchar[] whitespaces = reader_.get(length);

            dchar c = reader_.peek();
            // No newline after the spaces (if any)
            if(!"\n\r\u0085\u2028\u2029"d.canFind(c))
            {
                // We have spaces, but no newline.
                if(whitespaces.length > 0)
                {
                    reader_.sliceBuilder.write(whitespaces);
                    return true;
                }
                // No spaces or newline.
                return false;
            }

            // Newline after the spaces (if any)
            bool anySpaces  = false;
            const lineBreak = scanLineBreak();
            allowSimpleKey_ = true;

            static bool end(Reader reader_) @safe pure nothrow @nogc
            {
                return ("---"d == reader_.prefix(3) || "..."d == reader_.prefix(3))
                        && " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(3));
            }

            if(end(reader_)) { return false; }

            bool extraBreaks = false;

            alias Transaction = SliceBuilder.Transaction;
            auto transaction = Transaction(reader_.sliceBuilder);
            if(lineBreak != '\n') { reader_.sliceBuilder.write(lineBreak); }
            while(" \n\r\u0085\u2028\u2029"d.canFind(reader_.peek()))
            {
                if(reader_.peek() == ' ') { reader_.forward(); }
                else
                {
                    const lBreak = scanLineBreak();
                    extraBreaks  = true;
                    reader_.sliceBuilder.write(lBreak);
                    if(end(reader_))
                    {
                        return false;
                    }
                }
            }
            transaction.commit();

            // No line breaks, only a space.
            if(lineBreak == '\n' && !extraBreaks) { reader_.sliceBuilder.write(' '); }

            // We've written some spaces into the slice if:
            // (lineBreak != '\n' || extraBreaks || lineBreak == '\n' && !extraBreaks).
            // That simplifies to (lineBreak != '\n' || lineBreak == '\n') which
            // simplifies to (true)
            return true;
        }

        /// Scan handle of a tag token.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        void scanTagHandleToSlice(string name)(const Mark startMark)
            @system pure nothrow @nogc
        {
            dchar c = reader_.peek();
            enum contextMsg = "While scanning a " ~ name;
            if(c != '!')
            {
                setError(contextMsg, startMark,
                         buildMsg("expected a '!', but found: ", c), reader_.mark);
                return;
            }

            uint length = 1;
            c = reader_.peek(length);
            if(c != ' ')
            {
                while(c.isAlphaNum || "-_"d.canFind(c))
                {
                    ++length;
                    c = reader_.peek(length);
                }
                if(c != '!')
                {
                    reader_.forward(length);
                    setError(contextMsg, startMark,
                             buildMsg("expected a '!', but found: ", c), reader_.mark);
                    return;
                }
                ++length;
            }

            reader_.sliceBuilder.write(reader_.get(length));
        }

        /// Scan URI in a tag token.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        void scanTagURIToSlice(string name)(const Mark startMark) @trusted pure nothrow
        {
            // Note: we do not check if URI is well-formed.
            dchar c = reader_.peek();
            bool anyChars = false;
            {
                uint length = 0;
                while(c.isAlphaNum || "-;/?:@&=+$,_.!~*\'()[]%"d.canFind(c))
                {
                    if(c == '%')
                    {
                        auto chars = reader_.get(length);
                        reader_.sliceBuilder.write(chars);
                        anyChars = anyChars || (length > 0);
                        length = 0;
                        anyChars = scanURIEscapesToSlice!name(startMark) || anyChars;
                        if(error_) { return; }
                    }
                    else { ++length; }
                    c = reader_.peek(length);
                }
                if(length > 0)
                {
                    auto chars = reader_.get(length);
                    reader_.sliceBuilder.write(chars);
                    anyChars = true;
                    length = 0;
                }
            }
            if(anyChars) { return; }

            enum contextMsg = "While parsing a " ~ name;
            setError(contextMsg, startMark, buildMsg("expected URI, but found: ", c),
                     reader_.mark);
        }

        // Not @nogc yet because std.utf.decode is not @nogc
        /// Scan URI escape sequences.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        ///
        /// Returns: true if any escapes were scanned, false otherwise.
        ///
        /// In case of an error, error_ is set. Use throwIfError() to handle this.
        bool scanURIEscapesToSlice(string name)(const Mark startMark)
            @system pure nothrow // @nogc
        {
            // URI escapes encode a UTF-8 string. We store UTF-8 code units here for
            // decoding into UTF-32.
            char[4] bytes;
            size_t bytesUsed;
            Mark mark = reader_.mark;
            // True if any characters were written to the slice.
            bool anyChars;

            // Get one dchar by decoding data from bytes.
            //
            // This is probably slow, but simple and URI escapes are extremely uncommon
            // in YAML.
            static size_t getDchar(char[] bytes, Reader reader_, ref bool anyChars)
            {
                import std.utf;
                size_t nextChar;
                const c = std.utf.decode(bytes[], nextChar);
                reader_.sliceBuilder.write(c);
                anyChars = true;
                if(bytes.length - nextChar > 0)
                {
                    core.stdc.string.memmove(bytes.ptr, bytes.ptr + nextChar,
                                             bytes.length - nextChar);
                }
                return bytes.length - nextChar;
            }

            enum contextMsg = "While scanning a " ~ name;
            try
            {
                while(reader_.peek() == '%')
                {
                    reader_.forward();
                    if(bytesUsed == bytes.length)
                    {
                        bytesUsed = getDchar(bytes[], reader_, anyChars);
                    }

                    char b = 0;
                    uint mult = 16;
                    // Converting 2 hexadecimal digits to a byte.
                    foreach(k; 0 .. 2)
                    {
                        const dchar c = reader_.peek(k);
                        if(!c.isHexDigit)
                        {
                            auto msg = buildMsg("expected URI escape sequence of 2 "
                                                "hexadecimal numbers, but found: ", c);
                            setError(contextMsg, startMark, msg, reader_.mark);
                            return false;
                        }

                        uint digit;
                        if(c - '0' < 10)     { digit = c - '0'; }
                        else if(c - 'A' < 6) { digit = c - 'A'; }
                        else if(c - 'a' < 6) { digit = c - 'a'; }
                        else                 { assert(false); }
                        b += mult * digit;
                        mult /= 16;
                    }
                    bytes[bytesUsed++] = b;

                    reader_.forward(2);
                }

                bytesUsed = getDchar(bytes[0 .. bytesUsed], reader_, anyChars);
            }
            catch(UTFException e)
            {
                setError(contextMsg, startMark, e.msg, mark);
                return false;
            }
            catch(Exception e)
            {
                assert(false, "Unexpected exception in scanURIEscapesToSlice");
            }

            return anyChars;
        }


        /// Scan a line break, if any.
        ///
        /// Transforms:
        ///   '\r\n'      :   '\n'
        ///   '\r'        :   '\n'
        ///   '\n'        :   '\n'
        ///   '\u0085'    :   '\n'
        ///   '\u2028'    :   '\u2028'
        ///   '\u2029     :   '\u2029'
        ///   no break    :   '\0'
        dchar scanLineBreak() @safe pure nothrow @nogc
        {
            const c = reader_.peek();

            if(c == '\n' || c == '\r' || c == '\u0085')
            {
                if(reader_.prefix(2) == "\r\n"d) { reader_.forward(2); }
                else { reader_.forward(); }
                return '\n';
            }
            if(c == '\u2028' || c == '\u2029')
            {
                reader_.forward();
                return c;
            }
            return '\0';
        }
}

private:

/// A nothrow function that converts a dchar[] to a string.
string utf32To8(C)(C[] str) @safe pure nothrow
    if(is(Unqual!C == dchar))
{
    try                    { return str.to!string; }
    catch(ConvException e) { assert(false, "Unexpected invalid UTF-32 string"); }
    catch(Exception e)     { assert(false, "Unexpected exception during UTF-8 encoding"); }
}

