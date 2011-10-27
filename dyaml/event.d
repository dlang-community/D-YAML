
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML events.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dyaml.event;

import std.array;
import std.conv;
import std.typecons;

import dyaml.anchor;
import dyaml.encoding;
import dyaml.exception;
import dyaml.reader;
import dyaml.tag;
import dyaml.tagdirectives;
import dyaml.style;


package:
///Event types.
enum EventID : ubyte
{
    Invalid = 0,     /// Invalid (uninitialized) event.
    StreamStart,     /// Stream start
    StreamEnd,       /// Stream end
    DocumentStart,   /// Document start
    DocumentEnd,     /// Document end
    Alias,           /// Alias
    Scalar,          /// Scalar
    SequenceStart,   /// Sequence start
    SequenceEnd,     /// Sequence end
    MappingStart,    /// Mapping start
    MappingEnd       /// Mapping end
}

/**
 * YAML event produced by parser.
 *
 * 48 bytes on 64bit.
 */
struct Event
{
    ///Value of the event, if any.
    string value;
    ///Start position of the event in file/stream.
    Mark startMark;
    ///End position of the event in file/stream.
    Mark endMark;
    ///Anchor of the event, if any.
    Anchor anchor;
    ///Tag of the event, if any.
    Tag tag;
    ///Event type.
    EventID id = EventID.Invalid;
    ///Style of scalar event, if this is a scalar event.
    ScalarStyle scalarStyle;
    ///Should the tag be implicitly resolved? 
    bool implicit;
    ///TODO figure this out - Unknown, used by PyYAML with Scalar events.
    bool implicit_2;
    /**
     * Is this document event explicit?
     *
     * Used if this is a DocumentStart or DocumentEnd.
     */
    alias implicit explicitDocument;
    ///Tag directives, if this is a DocumentStart.
    TagDirectives tagDirectives;
    ///Encoding of the stream, if this is a StreamStart.
    Encoding encoding;
    ///Collection style, if this is a SequenceStart or MappingStart.
    CollectionStyle collectionStyle;

    ///Is this a null (uninitialized) event?
    @property bool isNull() const {return id == EventID.Invalid;}

    ///Get string representation of the token ID.
    @property string idString() const {return to!string(id);}
}

/**
 * Construct a simple event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 *          anchor   = Anchor, if this is an alias event.
 */
Event event(EventID id)(in Mark start, in Mark end, in Anchor anchor = Anchor()) pure
{
    return Event(null, start, end, anchor, Tag(), id);
}

/**
 * Construct a collection (mapping or sequence) start event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 *          anchor   = Anchor of the sequence, if any.
 *          tag      = Tag of the sequence, if specified.
 *          implicit = Should the tag be implicitly resolved?
 */
Event collectionStartEvent(EventID id)(in Mark start, in Mark end, in Anchor anchor, 
                                       in Tag tag, in bool implicit, 
                                       in CollectionStyle style)
{
    static assert(id == EventID.SequenceStart || id == EventID.SequenceEnd ||
                  id == EventID.MappingStart || id == EventID.MappingEnd);
    return Event(null, start, end, anchor, tag, id, ScalarStyle.Invalid, implicit,
                 false, TagDirectives(), Encoding.UTF_8, style);
}

/**
 * Construct a stream start event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 *          encoding = Encoding of the stream.
 */
Event streamStartEvent(in Mark start, in Mark end, Encoding encoding) 
{
    return Event(null, start, end, Anchor(), Tag(), EventID.StreamStart, 
                 ScalarStyle.Invalid, false, false, TagDirectives(), encoding);
}

///Aliases for simple events.
alias event!(EventID.StreamEnd)   streamEndEvent;
alias event!(EventID.Alias)       aliasEvent;
alias event!(EventID.SequenceEnd) sequenceEndEvent;
alias event!(EventID.MappingEnd)  mappingEndEvent;

///Aliases for collection start events.
alias collectionStartEvent!(EventID.SequenceStart) sequenceStartEvent;
alias collectionStartEvent!(EventID.MappingStart) mappingStartEvent;

/**
 * Construct a document start event.
 *
 * Params:  start         = Start position of the event in the file/stream.
 *          end           = End position of the event in the file/stream.
 *          explicit      = Is this an explicit document start?
 *          YAMLVersion   = YAML version string of the document.
 *          tagDirectives = Tag directives of the document.
 */
Event documentStartEvent(Mark start, Mark end, bool explicit, string YAMLVersion,
                         TagDirectives tagDirectives)
{
    return Event(YAMLVersion, start, end, Anchor(), Tag(), EventID.DocumentStart, 
                 ScalarStyle.Invalid, explicit, false, tagDirectives);
}

/**
 * Construct a document end event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 *          explicit = Is this an explicit document end?
 */
Event documentEndEvent(Mark start, Mark end, bool explicit)
{
    return Event(null, start, end, Anchor(), Tag(), EventID.DocumentEnd,
                 ScalarStyle.Invalid, explicit);
}

/**
 * Construct a scalar event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 *          anchor   = Anchor of the scalar, if any.
 *          tag      = Tag of the scalar, if specified.
 *          implicit = Should the tag be implicitly resolved?
 *          value    = String value of the scalar.
 *          style    = Scalar style.
 */
Event scalarEvent(in Mark start, in Mark end, in Anchor anchor, in Tag tag, 
                  in Tuple!(bool, bool) implicit, in string value, 
                  in ScalarStyle style = ScalarStyle.Invalid) 
{
    return Event(value, start, end, anchor, tag, EventID.Scalar, style, implicit[0],
                 implicit[1]);
}
