
//          Copyright Ferdinand Majerech 2011.
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
import std.utf;

import dyaml.fastcharsearch;
import dyaml.escapes;
import dyaml.exception;
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

///Generates tokens from data provided by a Reader.
final class Scanner
{
    private:
        /**
         * A simple key is a key that is not denoted by the '?' indicator.
         * For example:
         *   ---
         *   block simple key: value
         *   ? not a simple key:
         *   : { flow simple key: value }
         * We emit the KEY token before all keys, so when we find a potential
         * simple key, we try to locate the corresponding ':' indicator.
         * Simple keys should be limited to a single line and 1024 characters.
         *
         * 16 bytes on 64-bit.
         */
        static struct SimpleKey
        {
            ///Character index in reader where the key starts.
            uint charIndex = uint.max;
            ///Index of the key token from start (first token scanned being 0).
            uint tokenIndex;
            ///Line the key starts at.
            uint line;
            ///Column the key starts at.
            ushort column;
            ///Is this required to be a simple key?
            bool required;
            ///Is this struct "null" (invalid)?.
            bool isNull;
        }

        ///Block chomping types.
        enum Chomping
        {
            ///Strip all trailing line breaks. '-' indicator.
            Strip,
            ///Line break of the last line is preserved, others discarded. Default.
            Clip,
            ///All trailing line breaks are preserved. '+' indicator.
            Keep
        }

        ///Reader used to read from a file/stream.
        Reader reader_;
        ///Are we done scanning?
        bool done_;

        ///Level of nesting in flow context. If 0, we're in block context.
        uint flowLevel_;
        ///Current indentation level.
        int indent_ = -1;
        ///Past indentation levels. Used as a stack.
        Array!int indents_;

        ///Processed tokens not yet emitted. Used as a queue.
        Queue!Token tokens_;

        ///Number of tokens emitted through the getToken method.
        uint tokensTaken_;

        /**
         * Can a simple key start at the current position? A simple key may
         * start:
         * - at the beginning of the line, not counting indentation spaces
         *       (in block context),
         * - after '{', '[', ',' (in the flow context),
         * - after '?', ':', '-' (in the block context).
         * In the block context, this flag also signifies if a block collection
         * may start at the current position.
         */
        bool allowSimpleKey_ = true;

        ///Possible simple keys indexed by flow levels.
        SimpleKey[] possibleSimpleKeys_;

        ///Used for constructing strings while limiting reallocation.
        Appender!(dchar[]) appender_;

    public:
        ///Construct a Scanner using specified Reader.
        this(Reader reader) @trusted
        {
            //Return the next token, but do not delete it from the queue
            reader_ = reader;
            appender_ = appender!(dchar[])();
            fetchStreamStart();
        }

        ///Destroy the scanner.
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
        ///Determine whether or not we need to fetch more tokens before peeking/getting a token.
        @property bool needMoreTokens() pure @safe
        {
            if(done_)        {return false;}
            if(tokens_.empty){return true;}

            ///The current token may be a potential simple key, so we need to look further.
            stalePossibleSimpleKeys();
            return nextPossibleSimpleKey() == tokensTaken_;
        }

        ///Fetch at token, adding it to tokens_.
        void fetchToken() @trusted
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
        uint nextPossibleSimpleKey() pure @safe nothrow
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
        void stalePossibleSimpleKeys() pure @safe
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
        void savePossibleSimpleKey() pure @system
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
        void removePossibleSimpleKey() pure @safe
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

        ///Aliases to add literal or folded block scalar.
        alias fetchBlockScalar!(ScalarStyle.Literal) fetchLiteral;
        alias fetchBlockScalar!(ScalarStyle.Folded) fetchFolded;

        ///Add quoted flow SCALAR token.
        void fetchFlowScalar(ScalarStyle quotes)() @trusted
        {
            //A flow scalar could be a simple key.
            savePossibleSimpleKey();
            //No simple keys after flow scalars.
            allowSimpleKey_ = false;

            //Scan and add SCALAR.
            tokens_.push(scanFlowScalar(quotes));
        }

        ///Aliases to add single or double quoted block scalar.
        alias fetchFlowScalar!(ScalarStyle.SingleQuoted) fetchSingle;
        alias fetchFlowScalar!(ScalarStyle.DoubleQuoted) fetchDouble;

        ///Add plain SCALAR token.
        void fetchPlain() @trusted
        {
            //A plain scalar could be a simple key
            savePossibleSimpleKey();
            //No simple keys after plain scalars. But note that scanPlain() will
            //change this flag if the scan is finished at the beginning of the line.
            allowSimpleKey_ = false;

            //Scan and add SCALAR. May change allowSimpleKey_
            tokens_.push(scanPlain());
        }


        ///Check if the next token is DIRECTIVE:        ^ '%' ...
        bool checkDirective() @safe
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
        bool checkDocumentEnd() @safe
        {
            // Check one char first, then all 3, to prevent reading outside the buffer.
            return reader_.column    == 0     &&
                   reader_.peek()    == '.'   &&
                   reader_.prefix(3) == "..." &&
                   " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(3));
        }

        ///Check if the next token is BLOCK-ENTRY:      '-' (' '|'\n')
        bool checkBlockEntry() @safe
        {
            return reader_.peek() == '-' &&
                   " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(1));
        }

        /**
         * Check if the next token is KEY(flow context):    '?'
         *
         * or KEY(block context):   '?' (' '|'\n')
         */
        bool checkKey() @safe
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
        bool checkValue() @safe
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
        bool checkPlain() @safe
        {
            const c = reader_.peek();
            return !("-?:,[]{}#&*!|>\'\"%@` \t\0\n\r\u0085\u2028\u2029"d.canFind(c)) ||
                    (!" \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(1)) &&
                     (c == '-' || (flowLevel_ == 0 && "?:"d.canFind(c))));
        }

        ///Move to the next non-space character.
        void findNextNonSpace() @safe
        {
            while(reader_.peek() == ' '){reader_.forward();}
        }

        ///Scan a string of alphanumeric or "-_" characters.
        dstring scanAlphaNumeric(string name)(const Mark startMark) @trusted
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

        ///Scan all characters until nex line break.
        dstring scanToNextBreak() @safe
        {
            uint length = 0;
            while(!"\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(length))){++length;}
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
        void scanToNextToken() @safe
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
        Token scanDirective() @trusted
        {
            Mark startMark = reader_.mark;
            //Skip the '%'.
            reader_.forward();

            const name  = scanDirectiveName(startMark);
            const value = name == "YAML" ? scanYAMLDirectiveValue(startMark):
                          name == "TAG"  ? scanTagDirectiveValue(startMark) : "";

            Mark endMark = reader_.mark;

            if(!["YAML"d, "TAG"d].canFind(name)){scanToNextBreak();}
            scanDirectiveIgnoredLine(startMark);

            //Storing directive name and value in a single string, separated by zero.
            return directiveToken(startMark, endMark, to!string(name ~ '\0' ~ value));
        }

        ///Scan name of a directive token.
        dstring scanDirectiveName(const Mark startMark) @trusted
        {
            //Scan directive name.
            const name = scanAlphaNumeric!"a directive"(startMark);

            enforce(" \0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()),
                    new Error("While scanning a directive", startMark,
                              "expected alphanumeric, - or _, but found "
                              ~ to!string(reader_.peek()), reader_.mark));
            return name;
        }

        ///Scan value of a YAML directive token. Returns major, minor version separated by '.'.
        dstring scanYAMLDirectiveValue(const Mark startMark) @trusted
        {
            findNextNonSpace();

            dstring result = scanYAMLDirectiveNumber(startMark);
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

        ///Scan a number from a YAML directive.
        dstring scanYAMLDirectiveNumber(const Mark startMark) @trusted
        {
            enforce(isDigit(reader_.peek()),
                    new Error("While scanning a directive", startMark,
                              "expected a digit, but found: " ~
                              to!string(reader_.peek()), reader_.mark));

            //Already found the first digit in the enforce(), so set length to 1.
            uint length = 1;
            while(isDigit(reader_.peek(length))){++length;}

            return reader_.get(length);
        }

        ///Scan value of a tag directive.
        dstring scanTagDirectiveValue(const Mark startMark) @safe
        {
            findNextNonSpace();
            const handle = scanTagDirectiveHandle(startMark);
            findNextNonSpace();
            return handle ~ '\0' ~ scanTagDirectivePrefix(startMark);
        }

        ///Scan handle of a tag directive.
        dstring scanTagDirectiveHandle(const Mark startMark) @trusted
        {
            const value = scanTagHandle("directive", startMark);
            enforce(reader_.peek() == ' ',
                    new Error("While scanning a directive handle", startMark,
                              "expected ' ', but found: " ~ to!string(reader_.peek()),
                              reader_.mark));
            return value;
        }

        ///Scan prefix of a tag directive.
        dstring scanTagDirectivePrefix(const Mark startMark) @trusted
        {
            const value = scanTagURI("directive", startMark);
            enforce(" \0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()),
                    new Error("While scanning a directive prefix", startMark,
                              "expected ' ', but found" ~ to!string(reader_.peek()),
                              reader_.mark));

            return value;
        }

        ///Scan (and ignore) ignored line after a directive.
        void scanDirectiveIgnoredLine(const Mark startMark) @trusted
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
        Token scanAnchor(TokenID id) @trusted
        {
            const startMark = reader_.mark;

            const dchar i = reader_.get();

            dstring value = i == '*' ? scanAlphaNumeric!("an alias")(startMark)
                                     : scanAlphaNumeric!("an anchor")(startMark);

            enforce((" \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()) ||
                     ("?:,]}%@").canFind(reader_.peek())),
                    new Error("While scanning an " ~ (i == '*') ? "alias" : "anchor",
                                         startMark, "expected alphanumeric, - or _, but found "~
                                         to!string(reader_.peek()), reader_.mark));

            if(id == TokenID.Alias)
            {
                return aliasToken(startMark, reader_.mark, to!string(value));
            }
            else if(id == TokenID.Anchor)
            {
                return anchorToken(startMark, reader_.mark, to!string(value));
            }
            assert(false, "This code should never be reached");
        }

        ///Scan a tag token.
        Token scanTag() @trusted
        {
            const startMark = reader_.mark;
            dchar c = reader_.peek(1);
            dstring handle = "";
            dstring suffix;

            if(c == '<')
            {
                reader_.forward(2);
                suffix = scanTagURI("tag", startMark);
                enforce(reader_.peek() == '>',
                        new Error("While scanning a tag", startMark,
                                  "expected '>' but found" ~ to!string(reader_.peek()),
                                  reader_.mark));
                reader_.forward();
            }
            else if(" \t\0\n\r\u0085\u2028\u2029"d.canFind(c))
            {
                suffix = "!";
                reader_.forward();
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

                if(useHandle){handle = scanTagHandle("tag", startMark);}
                else
                {
                    handle = "!";
                    reader_.forward();
                }

                suffix = scanTagURI("tag", startMark);
            }

            enforce(" \0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()),
                    new Error("While scanning a tag", startMark,
                              "expected ' ' but found" ~ to!string(reader_.peek()),
                              reader_.mark));
            return tagToken(startMark, reader_.mark, to!string(handle ~ '\0' ~ suffix));
        }

        ///Scan a block scalar token with specified style.
        Token scanBlockScalar(const ScalarStyle style) @system
        {
            const startMark = reader_.mark;

            //Scan the header.
            reader_.forward();

            const indicators = scanBlockScalarIndicators(startMark);
            const chomping   = indicators[0];
            const increment  = indicators[1];
            scanBlockScalarIgnoredLine(startMark);

            //Determine the indentation level and go to the first non-empty line.
            Mark endMark;
            dchar[] breaks;
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

            dstring lineBreak = "";

            //Using appender_, so clear it when we're done.
            scope(exit){appender_.clear();}

            //Scan the inner part of the block scalar.
            while(reader_.column == indent && reader_.peek() != '\0')
            {
                appender_.put(breaks);
                const bool leadingNonSpace = !" \t"d.canFind(reader_.peek());
                appender_.put(scanToNextBreak());
                lineBreak = ""d ~ scanLineBreak();

                auto scalarBreaks = scanBlockScalarBreaks(indent);
                breaks = scalarBreaks[0];
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

            return scalarToken(startMark, endMark, to!string(cast(dstring)appender_.data), style);
        }

        ///Scan chomping and indentation indicators of a scalar token.
        Tuple!(Chomping, int) scanBlockScalarIndicators(const Mark startMark) @trusted
        {
            auto chomping = Chomping.Clip;
            int increment = int.min;
            dchar c = reader_.peek();

            ///Get chomping indicator, if detected. Return false otherwise.
            bool getChomping()
            {
                if(!"+-"d.canFind(c)){return false;}
                chomping = c == '+' ? Chomping.Keep : Chomping.Strip;
                reader_.forward();
                c = reader_.peek();
                return true;
            }

            ///Get increment indicator, if detected. Return false otherwise.
            bool getIncrement()
            {
                if(!isDigit(c)){return false;}
                increment = to!int(""d ~ c);
                enforce(increment != 0,
                        new Error("While scanning a block scalar", startMark,
                                  "expected indentation indicator in range 1-9, but found 0",
                                  reader_.mark));
                reader_.forward();
                c = reader_.peek();
                return true;
            }

            ///Indicators can be in any order.
            if(getChomping())      {getIncrement();}
            else if(getIncrement()){getChomping();}

            enforce(" \0\n\r\u0085\u2028\u2029"d.canFind(c),
                    new Error("While scanning a block scalar", startMark,
                              "expected chomping or indentation indicator, but found "
                              ~ to!string(c), reader_.mark));

            return tuple(chomping, increment);
        }

        ///Scan (and ignore) ignored line in a block scalar.
        void scanBlockScalarIgnoredLine(const Mark startMark) @trusted
        {
            findNextNonSpace();
            if(reader_.peek()== '#'){scanToNextBreak();}

            enforce("\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()),
                    new Error("While scanning a block scalar", startMark,
                              "expected a comment or a line break, but found "
                              ~ to!string(reader_.peek()), reader_.mark));
            scanLineBreak();
        }

        ///Scan indentation in a block scalar, returning line breaks, max indent and end mark.
        Tuple!(dchar[], uint, Mark) scanBlockScalarIndentation() @safe
        {
            dchar[] chunks;
            uint maxIndent;
            Mark endMark = reader_.mark;

            while(" \n\r\u0085\u2028\u2029"d.canFind(reader_.peek()))
            {
                if(reader_.peek() != ' ')
                {
                    chunks ~= scanLineBreak();
                    endMark = reader_.mark;
                    continue;
                }
                reader_.forward();
                maxIndent = max(reader_.column, maxIndent);
            }

            return tuple(chunks, maxIndent, endMark);
        }

        ///Scan line breaks at lower or specified indentation in a block scalar.
        Tuple!(dchar[], Mark) scanBlockScalarBreaks(const uint indent) @safe
        {
            dchar[] chunks;
            Mark endMark = reader_.mark;

            for(;;)
            {
                while(reader_.column < indent && reader_.peek() == ' '){reader_.forward();}
                if(!"\n\r\u0085\u2028\u2029"d.canFind(reader_.peek())){break;}
                chunks ~= scanLineBreak();
                endMark = reader_.mark;
            }

            return tuple(chunks, endMark);
        }

        ///Scan a qouted flow scalar token with specified quotes.
        Token scanFlowScalar(const ScalarStyle quotes) @system
        {
            const startMark = reader_.mark;
            const quote = reader_.get();

            //Using appender_, so clear it when we're done.
            scope(exit){appender_.clear();}

            //Puts scanned data to appender_.
            scanFlowScalarNonSpaces(quotes, startMark);
            while(reader_.peek() != quote)
            {
                //Puts scanned data to appender_.
                scanFlowScalarSpaces(startMark);
                scanFlowScalarNonSpaces(quotes, startMark);
            }
            reader_.forward();

            return scalarToken(startMark, reader_.mark, to!string(cast(dstring)appender_.data), quotes);
        }

        ///Scan nonspace characters in a flow scalar.
        void scanFlowScalarNonSpaces(const ScalarStyle quotes, const Mark startMark) @system
        {
            for(;;)
            {
                dchar c = reader_.peek();
                uint length = 0;

                mixin FastCharSearch!" \t\0\n\r\u0085\u2028\u2029\'\"\\"d search;

                //This is an optimized way of writing:
                //while(!search.canFind(reader_.peek(length))){++length;}
                outer: for(;;)
                {
                    const slice = reader_.slice(length, length + 32);
                    enforce(slice.length > 0,
                            new Error("While reading a flow scalar", startMark,
                                      "reached end of file", reader_.mark));
                    foreach(ch; slice)
                    {
                        if(search.canFind(ch)){break outer;}
                        ++length;
                    }
                }

                appender_.put(reader_.prefix(length));
                reader_.forward(length);

                c = reader_.peek();
                if(quotes == ScalarStyle.SingleQuoted &&
                   c == '\'' && reader_.peek(1) == '\'')
                {
                    appender_.put('\'');
                    reader_.forward(2);
                }
                else if((quotes == ScalarStyle.DoubleQuoted && c == '\'') ||
                        (quotes == ScalarStyle.SingleQuoted && "\"\\"d.canFind(c)))
                {
                    appender_.put(c);
                    reader_.forward();
                }
                else if(quotes == ScalarStyle.DoubleQuoted && c == '\\')
                {
                    reader_.forward();
                    c = reader_.peek();
                    if((c in dyaml.escapes.fromEscapes) !is null)
                    {
                        appender_.put(dyaml.escapes.fromEscapes[c]);
                        reader_.forward();
                    }
                    else if((c in dyaml.escapes.escapeHexCodes) !is null)
                    {
                        length = dyaml.escapes.escapeHexCodes[c];
                        reader_.forward();

                        foreach(i; 0 .. length)
                        {
                            enforce(isHexDigit(reader_.peek(i)),
                                    new Error(
                                        "While scanning a double qouted scalar", startMark,
                                        "expected escape sequence of " ~ to!string(length) ~
                                        " hexadecimal numbers, but found " ~
                                        to!string(reader_.peek(i)), reader_.mark));
                        }

                        dstring hex = reader_.get(length);
                        appender_.put(cast(dchar)parse!int(hex, 16));
                    }
                    else if("\n\r\u0085\u2028\u2029"d.canFind(c))
                    {
                        scanLineBreak();
                        appender_.put(scanFlowScalarBreaks(startMark));
                    }
                    else
                    {
                        throw new Error("While scanning a double quoted scalar", startMark,
                                        "found unknown escape character: " ~ to!string(c),
                                        reader_.mark);
                    }
                }
                else
                {
                    return;
                }
            }
        }

        /// Scan space characters in a flow scalar.
        void scanFlowScalarSpaces(const Mark startMark) @system
        {
            // Increase length as long as we see whitespace.
            uint length = 0;
            while(" \t"d.canFind(reader_.peek(length))) { ++length; }
            const whitespaces = reader_.prefix(length + 1);

            const c = whitespaces[$ - 1];
            enforce(c != '\0', new Error("While scanning a quoted scalar", startMark,
                                         "found unexpected end of buffer", reader_.mark));

            if("\n\r\u0085\u2028\u2029"d.canFind(c))
            {
                reader_.forward(length);
                const lineBreak = scanLineBreak();
                const breaks = scanFlowScalarBreaks(startMark);

                if(lineBreak != '\n') { appender_.put(lineBreak); }
                else if(breaks.length == 0) { appender_.put(' '); }
                appender_.put(breaks);
            }
            else
            {
                appender_.put(whitespaces[0 .. $ - 1]);
                reader_.forward(length);
            }
        }

        /// Scan line breaks in a flow scalar.
        dstring scanFlowScalarBreaks(const Mark startMark) @system
        {
            auto appender = appender!dstring();
            for(;;)
            {
                // Instead of checking indentation, we check for document separators.
                const prefix = reader_.prefix(3);
                if((prefix == "---"d || prefix == "..."d) &&
                   " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader_.peek(3)))
                {
                    throw new Error("While scanning a quoted scalar", startMark,
                                    "found unexpected document separator", reader_.mark);
                }

                while(" \t"d.canFind(reader_.peek())) { reader_.forward(); }

                if("\n\r\u0085\u2028\u2029"d.canFind(reader_.peek()))
                {
                    appender.put(scanLineBreak());
                }
                else { return appender.data; }
            }
        }

        ///Scan plain scalar token (no block, no quotes).
        Token scanPlain() @system
        {
            //We keep track of the allowSimpleKey_ flag here.
            //Indentation rules are loosed for the flow context
            //Using appender_, so clear it when we're done.
            scope(exit){appender_.clear();}
            const startMark = reader_.mark;
            Mark endMark = startMark;
            const indent = indent_ + 1;

            //We allow zero indentation for scalars, but then we need to check for
            //document separators at the beginning of the line.
            //if(indent == 0){indent = 1;}
            dstring spaces;

            mixin FastCharSearch!" \t\0\n\r\u0085\u2028\u2029"d search;

            for(;;)
            {
                if(reader_.peek() == '#'){break;}

                uint length = 0;

                dchar c;
                for(;;)
                {
                    c = reader_.peek(length);
                    const bool done = search.canFind(c) || (flowLevel_ == 0 && c == ':' &&
                                      search.canFind(reader_.peek(length + 1))) ||
                                      (flowLevel_ > 0 && ",:?[]{}"d.canFind(c));
                    if(done){break;}
                    ++length;
                }

                //It's not clear what we should do with ':' in the flow context.
                if(flowLevel_ > 0 && c == ':' &&
                   !search.canFind(reader_.peek(length + 1)) &&
                   !",[]{}"d.canFind(reader_.peek(length + 1)))
                {
                    reader_.forward(length);
                    throw new Error("While scanning a plain scalar", startMark,
                                    "found unexpected ':' . Please check "
                                    "http://pyyaml.org/wiki/YAMLColonInFlowContext "
                                    "for details.", reader_.mark);
                }

                if(length == 0){break;}
                allowSimpleKey_ = false;

                appender_.put(spaces);
                appender_.put(reader_.get(length));

                endMark = reader_.mark;

                spaces = scanPlainSpaces(startMark);
                if(spaces.length == 0 || reader_.peek() == '#' ||
                   (flowLevel_ == 0 && reader_.column < indent))
                {
                    break;
                }
            }
            return scalarToken(startMark, endMark, to!string(cast(dstring)appender_.data), ScalarStyle.Plain);
        }

        /// Scan spaces in a plain scalar.
        dstring scanPlainSpaces(const Mark startMark) @system
        {
            // The specification is really confusing about tabs in plain scalars.
            // We just forbid them completely. Do not use tabs in YAML!
            auto appender = appender!dstring();

            uint length = 0;
            while(reader_.peek(length) == ' '){++length;}
            dstring whitespaces = reader_.get(length);

            dchar c = reader_.peek();
            if("\n\r\u0085\u2028\u2029"d.canFind(c))
            {
                const lineBreak = scanLineBreak();
                allowSimpleKey_ = true;

                static bool end(Reader reader)
                {
                    return ["---"d, "..."d].canFind(reader.prefix(3)) &&
                           " \t\0\n\r\u0085\u2028\u2029"d.canFind(reader.peek(3));
                }

                if(end(reader_)) { return ""; }

                dstring breaks;
                while(" \n\r\u0085\u2028\u2029"d.canFind(reader_.peek()))
                {
                    if(reader_.peek() == ' '){reader_.forward();}
                    else
                    {
                        breaks ~= scanLineBreak();
                        if(end(reader_)) { return ""; }
                    }
                }

                if(lineBreak != '\n') { appender.put(lineBreak); }
                else if(breaks.length == 0) { appender.put(' '); }
                appender.put(breaks);
            }
            else if(whitespaces.length > 0)
            {
                appender.put(whitespaces);
            }

            return appender.data;
        }

        ///Scan handle of a tag token.
        dstring scanTagHandle(const string name, const Mark startMark) @system
        {
            dchar c = reader_.peek();
            enforce(c == '!',
                    new Error("While scanning a " ~ name, startMark,
                              "expected a '!', but found: " ~ to!string(c), reader_.mark));

            uint length = 1;
            c = reader_.peek(length);
            if(c != ' ')
            {
                while(isAlphaNum(c) || "-_"d.canFind(c))
                {
                    ++length;
                    c = reader_.peek(length);
                }
                if(c != '!')
                {
                    reader_.forward(length);
                    throw new Error("While scanning a " ~ name, startMark,
                                    "expected a '!', but found: " ~ to!string(c),
                                    reader_.mark);
                }
                ++length;
            }
            return reader_.get(length);
        }

        ///Scan URI in a tag token.
        dstring scanTagURI(const string name, const Mark startMark) @system
        {
            //Note: we do not check if URI is well-formed.
            //Using appender_, so clear it when we're done.
            scope(exit){appender_.clear();}
            uint length = 0;

            dchar c = reader_.peek();
            while(isAlphaNum(c) || "-;/?:@&=+$,_.!~*\'()[]%"d.canFind(c))
            {
                if(c == '%')
                {
                    appender_.put(reader_.get(length));
                    length = 0;
                    appender_.put(scanURIEscapes(name, startMark));
                }
                else{++length;}
                c = reader_.peek(length);
            }
            if(length > 0)
            {
                appender_.put(reader_.get(length));
                length = 0;
            }
            enforce(appender_.data.length > 0,
                    new Error("While parsing a " ~ name, startMark,
                              "expected URI, but found: " ~ to!string(c), reader_.mark));

            return cast(dstring)appender_.data;
        }

        ///Scan URI escape sequences.
        dstring scanURIEscapes(const string name, const Mark startMark) @system
        {
            ubyte[] bytes;
            Mark mark = reader_.mark;

            while(reader_.peek() == '%')
            {
                reader_.forward();

                ubyte b = 0;
                uint mult = 16;
                //Converting 2 hexadecimal digits to a byte.
                foreach(k; 0 .. 2)
                {
                    const dchar c = reader_.peek(k);
                    enforce(isHexDigit(c),
                            new Error("While scanning a " ~ name, startMark,
                                      "expected URI escape sequence of "
                                      "2 hexadecimal numbers, but found: " ~
                                      to!string(c), reader_.mark));

                    uint digit;
                    if(c - '0' < 10){digit = c - '0';}
                    else if(c - 'A' < 6){digit = c - 'A';}
                    else if(c - 'a' < 6){digit = c - 'a';}
                    else{assert(false);}
                    b += mult * digit;
                    mult /= 16;
                }
                bytes ~= b;

                reader_.forward(2);
            }

            try{return to!dstring(cast(string)bytes);}
            catch(ConvException e)
            {
                throw new Error("While scanning a " ~ name, startMark, e.msg, mark);
            }
            catch(UTFException e)
            {
                throw new Error("While scanning a " ~ name, startMark, e.msg, mark);
            }
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
        dchar scanLineBreak() @safe
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
