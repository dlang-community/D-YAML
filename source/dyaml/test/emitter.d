
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.emitter;


version(unittest)
{

import std.algorithm;
import std.file;
import std.range;
import std.typecons;

import dyaml.emitter;
import dyaml.event;
import dyaml.test.common;
import dyaml.token;

// Try to emit an event range.
void emitTestCommon(T)(ref Appender!string emitStream, T events, bool canonical = false) @safe
    if (isInputRange!T && is(ElementType!T == Event))
{
    auto emitter = Emitter!(typeof(emitStream), char)(emitStream, canonical, 2, 80, LineBreak.unix);
    foreach(ref event; events)
    {
        emitter.emit(event);
    }
}

/// Determine if events in events1 are equivalent to events in events2.
///
/// Params:  events1 = First event array to compare.
///          events2 = Second event array to compare.
///
/// Returns: true if the events are equivalent, false otherwise.
bool compareEvents(T, U)(T events1, U events2)
    if (isInputRange!T && isInputRange!U && is(ElementType!T == Event) && is(ElementType!U == Event))
{
    foreach (e1, e2; zip(events1, events2))
    {
        //Different event types.
        if(e1.id != e2.id){return false;}
        //Different anchor (if applicable).
        if(e1.id.among!(EventID.sequenceStart,
            EventID.mappingStart,
            EventID.alias_,
            EventID.scalar)
            && e1.anchor != e2.anchor)
        {
            return false;
        }
        //Different collection tag (if applicable).
        if(e1.id.among!(EventID.sequenceStart, EventID.mappingStart) && e1.tag != e2.tag)
        {
            return false;
        }
        if(e1.id == EventID.scalar)
        {
            //Different scalar tag (if applicable).
            if(!(e1.implicit || e2.implicit)
               && e1.tag != e2.tag)
            {
                return false;
            }
            //Different scalar value.
            if(e1.value != e2.value)
            {
                return false;
            }
        }
    }
    return true;
}

/// Test emitter by getting events from parsing a file, emitting them, parsing
/// the emitted result and comparing events from parsing the emitted result with
/// originally parsed events.
///
/// Params:  dataFilename      = YAML file to parse.
///          canonicalFilename = Canonical YAML file used as dummy to determine
///                              which data files to load.
void testEmitterOnData(string dataFilename, string canonicalFilename) @safe
{
    //Must exist due to Anchor, Tags reference counts.
    auto loader = Loader.fromFile(dataFilename);
    auto events = loader.parse();
    auto emitStream = Appender!string();
    emitTestCommon(emitStream, events);

    static if(verbose)
    {
        writeln(dataFilename);
        writeln("ORIGINAL:\n", readText(dataFilename));
        writeln("OUTPUT:\n", emitStream.data);
    }

    auto loader2        = Loader.fromString(emitStream.data);
    loader2.name        = "TEST";
    auto newEvents = loader2.parse();
    assert(compareEvents(events, newEvents));
}

/// Test emitter by getting events from parsing a canonical YAML file, emitting
/// them both in canonical and normal format, parsing the emitted results and
/// comparing events from parsing the emitted result with originally parsed events.
///
/// Params:  canonicalFilename = Canonical YAML file to parse.
void testEmitterOnCanonical(string canonicalFilename) @safe
{
    //Must exist due to Anchor, Tags reference counts.
    auto loader = Loader.fromFile(canonicalFilename);
    auto events = loader.parse();
    foreach(canonical; [false, true])
    {
        auto emitStream = Appender!string();
        emitTestCommon(emitStream, events, canonical);
        static if(verbose)
        {
            writeln("OUTPUT (canonical=", canonical, "):\n",
                    emitStream.data);
        }
        auto loader2        = Loader.fromString(emitStream.data);
        loader2.name        = "TEST";
        auto newEvents = loader2.parse();
        assert(compareEvents(events, newEvents));
    }
}

/// Test emitter by getting events from parsing a file, emitting them with all
/// possible scalar and collection styles, parsing the emitted results and
/// comparing events from parsing the emitted result with originally parsed events.
///
/// Params:  dataFilename      = YAML file to parse.
///          canonicalFilename = Canonical YAML file used as dummy to determine
///                              which data files to load.
void testEmitterStyles(string dataFilename, string canonicalFilename) @safe
{
    foreach(filename; [dataFilename, canonicalFilename])
    {
        //must exist due to Anchor, Tags reference counts
        auto loader = Loader.fromFile(canonicalFilename);
        auto events = loader.parse();
        foreach(flowStyle; [CollectionStyle.block, CollectionStyle.flow])
        {
            foreach(style; [ScalarStyle.literal, ScalarStyle.folded,
                            ScalarStyle.doubleQuoted, ScalarStyle.singleQuoted,
                            ScalarStyle.plain])
            {
                Event[] styledEvents;
                foreach(event; events)
                {
                    if(event.id == EventID.scalar)
                    {
                        event = scalarEvent(Mark(), Mark(), event.anchor, event.tag,
                                            event.implicit,
                                            event.value, style);
                    }
                    else if(event.id == EventID.sequenceStart)
                    {
                        event = sequenceStartEvent(Mark(), Mark(), event.anchor,
                                                   event.tag, event.implicit, flowStyle);
                    }
                    else if(event.id == EventID.mappingStart)
                    {
                        event = mappingStartEvent(Mark(), Mark(), event.anchor,
                                                  event.tag, event.implicit, flowStyle);
                    }
                    styledEvents ~= event;
                }
                auto emitStream = Appender!string();
                emitTestCommon(emitStream, styledEvents);
                static if(verbose)
                {
                    writeln("OUTPUT (", filename, ", ", to!string(flowStyle), ", ",
                            to!string(style), ")");
                    writeln(emitStream.data);
                }
                auto loader2        = Loader.fromString(emitStream.data);
                loader2.name        = "TEST";
                auto newEvents = loader2.parse();
                assert(compareEvents(events, newEvents));
            }
        }
    }
}

@safe unittest
{
    printProgress("D:YAML Emitter unittest");
    run("testEmitterOnData",      &testEmitterOnData,      ["data", "canonical"]);
    run("testEmitterOnCanonical", &testEmitterOnCanonical, ["canonical"]);
    run("testEmitterStyles",      &testEmitterStyles,      ["data", "canonical"]);
}

} // version(unittest)
