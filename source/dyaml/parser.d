
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML parser.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dyaml.parser;


import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.typecons;

import dyaml.event;
import dyaml.exception;
import dyaml.scanner;
import dyaml.style;
import dyaml.token;
import dyaml.tagdirective;


package:
/**
 * The following YAML grammar is LL(1) and is parsed by a recursive descent
 * parser.
 *
 * stream            ::= STREAM-START implicit_document? explicit_document* STREAM-END
 * implicit_document ::= block_node DOCUMENT-END*
 * explicit_document ::= DIRECTIVE* DOCUMENT-START block_node? DOCUMENT-END*
 * block_node_or_indentless_sequence ::=
 *                       ALIAS
 *                       | properties (block_content | indentless_block_sequence)?
 *                       | block_content
 *                       | indentless_block_sequence
 * block_node        ::= ALIAS
 *                       | properties block_content?
 *                       | block_content
 * flow_node         ::= ALIAS
 *                       | properties flow_content?
 *                       | flow_content
 * properties        ::= TAG ANCHOR? | ANCHOR TAG?
 * block_content     ::= block_collection | flow_collection | SCALAR
 * flow_content      ::= flow_collection | SCALAR
 * block_collection  ::= block_sequence | block_mapping
 * flow_collection   ::= flow_sequence | flow_mapping
 * block_sequence    ::= BLOCK-SEQUENCE-START (BLOCK-ENTRY block_node?)* BLOCK-END
 * indentless_sequence   ::= (BLOCK-ENTRY block_node?)+
 * block_mapping     ::= BLOCK-MAPPING_START
 *                       ((KEY block_node_or_indentless_sequence?)?
 *                       (VALUE block_node_or_indentless_sequence?)?)*
 *                       BLOCK-END
 * flow_sequence     ::= FLOW-SEQUENCE-START
 *                       (flow_sequence_entry FLOW-ENTRY)*
 *                       flow_sequence_entry?
 *                       FLOW-SEQUENCE-END
 * flow_sequence_entry   ::= flow_node | KEY flow_node? (VALUE flow_node?)?
 * flow_mapping      ::= FLOW-MAPPING-START
 *                       (flow_mapping_entry FLOW-ENTRY)*
 *                       flow_mapping_entry?
 *                       FLOW-MAPPING-END
 * flow_mapping_entry    ::= flow_node | KEY flow_node? (VALUE flow_node?)?
 *
 * FIRST sets:
 *
 * stream: { STREAM-START }
 * explicit_document: { DIRECTIVE DOCUMENT-START }
 * implicit_document: FIRST(block_node)
 * block_node: { ALIAS TAG ANCHOR SCALAR BLOCK-SEQUENCE-START BLOCK-MAPPING-START FLOW-SEQUENCE-START FLOW-MAPPING-START }
 * flow_node: { ALIAS ANCHOR TAG SCALAR FLOW-SEQUENCE-START FLOW-MAPPING-START }
 * block_content: { BLOCK-SEQUENCE-START BLOCK-MAPPING-START FLOW-SEQUENCE-START FLOW-MAPPING-START SCALAR }
 * flow_content: { FLOW-SEQUENCE-START FLOW-MAPPING-START SCALAR }
 * block_collection: { BLOCK-SEQUENCE-START BLOCK-MAPPING-START }
 * flow_collection: { FLOW-SEQUENCE-START FLOW-MAPPING-START }
 * block_sequence: { BLOCK-SEQUENCE-START }
 * block_mapping: { BLOCK-MAPPING-START }
 * block_node_or_indentless_sequence: { ALIAS ANCHOR TAG SCALAR BLOCK-SEQUENCE-START BLOCK-MAPPING-START FLOW-SEQUENCE-START FLOW-MAPPING-START BLOCK-ENTRY }
 * indentless_sequence: { ENTRY }
 * flow_collection: { FLOW-SEQUENCE-START FLOW-MAPPING-START }
 * flow_sequence: { FLOW-SEQUENCE-START }
 * flow_mapping: { FLOW-MAPPING-START }
 * flow_sequence_entry: { ALIAS ANCHOR TAG SCALAR FLOW-SEQUENCE-START FLOW-MAPPING-START KEY }
 * flow_mapping_entry: { ALIAS ANCHOR TAG SCALAR FLOW-SEQUENCE-START FLOW-MAPPING-START KEY }
 */


/**
 * Marked exception thrown at parser errors.
 *
 * See_Also: MarkedYAMLException
 */
class ParserException : MarkedYAMLException
{
    mixin MarkedExceptionCtors;
}

/// Generates events from tokens provided by a Scanner.
///
/// While Parser receives tokens with non-const character slices, the events it
/// produces are immutable strings, which are usually the same slices, cast to string.
/// Parser is the last layer of D:YAML that may possibly do any modifications to these
/// slices.
final class Parser
{
    private:
        ///Default tag handle shortcuts and replacements.
        static TagDirective[] defaultTagDirectives_ =
            [TagDirective("!", "!"), TagDirective("!!", "tag:yaml.org,2002:")];

        ///Scanner providing YAML tokens.
        Scanner scanner_;

        ///Event produced by the most recent state.
        Event currentEvent_;

        ///YAML version string.
        string YAMLVersion_ = null;
        ///Tag handle shortcuts and replacements.
        TagDirective[] tagDirectives_;

        ///Stack of states.
        Appender!(Event delegate() @safe[]) states_;
        ///Stack of marks used to keep track of extents of e.g. YAML collections.
        Appender!(Mark[]) marks_;

        ///Current state.
        Event delegate() @safe state_;

    public:
        ///Construct a Parser using specified Scanner.
        this(Scanner scanner) @safe
        {
            state_ = &parseStreamStart;
            scanner_ = scanner;
            states_.reserve(32);
            marks_.reserve(32);
        }

        /**
         * Check if any events are left. May have side effects in some cases.
         */
        bool empty() @safe
        {
            ensureState();
            return currentEvent_.isNull;
        }

        /**
         * Return the current event.
         *
         * Must not be called if there are no events left.
         */
        Event front() @safe
        {
            ensureState();
            assert(!currentEvent_.isNull, "No event left to peek");
            return currentEvent_;
        }

        /**
         * Skip to the next event.
         *
         * Must not be called if there are no events left.
         */
        void popFront() @safe
        {
            currentEvent_.id = EventID.Invalid;
            ensureState();
        }

    private:
        /// If current event is invalid, load the next valid one if possible.
        void ensureState() @safe
        {
            if(currentEvent_.isNull && state_ !is null)
            {
                currentEvent_ = state_();
            }
        }
        ///Pop and return the newest state in states_.
        Event delegate() @safe popState() @safe
        {
            enforce(states_.data.length > 0,
                    new YAMLException("Parser: Need to pop state but no states left to pop"));
            const result = states_.data.back;
            states_.shrinkTo(states_.data.length - 1);
            return result;
        }

        ///Pop and return the newest mark in marks_.
        Mark popMark() @safe
        {
            enforce(marks_.data.length > 0,
                    new YAMLException("Parser: Need to pop mark but no marks left to pop"));
            const result = marks_.data.back;
            marks_.shrinkTo(marks_.data.length - 1);
            return result;
        }

        /// Push a state on the stack
        void pushState(Event delegate() @safe state) @safe
        {
            states_ ~= state;
        }
        /// Push a mark on the stack
        void pushMark(Mark mark) @safe
        {
            marks_ ~= mark;
        }

        /**
         * stream    ::= STREAM-START implicit_document? explicit_document* STREAM-END
         * implicit_document ::= block_node DOCUMENT-END*
         * explicit_document ::= DIRECTIVE* DOCUMENT-START block_node? DOCUMENT-END*
         */

        ///Parse stream start.
        Event parseStreamStart() @safe
        {
            const token = scanner_.getToken();
            state_ = &parseImplicitDocumentStart;
            return streamStartEvent(token.startMark, token.endMark);
        }

        /// Parse implicit document start, unless explicit detected: if so, parse explicit.
        Event parseImplicitDocumentStart() @safe
        {
            // Parse an implicit document.
            if(!scanner_.checkToken(TokenID.Directive, TokenID.DocumentStart,
                                    TokenID.StreamEnd))
            {
                tagDirectives_  = defaultTagDirectives_;
                const token = scanner_.peekToken();

                pushState(&parseDocumentEnd);
                state_ = &parseBlockNode;

                return documentStartEvent(token.startMark, token.endMark, false, null, null);
            }
            return parseDocumentStart();
        }

        ///Parse explicit document start.
        Event parseDocumentStart() @trusted
        {
            //Parse any extra document end indicators.
            while(scanner_.checkToken(TokenID.DocumentEnd)){scanner_.getToken();}

            //Parse an explicit document.
            if(!scanner_.checkToken(TokenID.StreamEnd))
            {
                const startMark = scanner_.peekToken().startMark;

                auto tagDirectives = processDirectives();
                enforce(scanner_.checkToken(TokenID.DocumentStart),
                        new ParserException("Expected document start but found " ~
                                  scanner_.peekToken().idString,
                                  scanner_.peekToken().startMark));

                const endMark = scanner_.getToken().endMark;
                pushState(&parseDocumentEnd);
                state_ = &parseDocumentContent;
                return documentStartEvent(startMark, endMark, true, YAMLVersion_, tagDirectives);
            }
            else
            {
                //Parse the end of the stream.
                const token = scanner_.getToken();
                assert(states_.data.length == 0);
                assert(marks_.data.length == 0);
                state_ = null;
                return streamEndEvent(token.startMark, token.endMark);
            }
        }

        ///Parse document end (explicit or implicit).
        Event parseDocumentEnd() @safe
        {
            Mark startMark = scanner_.peekToken().startMark;
            const bool explicit = scanner_.checkToken(TokenID.DocumentEnd);
            Mark endMark = explicit ? scanner_.getToken().endMark : startMark;

            state_ = &parseDocumentStart;

            return documentEndEvent(startMark, endMark, explicit);
        }

        ///Parse document content.
        Event parseDocumentContent() @safe
        {
            if(scanner_.checkToken(TokenID.Directive,   TokenID.DocumentStart,
                                   TokenID.DocumentEnd, TokenID.StreamEnd))
            {
                state_ = popState();
                return processEmptyScalar(scanner_.peekToken().startMark);
            }
            return parseBlockNode();
        }

        /// Process directives at the beginning of a document.
        TagDirective[] processDirectives() @safe
        {
            // Destroy version and tag handles from previous document.
            YAMLVersion_ = null;
            tagDirectives_.length = 0;

            // Process directives.
            while(scanner_.checkToken(TokenID.Directive))
            {
                const token = scanner_.getToken();
                string value = token.value.idup;
                if(token.directive == DirectiveType.YAML)
                {
                    enforce(YAMLVersion_ is null,
                            new ParserException("Duplicate YAML directive", token.startMark));
                    const minor = value.split(".")[0];
                    enforce(minor == "1",
                            new ParserException("Incompatible document (version 1.x is required)",
                                      token.startMark));
                    YAMLVersion_ = value;
                }
                else if(token.directive == DirectiveType.TAG)
                {
                    auto handle = value[0 .. token.valueDivider];

                    foreach(ref pair; tagDirectives_)
                    {
                        // handle
                        const h = pair.handle;
                        enforce(h != handle, new ParserException("Duplicate tag handle: " ~ handle,
                                                       token.startMark));
                    }
                    tagDirectives_ ~=
                        TagDirective(handle, value[token.valueDivider .. $]);
                }
                // Any other directive type is ignored (only YAML and TAG are in YAML
                // 1.1/1.2, any other directives are "reserved")
            }

            TagDirective[] value = tagDirectives_;

            //Add any default tag handles that haven't been overridden.
            foreach(ref defaultPair; defaultTagDirectives_)
            {
                bool found;
                foreach(ref pair; tagDirectives_) if(defaultPair.handle == pair.handle)
                {
                    found = true;
                    break;
                }
                if(!found) {tagDirectives_ ~= defaultPair; }
            }

            return value;
        }

        /**
         * block_node_or_indentless_sequence ::= ALIAS
         *               | properties (block_content | indentless_block_sequence)?
         *               | block_content
         *               | indentless_block_sequence
         * block_node    ::= ALIAS
         *                   | properties block_content?
         *                   | block_content
         * flow_node     ::= ALIAS
         *                   | properties flow_content?
         *                   | flow_content
         * properties    ::= TAG ANCHOR? | ANCHOR TAG?
         * block_content     ::= block_collection | flow_collection | SCALAR
         * flow_content      ::= flow_collection | SCALAR
         * block_collection  ::= block_sequence | block_mapping
         * flow_collection   ::= flow_sequence | flow_mapping
         */

        ///Parse a node.
        Event parseNode(const Flag!"block" block,
                        const Flag!"indentlessSequence" indentlessSequence = No.indentlessSequence)
            @trusted
        {
            if(scanner_.checkToken(TokenID.Alias))
            {
                const token = scanner_.getToken();
                state_ = popState();
                return aliasEvent(token.startMark, token.endMark,
                                  cast(string)token.value);
            }

            string anchor;
            string tag;
            Mark startMark, endMark, tagMark;
            bool invalidMarks = true;
            // The index in the tag string where tag handle ends and tag suffix starts.
            uint tagHandleEnd;

            //Get anchor/tag if detected. Return false otherwise.
            bool get(const TokenID id, const Flag!"first" first, ref string target) @safe
            {
                if(!scanner_.checkToken(id)){return false;}
                invalidMarks = false;
                const token = scanner_.getToken();
                if(first){startMark = token.startMark;}
                if(id == TokenID.Tag)
                {
                    tagMark = token.startMark;
                    tagHandleEnd = token.valueDivider;
                }
                endMark = token.endMark;
                target  = token.value.idup;
                return true;
            }

            //Anchor and/or tag can be in any order.
            if(get(TokenID.Anchor, Yes.first, anchor)){get(TokenID.Tag, No.first, tag);}
            else if(get(TokenID.Tag, Yes.first, tag)) {get(TokenID.Anchor, No.first, anchor);}

            if(tag !is null){tag = processTag(tag, tagHandleEnd, startMark, tagMark);}

            if(invalidMarks)
            {
                startMark = endMark = scanner_.peekToken().startMark;
            }

            bool implicit = (tag is null || tag == "!");

            if(indentlessSequence && scanner_.checkToken(TokenID.BlockEntry))
            {
                state_ = &parseIndentlessSequenceEntry;
                return sequenceStartEvent
                    (startMark, scanner_.peekToken().endMark, anchor,
                     tag, implicit, CollectionStyle.Block);
            }

            if(scanner_.checkToken(TokenID.Scalar))
            {
                auto token = scanner_.getToken();
                auto value = token.style == ScalarStyle.DoubleQuoted
                           ? handleDoubleQuotedScalarEscapes(token.value)
                           : cast(string)token.value;

                implicit = (token.style == ScalarStyle.Plain && tag is null) || tag == "!";
                state_ = popState();
                return scalarEvent(startMark, token.endMark, anchor, tag,
                                   implicit, value, token.style);
            }

            if(scanner_.checkToken(TokenID.FlowSequenceStart))
            {
                endMark = scanner_.peekToken().endMark;
                state_ = &parseFlowSequenceEntry!(Yes.first);
                return sequenceStartEvent(startMark, endMark, anchor, tag,
                                          implicit, CollectionStyle.Flow);
            }

            if(scanner_.checkToken(TokenID.FlowMappingStart))
            {
                endMark = scanner_.peekToken().endMark;
                state_ = &parseFlowMappingKey!(Yes.first);
                return mappingStartEvent(startMark, endMark, anchor, tag,
                                         implicit, CollectionStyle.Flow);
            }

            if(block && scanner_.checkToken(TokenID.BlockSequenceStart))
            {
                endMark = scanner_.peekToken().endMark;
                state_ = &parseBlockSequenceEntry!(Yes.first);
                return sequenceStartEvent(startMark, endMark, anchor, tag,
                                          implicit, CollectionStyle.Block);
            }

            if(block && scanner_.checkToken(TokenID.BlockMappingStart))
            {
                endMark = scanner_.peekToken().endMark;
                state_ = &parseBlockMappingKey!(Yes.first);
                return mappingStartEvent(startMark, endMark, anchor, tag,
                                         implicit, CollectionStyle.Block);
            }

            if(anchor !is null || tag !is null)
            {
                state_ = popState();

                //PyYAML uses a tuple(implicit, false) for the second last arg here,
                //but the second bool is never used after that - so we don't use it.

                //Empty scalars are allowed even if a tag or an anchor is specified.
                return scalarEvent(startMark, endMark, anchor, tag,
                                   implicit , "");
            }

            const token = scanner_.peekToken();
            throw new ParserException("While parsing a " ~ (block ? "block" : "flow") ~ " node",
                            startMark, "expected node content, but found: "
                            ~ token.idString, token.startMark);
        }

        /// Handle escape sequences in a double quoted scalar.
        ///
        /// Moved here from scanner as it can't always be done in-place with slices.
        string handleDoubleQuotedScalarEscapes(char[] tokenValue) const @safe
        {
            string notInPlace;
            bool inEscape;
            auto appender = appender!(string)();
            for(char[] oldValue = tokenValue; !oldValue.empty();)
            {
                const dchar c = oldValue.front();
                oldValue.popFront();

                if(!inEscape)
                {
                    if(c != '\\')
                    {
                        if(notInPlace is null) { appender.put(c); }
                        else                   { notInPlace ~= c; }
                        continue;
                    }
                    // Escape sequence starts with a '\'
                    inEscape = true;
                    continue;
                }

                import dyaml.escapes;
                scope(exit) { inEscape = false; }

                // 'Normal' escape sequence.
                if(dyaml.escapes.escapes.canFind(c))
                {
                    if(notInPlace is null)
                    {
                        // \L and \C can't be handled in place as the expand into
                        // many-byte unicode chars
                        if(c != 'L' && c != 'P')
                        {
                            appender.put(dyaml.escapes.fromEscape(c));
                            continue;
                        }
                        // Need to duplicate as we won't fit into
                        // token.value - which is what appender uses
                        notInPlace = appender.data.dup;
                        notInPlace ~= dyaml.escapes.fromEscape(c);
                        continue;
                    }
                    notInPlace ~= dyaml.escapes.fromEscape(c);
                    continue;
                }

                // Unicode char written in hexadecimal in an escape sequence.
                if(dyaml.escapes.escapeHexCodeList.canFind(c))
                {
                    // Scanner has already checked that the hex string is valid.

                    const hexLength = dyaml.escapes.escapeHexLength(c);
                    // Any hex digits are 1-byte so this works.
                    char[] hex = oldValue[0 .. hexLength];
                    oldValue = oldValue[hexLength .. $];
                    import std.ascii : isHexDigit;
                    assert(!hex.canFind!(d => !d.isHexDigit),
                            "Scanner must ensure the hex string is valid");

                    const decoded = cast(dchar)parse!int(hex, 16u);
                    if(notInPlace is null) { appender.put(decoded); }
                    else                   { notInPlace ~= decoded; }
                    continue;
                }

                assert(false, "Scanner must handle unsupported escapes");
            }

            return notInPlace is null ? appender.data : notInPlace;
        }

        /**
         * Process a tag string retrieved from a tag token.
         *
         * Params:  tag       = Tag before processing.
         *          handleEnd = Index in tag where tag handle ends and tag suffix
         *                      starts.
         *          startMark = Position of the node the tag belongs to.
         *          tagMark   = Position of the tag.
         */
        string processTag(const string tag, const uint handleEnd,
                          const Mark startMark, const Mark tagMark)
            const @safe
        {
            const handle = tag[0 .. handleEnd];
            const suffix = tag[handleEnd .. $];

            if(handle.length > 0)
            {
                string replacement;
                foreach(ref pair; tagDirectives_)
                {
                    if(pair.handle == handle)
                    {
                        replacement = pair.prefix;
                        break;
                    }
                }
                //handle must be in tagDirectives_
                enforce(replacement !is null,
                        new ParserException("While parsing a node", startMark,
                                  "found undefined tag handle: " ~ handle, tagMark));
                return replacement ~ suffix;
            }
            return suffix;
        }

        ///Wrappers to parse nodes.
        Event parseBlockNode() @safe {return parseNode(Yes.block);}
        Event parseFlowNode() @safe {return parseNode(No.block);}
        Event parseBlockNodeOrIndentlessSequence() @safe {return parseNode(Yes.block, Yes.indentlessSequence);}

        ///block_sequence ::= BLOCK-SEQUENCE-START (BLOCK-ENTRY block_node?)* BLOCK-END

        ///Parse an entry of a block sequence. If first is true, this is the first entry.
        Event parseBlockSequenceEntry(Flag!"first" first)() @safe
        {
            static if(first){pushMark(scanner_.getToken().startMark);}

            if(scanner_.checkToken(TokenID.BlockEntry))
            {
                const token = scanner_.getToken();
                if(!scanner_.checkToken(TokenID.BlockEntry, TokenID.BlockEnd))
                {
                    pushState(&parseBlockSequenceEntry!(No.first));
                    return parseBlockNode();
                }

                state_ = &parseBlockSequenceEntry!(No.first);
                return processEmptyScalar(token.endMark);
            }

            if(!scanner_.checkToken(TokenID.BlockEnd))
            {
                const token = scanner_.peekToken();
                throw new ParserException("While parsing a block collection", marks_.data.back,
                                "expected block end, but found " ~ token.idString,
                                token.startMark);
            }

            state_ = popState();
            popMark();
            const token = scanner_.getToken();
            return sequenceEndEvent(token.startMark, token.endMark);
        }

        ///indentless_sequence ::= (BLOCK-ENTRY block_node?)+

        ///Parse an entry of an indentless sequence.
        Event parseIndentlessSequenceEntry() @safe
        {
            if(scanner_.checkToken(TokenID.BlockEntry))
            {
                const token = scanner_.getToken();

                if(!scanner_.checkToken(TokenID.BlockEntry, TokenID.Key,
                                        TokenID.Value, TokenID.BlockEnd))
                {
                    pushState(&parseIndentlessSequenceEntry);
                    return parseBlockNode();
                }

                state_ = &parseIndentlessSequenceEntry;
                return processEmptyScalar(token.endMark);
            }

            state_ = popState();
            const token = scanner_.peekToken();
            return sequenceEndEvent(token.startMark, token.endMark);
        }

        /**
         * block_mapping     ::= BLOCK-MAPPING_START
         *                       ((KEY block_node_or_indentless_sequence?)?
         *                       (VALUE block_node_or_indentless_sequence?)?)*
         *                       BLOCK-END
         */

        ///Parse a key in a block mapping. If first is true, this is the first key.
        Event parseBlockMappingKey(Flag!"first" first)() @safe
        {
            static if(first){pushMark(scanner_.getToken().startMark);}

            if(scanner_.checkToken(TokenID.Key))
            {
                const token = scanner_.getToken();

                if(!scanner_.checkToken(TokenID.Key, TokenID.Value, TokenID.BlockEnd))
                {
                    pushState(&parseBlockMappingValue);
                    return parseBlockNodeOrIndentlessSequence();
                }

                state_ = &parseBlockMappingValue;
                return processEmptyScalar(token.endMark);
            }

            if(!scanner_.checkToken(TokenID.BlockEnd))
            {
                const token = scanner_.peekToken();
                throw new ParserException("While parsing a block mapping", marks_.data.back,
                                "expected block end, but found: " ~ token.idString,
                                token.startMark);
            }

            state_ = popState();
            popMark();
            const token = scanner_.getToken();
            return mappingEndEvent(token.startMark, token.endMark);
        }

        ///Parse a value in a block mapping.
        Event parseBlockMappingValue() @safe
        {
            if(scanner_.checkToken(TokenID.Value))
            {
                const token = scanner_.getToken();

                if(!scanner_.checkToken(TokenID.Key, TokenID.Value, TokenID.BlockEnd))
                {
                    pushState(&parseBlockMappingKey!(No.first));
                    return parseBlockNodeOrIndentlessSequence();
                }

                state_ = &parseBlockMappingKey!(No.first);
                return processEmptyScalar(token.endMark);
            }

            state_= &parseBlockMappingKey!(No.first);
            return processEmptyScalar(scanner_.peekToken().startMark);
        }

        /**
         * flow_sequence     ::= FLOW-SEQUENCE-START
         *                       (flow_sequence_entry FLOW-ENTRY)*
         *                       flow_sequence_entry?
         *                       FLOW-SEQUENCE-END
         * flow_sequence_entry   ::= flow_node | KEY flow_node? (VALUE flow_node?)?
         *
         * Note that while production rules for both flow_sequence_entry and
         * flow_mapping_entry are equal, their interpretations are different.
         * For `flow_sequence_entry`, the part `KEY flow_node? (VALUE flow_node?)?`
         * generate an inline mapping (set syntax).
         */

        ///Parse an entry in a flow sequence. If first is true, this is the first entry.
        Event parseFlowSequenceEntry(Flag!"first" first)() @safe
        {
            static if(first){pushMark(scanner_.getToken().startMark);}

            if(!scanner_.checkToken(TokenID.FlowSequenceEnd))
            {
                static if(!first)
                {
                    if(scanner_.checkToken(TokenID.FlowEntry))
                    {
                        scanner_.getToken();
                    }
                    else
                    {
                        const token = scanner_.peekToken();
                        throw new ParserException("While parsing a flow sequence", marks_.data.back,
                                        "expected ',' or ']', but got: " ~
                                        token.idString, token.startMark);
                    }
                }

                if(scanner_.checkToken(TokenID.Key))
                {
                    const token = scanner_.peekToken();
                    state_ = &parseFlowSequenceEntryMappingKey;
                    return mappingStartEvent(token.startMark, token.endMark,
                                             null, null, true, CollectionStyle.Flow);
                }
                else if(!scanner_.checkToken(TokenID.FlowSequenceEnd))
                {
                    pushState(&parseFlowSequenceEntry!(No.first));
                    return parseFlowNode();
                }
            }

            const token = scanner_.getToken();
            state_ = popState();
            popMark();
            return sequenceEndEvent(token.startMark, token.endMark);
        }

        ///Parse a key in flow context.
        Event parseFlowKey(in Event delegate() @safe nextState) @safe
        {
            const token = scanner_.getToken();

            if(!scanner_.checkToken(TokenID.Value, TokenID.FlowEntry,
                                    TokenID.FlowSequenceEnd))
            {
                pushState(nextState);
                return parseFlowNode();
            }

            state_ = nextState;
            return processEmptyScalar(token.endMark);
        }

        ///Parse a mapping key in an entry in a flow sequence.
        Event parseFlowSequenceEntryMappingKey() @safe
        {
            return parseFlowKey(&parseFlowSequenceEntryMappingValue);
        }

        ///Parse a mapping value in a flow context.
        Event parseFlowValue(TokenID checkId, in Event delegate() @safe nextState)
            @safe
        {
            if(scanner_.checkToken(TokenID.Value))
            {
                const token = scanner_.getToken();
                if(!scanner_.checkToken(TokenID.FlowEntry, checkId))
                {
                    pushState(nextState);
                    return parseFlowNode();
                }

                state_ = nextState;
                return processEmptyScalar(token.endMark);
            }

            state_ = nextState;
            return processEmptyScalar(scanner_.peekToken().startMark);
        }

        ///Parse a mapping value in an entry in a flow sequence.
        Event parseFlowSequenceEntryMappingValue() @safe
        {
            return parseFlowValue(TokenID.FlowSequenceEnd,
                                  &parseFlowSequenceEntryMappingEnd);
        }

        ///Parse end of a mapping in a flow sequence entry.
        Event parseFlowSequenceEntryMappingEnd() @safe
        {
            state_ = &parseFlowSequenceEntry!(No.first);
            const token = scanner_.peekToken();
            return mappingEndEvent(token.startMark, token.startMark);
        }

        /**
         * flow_mapping  ::= FLOW-MAPPING-START
         *                   (flow_mapping_entry FLOW-ENTRY)*
         *                   flow_mapping_entry?
         *                   FLOW-MAPPING-END
         * flow_mapping_entry    ::= flow_node | KEY flow_node? (VALUE flow_node?)?
         */

        ///Parse a key in a flow mapping.
        Event parseFlowMappingKey(Flag!"first" first)() @safe
        {
            static if(first){pushMark(scanner_.getToken().startMark);}

            if(!scanner_.checkToken(TokenID.FlowMappingEnd))
            {
                static if(!first)
                {
                    if(scanner_.checkToken(TokenID.FlowEntry))
                    {
                        scanner_.getToken();
                    }
                    else
                    {
                        const token = scanner_.peekToken();
                        throw new ParserException("While parsing a flow mapping", marks_.data.back,
                                        "expected ',' or '}', but got: " ~
                                        token.idString, token.startMark);
                    }
                }

                if(scanner_.checkToken(TokenID.Key))
                {
                    return parseFlowKey(&parseFlowMappingValue);
                }

                if(!scanner_.checkToken(TokenID.FlowMappingEnd))
                {
                    pushState(&parseFlowMappingEmptyValue);
                    return parseFlowNode();
                }
            }

            const token = scanner_.getToken();
            state_ = popState();
            popMark();
            return mappingEndEvent(token.startMark, token.endMark);
        }

        ///Parse a value in a flow mapping.
        Event parseFlowMappingValue()  @safe
        {
            return parseFlowValue(TokenID.FlowMappingEnd, &parseFlowMappingKey!(No.first));
        }

        ///Parse an empty value in a flow mapping.
        Event parseFlowMappingEmptyValue() @safe
        {
            state_ = &parseFlowMappingKey!(No.first);
            return processEmptyScalar(scanner_.peekToken().startMark);
        }

        ///Return an empty scalar.
        Event processEmptyScalar(const Mark mark) @safe pure nothrow const @nogc
        {
            return scalarEvent(mark, mark, null, null, true, "");
        }
}
