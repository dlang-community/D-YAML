
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.emitter;


version(unittest)
{

import std.algorithm;
import std.file;
import std.outbuffer;
import std.range;
import std.typecons;

import dyaml.dumper;
import dyaml.event;
import dyaml.test.common;
import dyaml.token;


/// Determine if events in events1 are equivalent to events in events2.
///
/// Params:  events1 = First event array to compare.
///          events2 = Second event array to compare.
///
/// Returns: true if the events are equivalent, false otherwise.
bool compareEvents(Event[] events1, Event[] events2) @safe
{
    if(events1.length != events2.length){return false;}

    for(uint e; e < events1.length; ++e)
    {
        auto e1 = events1[e];
        auto e2 = events2[e];

        //Different event types.
        if(e1.id != e2.id){return false;}
        //Different anchor (if applicable).
        if([EventID.SequenceStart,
            EventID.MappingStart,
            EventID.Alias,
            EventID.Scalar].canFind(e1.id)
            && e1.anchor != e2.anchor)
        {
            return false;
        }
        //Different collection tag (if applicable).
        if([EventID.SequenceStart, EventID.MappingStart].canFind(e1.id) && e1.tag != e2.tag)
        {
            return false;
        }
        if(e1.id == EventID.Scalar)
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
    auto emitStream = new OutBuffer;
    Dumper!OutBuffer(emitStream).emit(events);

    static if(verbose)
    {
        writeln(dataFilename);
        writeln("ORIGINAL:\n", readText(dataFilename));
        writeln("OUTPUT:\n", emitStream.toString);
    }

    auto loader2        = Loader.fromBuffer(emitStream.toBytes);
    loader2.name        = "TEST";
    loader2.constructor = new Constructor;
    loader2.resolver    = new Resolver;
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
        auto emitStream = new OutBuffer;
        auto dumper = Dumper!OutBuffer(emitStream);
        dumper.canonical = canonical;
        dumper.emit(events);
        static if(verbose)
        {
            writeln("OUTPUT (canonical=", canonical, "):\n",
                    emitStream.toString);
        }
        auto loader2        = Loader.fromBuffer(emitStream.toBytes);
        loader2.name        = "TEST";
        loader2.constructor = new Constructor;
        loader2.resolver    = new Resolver;
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
        foreach(flowStyle; [CollectionStyle.Block, CollectionStyle.Flow])
        {
            foreach(style; [ScalarStyle.Literal, ScalarStyle.Folded,
                            ScalarStyle.DoubleQuoted, ScalarStyle.SingleQuoted,
                            ScalarStyle.Plain])
            {
                Event[] styledEvents;
                foreach(event; events)
                {
                    if(event.id == EventID.Scalar)
                    {
                        event = scalarEvent(Mark(), Mark(), event.anchor, event.tag,
                                            event.implicit,
                                            event.value, style);
                    }
                    else if(event.id == EventID.SequenceStart)
                    {
                        event = sequenceStartEvent(Mark(), Mark(), event.anchor,
                                                   event.tag, event.implicit, flowStyle);
                    }
                    else if(event.id == EventID.MappingStart)
                    {
                        event = mappingStartEvent(Mark(), Mark(), event.anchor,
                                                  event.tag, event.implicit, flowStyle);
                    }
                    styledEvents ~= event;
                }
                auto emitStream = new OutBuffer;
                Dumper!OutBuffer(emitStream).emit(styledEvents);
                static if(verbose)
                {
                    writeln("OUTPUT (", filename, ", ", to!string(flowStyle), ", ",
                            to!string(style), ")");
                    writeln(emitStream.toString);
                }
                auto loader2        = Loader.fromBuffer(emitStream.toBytes);
                loader2.name        = "TEST";
                loader2.constructor = new Constructor;
                loader2.resolver    = new Resolver;
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
