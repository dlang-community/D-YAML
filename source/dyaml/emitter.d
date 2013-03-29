//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML emitter.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dyaml.emitter;


import std.algorithm;
import std.array;
import std.ascii;
import std.container;
import std.conv;
import std.exception;
import std.format;
import std.range;
import std.stream;
import std.string;
import std.system;
import std.typecons;
import std.utf;

import dyaml.anchor;
import dyaml.encoding;
import dyaml.escapes;
import dyaml.event;
import dyaml.exception;
import dyaml.fastcharsearch;
import dyaml.flags;
import dyaml.linebreak;
import dyaml.queue;
import dyaml.style;
import dyaml.tag;


package:

/**
 * Exception thrown at Emitter errors.
 *
 * See_Also:
 *     YAMLException
 */
class EmitterException : YAMLException
{
    mixin ExceptionCtors;
}

private alias EmitterException Error;

//Stores results of analysis of a scalar, determining e.g. what scalar style to use.
align(4) struct ScalarAnalysis
{
    //Scalar itself.
    string scalar;

    ///Analysis results.
    Flags!("empty", "multiline", "allowFlowPlain", "allowBlockPlain",
           "allowSingleQuoted", "allowDoubleQuoted", "allowBlock", "isNull") flags;
}

///Quickly determines if a character is a newline.
private mixin FastCharSearch!"\n\u0085\u2028\u2029"d newlineSearch_;

//Emits YAML events into a file/stream.
struct Emitter 
{
    private:
        alias dyaml.tagdirective.TagDirective TagDirective;

        ///Default tag handle shortcuts and replacements.
        static TagDirective[] defaultTagDirectives_ = 
            [TagDirective("!", "!"), TagDirective("!!", "tag:yaml.org,2002:")];

        ///Stream to write to.
        Stream stream_;
        ///Encoding can be overriden by STREAM-START.
        Encoding encoding_ = Encoding.UTF_8;

        ///Stack of states.
        Array!(void delegate()) states_;
        ///Current state.
        void delegate() state_;

        ///Event queue.
        Queue!Event events_;
        ///Event we're currently emitting.
        Event event_;

        ///Stack of previous indentation levels.
        Array!int indents_;
        ///Current indentation level.
        int indent_ = -1;

        ///Level of nesting in flow context. If 0, we're in block context.
        uint flowLevel_ = 0;

        /// Describes context (where we are in the document).
        enum Context
        {
            /// Root node of a document.
            Root,
            /// Sequence.
            Sequence,
            /// Mapping.
            MappingNoSimpleKey,
            /// Mapping, in a simple key.
            MappingSimpleKey
        }
        /// Current context.
        Context context_;

        ///Characteristics of the last emitted character:

        ///Line.
        uint line_ = 0;
        ///Column.
        uint column_ = 0;
        ///Whitespace character?
        bool whitespace_ = true;
        ///indentation space, '-', '?', or ':'?
        bool indentation_ = true;

        ///Does the document require an explicit document indicator?
        bool openEnded_;

        ///Formatting details.

        ///Canonical scalar format?
        bool canonical_;
        ///Best indentation width.
        uint bestIndent_ = 2;
        ///Best text width.
        uint bestWidth_ = 80;
        ///Best line break character/s.
        LineBreak bestLineBreak_;

        ///Tag directive handle - prefix pairs.
        TagDirective[] tagDirectives_;

        ///Anchor/alias to process.
        string preparedAnchor_ = null;
        ///Tag to process.
        string preparedTag_ = null;

        ///Analysis result of the current scalar.
        ScalarAnalysis analysis_;
        ///Style of the current scalar.
        ScalarStyle style_ = ScalarStyle.Invalid;

    public:
        @disable int opCmp(ref Emitter);
        @disable bool opEquals(ref Emitter);

        /**
         * Construct an emitter.
         *
         * Params:  stream    = Stream to write to. Must be writable.
         *          canonical = Write scalars in canonical form?
         *          indent    = Indentation width.
         *          lineBreak = Line break character/s.
         */
        this(Stream stream, const bool canonical, const int indent, const int width, 
             const LineBreak lineBreak) @trusted
        in{assert(stream.writeable, "Can't emit YAML to a non-writable stream");}
        body
        {
            states_.reserve(32);
            indents_.reserve(32);
            stream_ = stream;
            canonical_ = canonical;
            state_ = &expectStreamStart;

            if(indent > 1 && indent < 10){bestIndent_ = indent;}
            if(width > bestIndent_ * 2)  {bestWidth_ = width;}
            bestLineBreak_ = lineBreak;

            analysis_.flags.isNull = true;
        }

        ///Destroy the emitter.
        @trusted ~this()
        {
            stream_ = null;
            clear(states_);
            clear(events_);
            clear(indents_);
            clear(tagDirectives_);
            tagDirectives_ = null;
            clear(preparedAnchor_);
            preparedAnchor_ = null;
            clear(preparedTag_);
            preparedTag_ = null;
        }

        ///Emit an event. Throws EmitterException on error.
        void emit(Event event) @trusted
        {
            events_.push(event);
            while(!needMoreEvents())
            {
                event_ = events_.pop();
                state_();
                clear(event_);
            }
        }

    private:
        ///Pop and return the newest state in states_.
        void delegate() popState() @trusted 
        {
            enforce(states_.length > 0, 
                    new YAMLException("Emitter: Need to pop a state but there are no states left"));
            const result = states_.back;
            states_.length = states_.length - 1;
            return result;
        }

        ///Pop and return the newest indent in indents_.
        int popIndent() @trusted
        {
            enforce(indents_.length > 0, 
                    new YAMLException("Emitter: Need to pop an indent level but there"
                                      " are no indent levels left"));
            const result = indents_.back;
            indents_.length = indents_.length - 1;
            return result;
        }

        ///Write a string to the file/stream.
        void writeString(const string str) @system
        {
            try final switch(encoding_)
            {
                case Encoding.UTF_8:
                    stream_.writeExact(str.ptr, str.length * char.sizeof);
                    break;
                case Encoding.UTF_16:
                    const buffer = to!wstring(str);
                    stream_.writeExact(buffer.ptr, buffer.length * wchar.sizeof);
                    break;
                case Encoding.UTF_32:
                    const buffer = to!dstring(str);
                    stream_.writeExact(buffer.ptr, buffer.length * dchar.sizeof);
                    break;
            }
            catch(WriteException e)
            {
                throw new Error("Unable to write to stream: " ~ e.msg);
            }
        }

        ///In some cases, we wait for a few next events before emitting.
        bool needMoreEvents() @trusted nothrow
        {
            if(events_.length == 0){return true;}

            const event = events_.peek();
            if(event.id == EventID.DocumentStart){return needEvents(1);}
            if(event.id == EventID.SequenceStart){return needEvents(2);}
            if(event.id == EventID.MappingStart) {return needEvents(3);}

            return false;
        }

        ///Determines if we need specified number of more events.
        bool needEvents(in uint count) @system nothrow
        {
            int level = 0;

            //Rather ugly, but good enough for now. 
            //Couldn't be bothered writing a range as events_ should eventually
            //become a Phobos queue/linked list.
            events_.startIteration();
            events_.next();
            while(!events_.iterationOver())
            {
                const event = events_.next();
                static starts = [EventID.DocumentStart, EventID.SequenceStart, EventID.MappingStart];
                static ends   = [EventID.DocumentEnd, EventID.SequenceEnd, EventID.MappingEnd];
                if(starts.canFind(event.id))   {++level;}
                else if(ends.canFind(event.id)){--level;}
                else if(event.id == EventID.StreamStart){level = -1;}

                if(level < 0)
                {
                    return false;
                }
            }

            return events_.length < (count + 1);
        }

        ///Increase indentation level.
        void increaseIndent(const Flag!"flow" flow = No.flow, const bool indentless = false) @trusted
        {
            indents_ ~= indent_;
            if(indent_ == -1)
            {
                indent_ = flow ? bestIndent_ : 0;
            }
            else if(!indentless)
            {
                indent_ += bestIndent_;
            }
        }

        ///Determines if the type of current event is as specified. Throws if no event.
        bool eventTypeIs(in EventID id) const pure @trusted
        {
            enforce(!event_.isNull,
                    new Error("Expected an event, but no event is available."));
            return event_.id == id;
        }


        //States.


        //Stream handlers.

        ///Handle start of a file/stream.
        void expectStreamStart() @trusted
        {
            enforce(eventTypeIs(EventID.StreamStart),
                    new Error("Expected StreamStart, but got " ~ event_.idString));

            encoding_ = event_.encoding;
            writeStreamStart();
            state_ = &expectDocumentStart!(Yes.first);
        }

        ///Expect nothing, throwing if we still have something.
        void expectNothing() const @trusted
        {
            throw new Error("Expected nothing, but got " ~ event_.idString);
        }

        //Document handlers.

        ///Handle start of a document.
        void expectDocumentStart(Flag!"first" first)() @trusted
        {
            enforce(eventTypeIs(EventID.DocumentStart) || eventTypeIs(EventID.StreamEnd),
                    new Error("Expected DocumentStart or StreamEnd, but got " 
                              ~ event_.idString));

            if(event_.id == EventID.DocumentStart)
            {
                const YAMLVersion = event_.value;
                auto tagDirectives = event_.tagDirectives;
                if(openEnded_ && (YAMLVersion !is null || tagDirectives !is null))
                {
                    writeIndicator("...", Yes.needWhitespace);
                    writeIndent();
                }
                
                if(YAMLVersion !is null)
                {
                    writeVersionDirective(prepareVersion(YAMLVersion));
                }

                if(tagDirectives !is null)
                {
                    tagDirectives_ = tagDirectives;
                    sort!"icmp(a.handle, b.handle) < 0"(tagDirectives_);

                    foreach(ref pair; tagDirectives_)
                    {
                        writeTagDirective(prepareTagHandle(pair.handle), 
                                          prepareTagPrefix(pair.prefix));
                    }
                }

                bool eq(ref TagDirective a, ref TagDirective b){return a.handle == b.handle;}
                //Add any default tag directives that have not been overriden.
                foreach(ref def; defaultTagDirectives_) 
                {
                    if(!std.algorithm.canFind!eq(tagDirectives_, def))
                    {
                        tagDirectives_ ~= def;
                    } 
                }

                const implicit = first && !event_.explicitDocument && !canonical_ &&
                                 YAMLVersion is null && tagDirectives is null && 
                                 !checkEmptyDocument();
                if(!implicit)
                {
                    writeIndent();
                    writeIndicator("---", Yes.needWhitespace);
                    if(canonical_){writeIndent();}
                }
                state_ = &expectRootNode;
            }
            else if(event_.id == EventID.StreamEnd)
            {
                if(openEnded_)
                {
                    writeIndicator("...", Yes.needWhitespace);
                    writeIndent();
                }
                writeStreamEnd();
                state_ = &expectNothing;
            }
        }

        ///Handle end of a document.
        void expectDocumentEnd() @trusted
        {
            enforce(eventTypeIs(EventID.DocumentEnd),
                    new Error("Expected DocumentEnd, but got " ~ event_.idString));

            writeIndent();
            if(event_.explicitDocument)
            {
                writeIndicator("...", Yes.needWhitespace);
                writeIndent();
            }
            stream_.flush();
            state_ = &expectDocumentStart!(No.first);
        }

        ///Handle the root node of a document.
        void expectRootNode() @trusted
        {
            states_ ~= &expectDocumentEnd;
            expectNode(Context.Root);
        }

        ///Handle a mapping node.
        //
        //Params: simpleKey = Are we in a simple key?
        void expectMappingNode(const bool simpleKey = false)
        {
            expectNode(simpleKey ? Context.MappingSimpleKey : Context.MappingNoSimpleKey);
        }

        ///Handle a sequence node.
        void expectSequenceNode()
        {
            expectNode(Context.Sequence);
        }

        ///Handle a new node. Context specifies where in the document we are.
        void expectNode(const Context context) @trusted
        {
            context_ = context;

            const flowCollection = event_.collectionStyle == CollectionStyle.Flow;

            switch(event_.id)
            {
                case EventID.Alias: expectAlias(); break;
                case EventID.Scalar:
                     processAnchor("&");
                     processTag();
                     expectScalar();
                     break;
                case EventID.SequenceStart:
                     processAnchor("&");
                     processTag();
                     if(flowLevel_ > 0 || canonical_ || flowCollection || checkEmptySequence())
                     {
                         expectFlowSequence();
                     }
                     else
                     {
                         expectBlockSequence();
                     }
                     break;
                case EventID.MappingStart:
                     processAnchor("&");
                     processTag();
                     if(flowLevel_ > 0 || canonical_ || flowCollection || checkEmptyMapping())
                     {
                         expectFlowMapping();
                     }
                     else
                     {
                         expectBlockMapping();
                     }
                     break;
                default:
                     throw new Error("Expected Alias, Scalar, SequenceStart or "
                                     "MappingStart, but got: " ~ event_.idString);
            }
        }
        ///Handle an alias.
        void expectAlias() @trusted
        {
            enforce(!event_.anchor.isNull(), new Error("Anchor is not specified for alias"));
            processAnchor("*");
            state_ = popState();
        }

        ///Handle a scalar.
        void expectScalar() @trusted
        {
            increaseIndent(Yes.flow);
            processScalar();
            indent_ = popIndent();
            state_ = popState();
        }

        //Flow sequence handlers.

        ///Handle a flow sequence.
        void expectFlowSequence() @trusted
        {
            writeIndicator("[", Yes.needWhitespace, Yes.whitespace);
            ++flowLevel_;
            increaseIndent(Yes.flow);
            state_ = &expectFlowSequenceItem!(Yes.first);
        }

        ///Handle a flow sequence item.
        void expectFlowSequenceItem(Flag!"first" first)() @trusted
        {
            if(event_.id == EventID.SequenceEnd)
            {
                indent_ = popIndent();
                --flowLevel_;
                static if(!first) if(canonical_)
                {
                    writeIndicator(",", No.needWhitespace);
                    writeIndent();
                }
                writeIndicator("]", No.needWhitespace);
                state_ = popState();
                return;
            }
            static if(!first){writeIndicator(",", No.needWhitespace);}
            if(canonical_ || column_ > bestWidth_){writeIndent();}
            states_ ~= &expectFlowSequenceItem!(No.first);
            expectSequenceNode();
        }

        //Flow mapping handlers.

        ///Handle a flow mapping.
        void expectFlowMapping() @trusted
        {
            writeIndicator("{", Yes.needWhitespace, Yes.whitespace);
            ++flowLevel_;
            increaseIndent(Yes.flow);
            state_ = &expectFlowMappingKey!(Yes.first);
        }

        ///Handle a key in a flow mapping.
        void expectFlowMappingKey(Flag!"first" first)() @trusted
        {
            if(event_.id == EventID.MappingEnd)
            {
                indent_ = popIndent();
                --flowLevel_;
                static if (!first) if(canonical_)
                {
                    writeIndicator(",", No.needWhitespace);
                    writeIndent();
                }
                writeIndicator("}", No.needWhitespace);
                state_ = popState();
                return;
            }

            static if(!first){writeIndicator(",", No.needWhitespace);}
            if(canonical_ || column_ > bestWidth_){writeIndent();}
            if(!canonical_ && checkSimpleKey())
            {
                states_ ~= &expectFlowMappingSimpleValue;
                expectMappingNode(true);
                return;
            }

            writeIndicator("?", Yes.needWhitespace);
            states_ ~= &expectFlowMappingValue;
            expectMappingNode();
        }

        ///Handle a simple value in a flow mapping.
        void expectFlowMappingSimpleValue() @trusted
        {
            writeIndicator(":", No.needWhitespace);
            states_ ~= &expectFlowMappingKey!(No.first);
            expectMappingNode();
        }

        ///Handle a complex value in a flow mapping.
        void expectFlowMappingValue() @trusted
        {
            if(canonical_ || column_ > bestWidth_){writeIndent();}
            writeIndicator(":", Yes.needWhitespace);
            states_ ~= &expectFlowMappingKey!(No.first);
            expectMappingNode();
        }

        //Block sequence handlers.

        ///Handle a block sequence.
        void expectBlockSequence() @safe
        {
            const indentless = (context_ == Context.MappingNoSimpleKey ||
                                context_ == Context.MappingSimpleKey) && !indentation_;
            increaseIndent(No.flow, indentless);
            state_ = &expectBlockSequenceItem!(Yes.first);
        }

        ///Handle a block sequence item.
        void expectBlockSequenceItem(Flag!"first" first)() @trusted
        {
            static if(!first) if(event_.id == EventID.SequenceEnd)
            {
                indent_ = popIndent();
                state_ = popState();
                return;
            }

            writeIndent();
            writeIndicator("-", Yes.needWhitespace, No.whitespace, Yes.indentation);
            states_ ~= &expectBlockSequenceItem!(No.first);
            expectSequenceNode();
        }

        //Block mapping handlers.

        ///Handle a block mapping.
        void expectBlockMapping() @safe
        {
            increaseIndent(No.flow);
            state_ = &expectBlockMappingKey!(Yes.first);
        }

        ///Handle a key in a block mapping.
        void expectBlockMappingKey(Flag!"first" first)() @trusted
        {
            static if(!first) if(event_.id == EventID.MappingEnd)
            {
                indent_ = popIndent();
                state_ = popState();
                return;
            }

            writeIndent();
            if(checkSimpleKey())
            {
                states_ ~= &expectBlockMappingSimpleValue;
                expectMappingNode(true);
                return;
            }

            writeIndicator("?", Yes.needWhitespace, No.whitespace, Yes.indentation);
            states_ ~= &expectBlockMappingValue;
            expectMappingNode();
        }

        ///Handle a simple value in a block mapping.
        void expectBlockMappingSimpleValue() @trusted
        {
            writeIndicator(":", No.needWhitespace);
            states_ ~= &expectBlockMappingKey!(No.first);
            expectMappingNode();
        }

        ///Handle a complex value in a block mapping.
        void expectBlockMappingValue() @trusted
        {
            writeIndent();
            writeIndicator(":", Yes.needWhitespace, No.whitespace, Yes.indentation);
            states_ ~= &expectBlockMappingKey!(No.first);
            expectMappingNode();
        }

        //Checkers.

        ///Check if an empty sequence is next.
        bool checkEmptySequence() const @trusted pure nothrow
        {
            return event_.id == EventID.SequenceStart && events_.length > 0 
                   && events_.peek().id == EventID.SequenceEnd;
        }

        ///Check if an empty mapping is next.
        bool checkEmptyMapping() const @trusted pure nothrow
        {
            return event_.id == EventID.MappingStart && events_.length > 0 
                   && events_.peek().id == EventID.MappingEnd;
        }

        ///Check if an empty document is next.
        bool checkEmptyDocument() const @trusted pure nothrow
        {
            if(event_.id != EventID.DocumentStart || events_.length == 0)
            {
                return false;
            }

            const event = events_.peek();
            const emptyScalar = event.id == EventID.Scalar && event.anchor.isNull() &&
                                event.tag.isNull() && event.implicit && event.value == "";
            return emptyScalar;
        }

        ///Check if a simple key is next.
        bool checkSimpleKey() @trusted 
        {
            uint length = 0;
            const id = event_.id;
            const scalar = id == EventID.Scalar;
            const collectionStart = id == EventID.MappingStart || 
                                    id == EventID.SequenceStart;

            if((id == EventID.Alias || scalar || collectionStart) 
               && !event_.anchor.isNull())
            {
                if(preparedAnchor_ is null)
                {
                    preparedAnchor_ = prepareAnchor(event_.anchor);
                }
                length += preparedAnchor_.length;
            }

            if((scalar || collectionStart) && !event_.tag.isNull())
            {
                if(preparedTag_ is null){preparedTag_ = prepareTag(event_.tag);}
                length += preparedTag_.length;
            }

            if(scalar)
            {
                if(analysis_.flags.isNull){analysis_ = analyzeScalar(event_.value);}
                length += analysis_.scalar.length;
            }

            if(length >= 128){return false;}

            return id == EventID.Alias || 
                   (scalar && !analysis_.flags.empty && !analysis_.flags.multiline) ||
                   checkEmptySequence() || 
                   checkEmptyMapping();
        }

        ///Process and write a scalar.
        void processScalar() @trusted
        {
            if(analysis_.flags.isNull){analysis_ = analyzeScalar(event_.value);}
            if(style_ == ScalarStyle.Invalid)
            {
                style_ = chooseScalarStyle();
            }

            //if(analysis_.flags.multiline && (context_ != Context.MappingSimpleKey) && 
            //   ([ScalarStyle.Invalid, ScalarStyle.Plain, ScalarStyle.SingleQuoted, ScalarStyle.DoubleQuoted)
            //    .canFind(style_))
            //{
            //    writeIndent();
            //}
            auto writer = ScalarWriter(this, analysis_.scalar,
                                       context_ != Context.MappingSimpleKey);
            with(writer) final switch(style_)
            {
                case ScalarStyle.Invalid:      assert(false);
                case ScalarStyle.DoubleQuoted: writeDoubleQuoted(); break;
                case ScalarStyle.SingleQuoted: writeSingleQuoted(); break;
                case ScalarStyle.Folded:       writeFolded();       break;
                case ScalarStyle.Literal:      writeLiteral();      break;
                case ScalarStyle.Plain:        writePlain();        break;
            }
            analysis_.flags.isNull = true;
            style_ = ScalarStyle.Invalid;
        }

        ///Process and write an anchor/alias.
        void processAnchor(const string indicator) @trusted
        {
            if(event_.anchor.isNull())
            {
                preparedAnchor_ = null;
                return;
            }
            if(preparedAnchor_ is null)
            {
                preparedAnchor_ = prepareAnchor(event_.anchor);
            }
            if(preparedAnchor_ !is null && preparedAnchor_ != "")
            {
                writeIndicator(indicator, Yes.needWhitespace);
                writeString(preparedAnchor_);
            }
            preparedAnchor_ = null;
        }

        ///Process and write a tag.
        void processTag() @trusted
        {
            Tag tag = event_.tag;

            if(event_.id == EventID.Scalar)
            {
                if(style_ == ScalarStyle.Invalid){style_ = chooseScalarStyle();}
                if((!canonical_ || tag.isNull()) && 
                   (style_ == ScalarStyle.Plain ? event_.implicit : event_.implicit_2))
                {
                    preparedTag_ = null;
                    return;
                }
                if(event_.implicit && tag.isNull())
                {
                    tag = Tag("!");
                    preparedTag_ = null;
                }
            }
            else if((!canonical_ || tag.isNull()) && event_.implicit)
            {
                preparedTag_ = null;
                return;
            }
            
            enforce(!tag.isNull(), new Error("Tag is not specified"));
            if(preparedTag_ is null){preparedTag_ = prepareTag(tag);}
            if(preparedTag_ !is null && preparedTag_ != "")
            {
                writeIndicator(preparedTag_, Yes.needWhitespace);
            }
            preparedTag_ = null;
        }

        ///Determine style to write the current scalar in.
        ScalarStyle chooseScalarStyle() @trusted
        {
            if(analysis_.flags.isNull){analysis_ = analyzeScalar(event_.value);}

            const style          = event_.scalarStyle;
            const invalidOrPlain = style == ScalarStyle.Invalid || style == ScalarStyle.Plain;
            const block          = style == ScalarStyle.Literal || style == ScalarStyle.Folded;
            const singleQuoted   = style == ScalarStyle.SingleQuoted;
            const doubleQuoted   = style == ScalarStyle.DoubleQuoted;

            const allowPlain     = flowLevel_ > 0 ? analysis_.flags.allowFlowPlain 
                                                  : analysis_.flags.allowBlockPlain;
            //simple empty or multiline scalars can't be written in plain style
            const simpleNonPlain = (context_ == Context.MappingSimpleKey) && 
                                   (analysis_.flags.empty || analysis_.flags.multiline);

            if(doubleQuoted || canonical_)
            {
                return ScalarStyle.DoubleQuoted;
            }

            if(invalidOrPlain && event_.implicit && !simpleNonPlain && allowPlain)
            {
                return ScalarStyle.Plain;
            }

            if(block && flowLevel_ == 0 && context_ != Context.MappingSimpleKey && 
               analysis_.flags.allowBlock)
            {
                return style;
            }

            if((invalidOrPlain || singleQuoted) && 
               analysis_.flags.allowSingleQuoted && 
               !(context_ == Context.MappingSimpleKey && analysis_.flags.multiline))
            {
                return ScalarStyle.SingleQuoted;
            }

            return ScalarStyle.DoubleQuoted;
        }

        ///Prepare YAML version string for output.
        static string prepareVersion(const string YAMLVersion) @trusted
        {
            enforce(YAMLVersion.split(".")[0] == "1",
                    new Error("Unsupported YAML version: " ~ YAMLVersion));
            return YAMLVersion;
        }

        ///Encode an Unicode character for tag directive and write it to writer.
        static void encodeChar(Writer)(ref Writer writer, in dchar c) @trusted
        {
            char[4] data;
            const bytes = encode(data, c);
            //For each byte add string in format %AB , where AB are hex digits of the byte.
            foreach(const char b; data[0 .. bytes])
            {
                formattedWrite(writer, "%%%02X", cast(ubyte)b);
            }
        }

        ///Prepare tag directive handle for output.
        static string prepareTagHandle(const string handle) @trusted
        {
            enforce(handle !is null && handle != "",
                    new Error("Tag handle must not be empty"));

            if(handle.length > 1) foreach(const dchar c; handle[1 .. $ - 1])
            {
                enforce(isAlphaNum(c) || "-_"d.canFind(c),
                        new Error("Invalid character: " ~ to!string(c)  ~
                                  " in tag handle " ~ handle));
            }
            return handle;
        }

        ///Prepare tag directive prefix for output.
        static string prepareTagPrefix(const string prefix) @trusted
        {
            enforce(prefix !is null && prefix != "",
                    new Error("Tag prefix must not be empty"));

            auto appender = appender!string();
            const offset = prefix[0] == '!' ? 1 : 0;
            size_t start = 0;
            size_t end = 0;

            foreach(const size_t i, const dchar c; prefix)
            {
                const size_t idx = i + offset;
                if(isAlphaNum(c) || "-;/?:@&=+$,_.!~*\'()[]%"d.canFind(c))
                {
                    end = idx + 1;
                    continue;
                }

                if(start < idx){appender.put(prefix[start .. idx]);}
                start = end = idx + 1;

                encodeChar(appender, c);
            }

            end = min(end, prefix.length);
            if(start < end){appender.put(prefix[start .. end]);}
            return appender.data;
        }

        ///Prepare tag for output.
        string prepareTag(in Tag tag) @trusted
        {
            enforce(!tag.isNull(), new Error("Tag must not be empty"));

            string tagString = tag.get;
            if(tagString == "!"){return tagString;}
            string handle = null;
            string suffix = tagString;

            //Sort lexicographically by prefix.
            sort!"icmp(a.prefix, b.prefix) < 0"(tagDirectives_);
            foreach(ref pair; tagDirectives_)
            {
                auto prefix = pair.prefix;
                if(tagString.startsWith(prefix) && 
                   (prefix != "!" || prefix.length < tagString.length))
                {
                    handle = pair.handle;
                    suffix = tagString[prefix.length .. $];
                }
            }

            auto appender = appender!string();
            appender.put(handle !is null && handle != "" ? handle : "!<");
            size_t start = 0;
            size_t end = 0;
            foreach(const dchar c; suffix)
            {
                if(isAlphaNum(c) || "-;/?:@&=+$,_.~*\'()[]"d.canFind(c) || 
                   (c == '!' && handle != "!"))
                {
                    ++end;
                    continue;
                }
                if(start < end){appender.put(suffix[start .. end]);}
                start = end = end + 1;

                encodeChar(appender, c);
            }

            if(start < end){appender.put(suffix[start .. end]);}
            if(handle is null || handle == ""){appender.put(">");}

            return appender.data;
        }

        ///Prepare anchor for output.
        static string prepareAnchor(const Anchor anchor) @trusted
        {
            enforce(!anchor.isNull() && anchor.get != "",
                    new Error("Anchor must not be empty"));
            const str = anchor.get;
            foreach(const dchar c; str)
            {
                enforce(isAlphaNum(c) || "-_"d.canFind(c),
                        new Error("Invalid character: " ~ to!string(c) ~ " in anchor: " ~ str));
            }
            return str;
        }

        ///Analyze specifed scalar and return the analysis result.
        static ScalarAnalysis analyzeScalar(string scalar) @safe
        {
            ScalarAnalysis analysis;
            analysis.flags.isNull = false;
            analysis.scalar = scalar;

            //Empty scalar is a special case.
            with(analysis.flags) if(scalar is null || scalar == "")
            {
                empty             = true;
                multiline         = false;
                allowFlowPlain    = false;
                allowBlockPlain   = true;
                allowSingleQuoted = true;
                allowDoubleQuoted = true;
                allowBlock        = false;
                return analysis;
            }

            //Indicators and special characters (All false by default). 
            bool blockIndicators, flowIndicators, lineBreaks, specialCharacters;

            //Important whitespace combinations (All false by default).
            bool leadingSpace, leadingBreak, trailingSpace, trailingBreak, 
                 breakSpace, spaceBreak;

            //Check document indicators.
            if(scalar.startsWith("---", "..."))
            {
                blockIndicators = flowIndicators = true;
            }
            
            //First character or preceded by a whitespace.
            bool preceededByWhitespace = true;

            //Last character or followed by a whitespace.
            bool followedByWhitespace = scalar.length == 1 || 
                                        " \t\0\n\r\u0085\u2028\u2029"d.canFind(scalar[1]);

            //The previous character is a space/break (false by default).
            bool previousSpace, previousBreak;

            foreach(const size_t index, const dchar c; scalar)
            {
                mixin FastCharSearch!("#,[]{}&*!|>\'\"%@`"d, 128) specialCharSearch;
                mixin FastCharSearch!(",?[]{}"d, 128) flowIndicatorSearch;

                //Check for indicators.
                if(index == 0)
                {
                    //Leading indicators are special characters.
                    if(specialCharSearch.canFind(c))
                    {
                        flowIndicators = blockIndicators = true;
                    }
                    if(':' == c || '?' == c)
                    {
                        flowIndicators = true;
                        if(followedByWhitespace){blockIndicators = true;}
                    }
                    if(c == '-' && followedByWhitespace)
                    {
                        flowIndicators = blockIndicators = true;
                    }
                }
                else
                {
                    //Some indicators cannot appear within a scalar as well.
                    if(flowIndicatorSearch.canFind(c)){flowIndicators = true;}
                    if(c == ':')
                    {
                        flowIndicators = true;
                        if(followedByWhitespace){blockIndicators = true;}
                    }
                    if(c == '#' && preceededByWhitespace)
                    {
                        flowIndicators = blockIndicators = true;
                    }
                }

                //Check for line breaks, special, and unicode characters.
                if(newlineSearch_.canFind(c)){lineBreaks = true;}
                if(!(c == '\n' || (c >= '\x20' && c <= '\x7E')) &&
                   !((c == '\u0085' || (c >= '\xA0' && c <= '\uD7FF') ||
                     (c >= '\uE000' && c <= '\uFFFD')) && c != '\uFEFF'))
                {
                    specialCharacters = true;
                }
                
                //Detect important whitespace combinations.
                if(c == ' ')
                {
                    if(index == 0){leadingSpace = true;}
                    if(index == scalar.length - 1){trailingSpace = true;}
                    if(previousBreak){breakSpace = true;}
                    previousSpace = true;
                    previousBreak = false;
                }
                else if(newlineSearch_.canFind(c))
                {
                    if(index == 0){leadingBreak = true;}
                    if(index == scalar.length - 1){trailingBreak = true;}
                    if(previousSpace){spaceBreak = true;}
                    previousSpace = false;
                    previousBreak = true;
                }
                else
                {
                    previousSpace = previousBreak = false;
                }

                mixin FastCharSearch! "\0\n\r\u0085\u2028\u2029 \t"d spaceSearch;
                //Prepare for the next character.
                preceededByWhitespace = spaceSearch.canFind(c);
                followedByWhitespace = index + 2 >= scalar.length || 
                                       spaceSearch.canFind(scalar[index + 2]);
            }

            with(analysis.flags)
            {
                //Let's decide what styles are allowed.
                allowFlowPlain = allowBlockPlain = allowSingleQuoted 
                               = allowDoubleQuoted = allowBlock = true;
                
                //Leading and trailing whitespaces are bad for plain scalars.
                if(leadingSpace || leadingBreak || trailingSpace || trailingBreak)
                {
                    allowFlowPlain = allowBlockPlain = false;
                }

                //We do not permit trailing spaces for block scalars.
                if(trailingSpace){allowBlock = false;}

                //Spaces at the beginning of a new line are only acceptable for block
                //scalars.
                if(breakSpace)
                {
                    allowFlowPlain = allowBlockPlain = allowSingleQuoted = false;
                }

                //Spaces followed by breaks, as well as special character are only
                //allowed for double quoted scalars.
                if(spaceBreak || specialCharacters)
                {
                    allowFlowPlain = allowBlockPlain = allowSingleQuoted = allowBlock = false;
                }

                //Although the plain scalar writer supports breaks, we never emit
                //multiline plain scalars.
                if(lineBreaks){allowFlowPlain = allowBlockPlain = false;}

                //Flow indicators are forbidden for flow plain scalars.
                if(flowIndicators){allowFlowPlain = false;}

                //Block indicators are forbidden for block plain scalars.
                if(blockIndicators){allowBlockPlain = false;}

                empty = false;
                multiline = lineBreaks;
            }

            return analysis;
        }

        //Writers.

        ///Start the YAML stream (write the unicode byte order mark).
        void writeStreamStart() @system
        {
            immutable(ubyte)[] bom;
            //Write BOM (always, even for UTF-8)
            final switch(encoding_)
            {
                case Encoding.UTF_8:
                    bom = ByteOrderMarks[BOM.UTF8];
                    break;
                case Encoding.UTF_16:
                    bom = std.system.endian == Endian.littleEndian 
                          ? ByteOrderMarks[BOM.UTF16LE]
                          : ByteOrderMarks[BOM.UTF16BE];
                    break;
                case Encoding.UTF_32:
                    bom = std.system.endian == Endian.littleEndian 
                          ? ByteOrderMarks[BOM.UTF32LE]  
                          : ByteOrderMarks[BOM.UTF32BE];
                    break;
            }

            enforce(stream_.write(bom) == bom.length, new Error("Unable to write to stream"));
        }

        ///End the YAML stream.
        void writeStreamEnd() @system {stream_.flush();}

        ///Write an indicator (e.g. ":", "[", ">", etc.).
        void writeIndicator(const string indicator, 
                            const Flag!"needWhitespace" needWhitespace, 
                            const Flag!"whitespace" whitespace = No.whitespace,
                            const Flag!"indentation" indentation = No.indentation) @system
        {
            const bool prefixSpace = !whitespace_ && needWhitespace;
            whitespace_  = whitespace;
            indentation_ = indentation_ && indentation;
            openEnded_   = false;
            column_ += indicator.length;
            if(prefixSpace)
            {
                ++column_;
                writeString(" ");
            }
            writeString(indicator);
        }

        ///Write indentation.
        void writeIndent() @system
        {
            const indent = indent_ == -1 ? 0 : indent_;

            if(!indentation_ || column_ > indent || (column_ == indent && !whitespace_))
            {
                writeLineBreak();
            }
            if(column_ < indent)
            {
                whitespace_ = true;

                //Used to avoid allocation of arbitrary length strings.
                static immutable spaces = "    ";
                size_t numSpaces = indent - column_;
                column_ = indent;
                while(numSpaces >= spaces.length)
                {
                    writeString(spaces);
                    numSpaces -= spaces.length;
                }
                writeString(spaces[0 .. numSpaces]);
            }
        }

        ///Start new line.
        void writeLineBreak(const string data = null) @system
        {
            whitespace_ = indentation_ = true;
            ++line_;
            column_ = 0;
            writeString(data is null ? lineBreak(bestLineBreak_) : data);
        }

        ///Write a YAML version directive.
        void writeVersionDirective(const string versionText) @system
        {
            writeString("%YAML ");
            writeString(versionText);
            writeLineBreak();
        }

        ///Write a tag directive.
        void writeTagDirective(const string handle, const string prefix) @system
        {
            writeString("%TAG ");
            writeString(handle);
            writeString(" ");
            writeString(prefix);
            writeLineBreak();
        }
}


private:

///RAII struct used to write out scalar values.
struct ScalarWriter
{
    invariant()
    {
        assert(emitter_.bestIndent_ > 0 && emitter_.bestIndent_ < 10,
               "Emitter bestIndent must be 1 to 9 for one-character indent hint");
    }

    private:
        @disable int opCmp(ref Emitter);
        @disable bool opEquals(ref Emitter);

        ///Used as "null" UTF-32 character.
        immutable dcharNone = dchar.max;

        ///Emitter used to emit the scalar.
        Emitter* emitter_;

        ///UTF-8 encoded text of the scalar to write.
        string text_;

        ///Can we split the scalar into multiple lines?
        bool split_;
        ///Are we currently going over spaces in the text?
        bool spaces_;
        ///Are we currently going over line breaks in the text?
        bool breaks_;

        ///Start and end byte of the text range we're currently working with.
        size_t startByte_, endByte_;
        ///End byte of the text range including the currently processed character.
        size_t nextEndByte_;
        ///Start and end character of the text range we're currently working with.
        long startChar_, endChar_;

    public:
        ///Construct a ScalarWriter using emitter to output text.
        this(ref Emitter emitter, string text, const bool split = true) @trusted nothrow
        {
            emitter_ = &emitter;
            text_ = text;
            split_ = split;
        }

        ///Destroy the ScalarWriter.
        @trusted nothrow ~this()
        {
            text_ = null;
        }

        ///Write text as single quoted scalar.
        void writeSingleQuoted() @system
        {
            emitter_.writeIndicator("\'", Yes.needWhitespace);
            spaces_ = breaks_ = false;
            resetTextPosition();

            do
            {   
                const dchar c = nextChar();
                if(spaces_)
                {
                    if(c != ' ' && tooWide() && split_ && 
                       startByte_ != 0 && endByte_ != text_.length)
                    {
                        writeIndent(Flag!"ResetSpace".no);
                        updateRangeStart();
                    }
                    else if(c != ' ')
                    {
                        writeCurrentRange(Flag!"UpdateColumn".yes);
                    }
                }
                else if(breaks_)
                {
                    if(!newlineSearch_.canFind(c))
                    {
                        writeStartLineBreak();
                        writeLineBreaks();
                        emitter_.writeIndent();
                    }
                }
                else if((c == dcharNone || c == '\'' || c == ' ' || newlineSearch_.canFind(c))
                        && startChar_ < endChar_)
                {
                    writeCurrentRange(Flag!"UpdateColumn".yes);
                }
                if(c == '\'')
                {
                    emitter_.column_ += 2;
                    emitter_.writeString("\'\'");
                    startByte_ = endByte_ + 1;
                    startChar_ = endChar_ + 1;
                }
                updateBreaks(c, Flag!"UpdateSpaces".yes);
            }while(endByte_ < text_.length);

            emitter_.writeIndicator("\'", No.needWhitespace);
        }

        ///Write text as double quoted scalar.
        void writeDoubleQuoted() @system
        {
            resetTextPosition();
            emitter_.writeIndicator("\"", Yes.needWhitespace);
            do
            {   
                const dchar c = nextChar();
                //handle special characters
                if(c == dcharNone || "\"\\\u0085\u2028\u2029\uFEFF"d.canFind(c) ||
                   !((c >= '\x20' && c <= '\x7E') || 
                     ((c >= '\xA0' && c <= '\uD7FF') || (c >= '\uE000' && c <= '\uFFFD'))))
                {
                    if(startChar_ < endChar_)
                    {
                        writeCurrentRange(Flag!"UpdateColumn".yes);
                    }
                    if(c != dcharNone)
                    {
                        auto appender = appender!string();
                        if((c in dyaml.escapes.toEscapes) !is null)
                        {
                            appender.put('\\');
                            appender.put(dyaml.escapes.toEscapes[c]);
                        }
                        else
                        {
                            //Write an escaped Unicode character.
                            const format = c <= 255   ? "\\x%02X":
                                           c <= 65535 ? "\\u%04X": "\\u%08X";
                            formattedWrite(appender, format, cast(uint)c);
                        }

                        emitter_.column_ += appender.data.length;
                        emitter_.writeString(appender.data);
                        startChar_ = endChar_ + 1;
                        startByte_ = nextEndByte_;
                    }
                }
                if((endByte_ > 0 && endByte_ < text_.length - strideBack(text_, text_.length)) 
                   && (c == ' ' || startChar_ >= endChar_) 
                   && (emitter_.column_ + endChar_ - startChar_ > emitter_.bestWidth_) 
                   && split_)
                {
                    //text_[2:1] is ok in Python but not in D, so we have to use min()
                    emitter_.writeString(text_[min(startByte_, endByte_) .. endByte_]);
                    emitter_.writeString("\\");
                    emitter_.column_ += startChar_ - endChar_ + 1;
                    startChar_ = max(startChar_, endChar_);
                    startByte_ = max(startByte_, endByte_);

                    writeIndent(Flag!"ResetSpace".yes);
                    if(charAtStart() == ' ')
                    {
                        emitter_.writeString("\\");
                        ++emitter_.column_;
                    }
                }
            }while(endByte_ < text_.length);
            emitter_.writeIndicator("\"", No.needWhitespace);
        }

        ///Write text as folded block scalar.
        void writeFolded() @system
        {
            initBlock('>');
            bool leadingSpace = true;
            spaces_ = false;
            breaks_ = true;
            resetTextPosition();

            do
            {   
                const dchar c = nextChar();
                if(breaks_)
                {
                    if(!newlineSearch_.canFind(c))
                    {
                        if(!leadingSpace && c != dcharNone && c != ' ')
                        {
                            writeStartLineBreak();
                        }
                        leadingSpace = (c == ' ');
                        writeLineBreaks();
                        if(c != dcharNone){emitter_.writeIndent();}
                    }
                }
                else if(spaces_)
                {
                    if(c != ' ' && tooWide())
                    {
                        writeIndent(Flag!"ResetSpace".no);
                        updateRangeStart();
                    }
                    else if(c != ' ')
                    {
                        writeCurrentRange(Flag!"UpdateColumn".yes);
                    }
                }
                else if(c == dcharNone || newlineSearch_.canFind(c) || c == ' ')
                {
                    writeCurrentRange(Flag!"UpdateColumn".yes);
                    if(c == dcharNone){emitter_.writeLineBreak();}
                }
                updateBreaks(c, Flag!"UpdateSpaces".yes);
            }while(endByte_ < text_.length);
        }

        ///Write text as literal block scalar.
        void writeLiteral() @system
        {
            initBlock('|');
            breaks_ = true;
            resetTextPosition();

            do
            {   
                const dchar c = nextChar();
                if(breaks_)
                {
                    if(!newlineSearch_.canFind(c))
                    {
                        writeLineBreaks();
                        if(c != dcharNone){emitter_.writeIndent();}
                    }
                }
                else if(c == dcharNone || newlineSearch_.canFind(c))
                {
                    writeCurrentRange(Flag!"UpdateColumn".no);
                    if(c == dcharNone){emitter_.writeLineBreak();}
                }
                updateBreaks(c, Flag!"UpdateSpaces".no);
            }while(endByte_ < text_.length);
        }

        ///Write text as plain scalar.
        void writePlain() @system
        {
            if(emitter_.context_ == Emitter.Context.Root){emitter_.openEnded_ = true;}
            if(text_ == ""){return;}
            if(!emitter_.whitespace_)
            {
                ++emitter_.column_;
                emitter_.writeString(" ");
            }
            emitter_.whitespace_ = emitter_.indentation_ = false;
            spaces_ = breaks_ = false;
            resetTextPosition();

            do
            {   
                const dchar c = nextChar();
                if(spaces_)
                {
                    if(c != ' ' && tooWide() && split_)
                    {
                        writeIndent(Flag!"ResetSpace".yes);
                        updateRangeStart();
                    }
                    else if(c != ' ')
                    {
                        writeCurrentRange(Flag!"UpdateColumn".yes);
                    }
                }
                else if(breaks_)
                {
                    if(!newlineSearch_.canFind(c))
                    {
                        writeStartLineBreak();
                        writeLineBreaks();
                        writeIndent(Flag!"ResetSpace".yes);
                    }
                }
                else if(c == dcharNone || newlineSearch_.canFind(c) || c == ' ')
                {
                    writeCurrentRange(Flag!"UpdateColumn".yes);
                }
                updateBreaks(c, Flag!"UpdateSpaces".yes);
            }while(endByte_ < text_.length);
        }

    private:
        ///Get next character and move end of the text range to it.
        dchar nextChar() pure @safe
        {
            ++endChar_;
            endByte_ = nextEndByte_;
            if(endByte_ >= text_.length){return dcharNone;}
            const c = text_[nextEndByte_];
            //c is ascii, no need to decode.
            if(c < 0x80)
            {
                ++nextEndByte_;
                return c;
            }
            return decode(text_, nextEndByte_);
        }

        ///Get character at start of the text range.
        dchar charAtStart() const pure @safe
        {
            size_t idx = startByte_;
            return decode(text_, idx);
        }

        ///Is the current line too wide?
        bool tooWide() const pure @safe nothrow
        {
            return startChar_ + 1 == endChar_ && 
                   emitter_.column_ > emitter_.bestWidth_;
        }

        ///Determine hints (indicators) for block scalar.
        size_t determineBlockHints(char[] hints, uint bestIndent) const pure @trusted 
        {
            size_t hintsIdx = 0;
            if(text_.length == 0){return hintsIdx;}

            dchar lastChar(const string str, ref size_t end) 
            {
                size_t idx = end = end - strideBack(str, end);
                return decode(text_, idx);
            }

            size_t end = text_.length;
            const last = lastChar(text_, end);
            const secondLast = end > 0 ? lastChar(text_, end) : 0;

            if(newlineSearch_.canFind(text_[0]) || text_[0] == ' ')
            {
                hints[hintsIdx++] = cast(char)('0' + bestIndent);
            }
            if(!newlineSearch_.canFind(last))
            {
                hints[hintsIdx++] = '-';
            }
            else if(std.utf.count(text_) == 1 || newlineSearch_.canFind(secondLast))
            {
                hints[hintsIdx++] = '+';
            }
            return hintsIdx;
        }

        ///Initialize for block scalar writing with specified indicator.
        void initBlock(const char indicator) @system
        {
            char[4] hints;
            hints[0] = indicator;
            const hintsLength = 1 + determineBlockHints(hints[1 .. $], emitter_.bestIndent_);
            emitter_.writeIndicator(cast(string)hints[0 .. hintsLength], Yes.needWhitespace);
            if(hints.length > 0 && hints[$ - 1] == '+')
            {
                emitter_.openEnded_ = true;
            }
            emitter_.writeLineBreak();
        }

        ///Write out the current text range.
        void writeCurrentRange(const Flag!"UpdateColumn" updateColumn) @system
        {
            emitter_.writeString(text_[startByte_ .. endByte_]);
            if(updateColumn){emitter_.column_ += endChar_ - startChar_;}
            updateRangeStart();
        }

        ///Write line breaks in the text range.
        void writeLineBreaks() @system
        {
            foreach(const dchar br; text_[startByte_ .. endByte_])
            {
                if(br == '\n'){emitter_.writeLineBreak();}
                else
                {
                    char[4] brString;
                    const bytes = encode(brString, br);
                    emitter_.writeLineBreak(cast(string)brString[0 .. bytes]);
                }
            }
            updateRangeStart();
        }

        ///Write line break if start of the text range is a newline.
        void writeStartLineBreak() @system
        {
            if(charAtStart == '\n'){emitter_.writeLineBreak();}
        }

        ///Write indentation, optionally resetting whitespace/indentation flags.
        void writeIndent(const Flag!"ResetSpace" resetSpace) @system
        {
            emitter_.writeIndent();
            if(resetSpace)
            {
                emitter_.whitespace_ = emitter_.indentation_ = false;
            }
        }

        ///Move start of text range to its end.
        void updateRangeStart() pure @safe nothrow
        {
            startByte_ = endByte_;
            startChar_ = endChar_;
        }

        ///Update the line breaks_ flag, optionally updating the spaces_ flag.
        void updateBreaks(in dchar c, const Flag!"UpdateSpaces" updateSpaces) pure @trusted
        {
            if(c == dcharNone){return;}
            breaks_ = newlineSearch_.canFind(c);
            if(updateSpaces){spaces_ = c == ' ';}
        }

        ///Move to the beginning of text.
        void resetTextPosition() pure @safe nothrow
        {
            startByte_ = endByte_ = nextEndByte_ = 0;
            startChar_ = endChar_ = -1;
        }
}
