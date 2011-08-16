
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

import dyaml.reader;
import dyaml.token;
import dyaml.exception;


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
 * 64 bytes on 64-bit.
 */
immutable struct Event
{
    ///Start position of the event in file/stream.
    Mark startMark;
    ///End position of the event in file/stream.
    Mark endMark;
    ///Anchor of the event, if any.
    string anchor;
    ///Tag of the event, if any.
    string tag;
    ///Value of the event, if any.
    string value;
    ///Event type.
    EventID id;
    ///Style of scalar event, if this is a scalar event.
    ScalarStyle style;
    ///Should the tag be implicitly resolved? 
    bool implicit;
    /**
     * Is this document event explicit?
     *
     * Used if this is a DocumentStart or DocumentEnd.
     */
    alias implicit explicitDocument;
}

/**
 * Construct a simple event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 *          anchor   = Anchor, if this is an alias event.
 */
Event event(EventID id)(in Mark start, in Mark end, in string anchor = null) pure
{
    return Event(start, end, anchor, null, null, id);
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
Event collectionStartEvent(EventID id)(in Mark start, in Mark end, in string anchor, 
                                       in string tag, in bool implicit) pure
{
    static assert(id == EventID.SequenceStart || id == EventID.SequenceEnd ||
                  id == EventID.MappingStart || id == EventID.MappingEnd);
    return Event(start, end, anchor, tag, null, id, ScalarStyle.Invalid, implicit);
}

///Aliases for simple events.
alias event!(EventID.StreamStart) streamStartEvent;
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
 * Params:  start       = Start position of the event in the file/stream.
 *          end         = End position of the event in the file/stream.
 *          explicit    = Is this an explicit document start?
 *          YAMLVersion = YAML version string of the document.
 */
Event documentStartEvent(Mark start, Mark end, bool explicit, string YAMLVersion) pure
{
    return Event(start, end, null, null, YAMLVersion, EventID.DocumentStart, 
                 ScalarStyle.Invalid, explicit);
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
    return Event(start, end, null, null, null, EventID.DocumentEnd,
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
Event scalarEvent(in Mark start, in Mark end, in string anchor, in string tag, 
                  in bool implicit, in string value, 
                  in ScalarStyle style = ScalarStyle.Invalid) pure
{
    return Event(start, end, anchor, tag, value, EventID.Scalar, style, implicit);
}
