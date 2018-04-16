
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

import dyaml.stream;
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
bool compareEvents(Event[] events1, Event[] events2) @system
{
    if(events1.length != events2.length){return false;}

    for(uint e = 0; e < events1.length; ++e)
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
            if(![e1.implicit, e1.implicit_2, e2.implicit, e2.implicit_2].canFind(true)
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
void testEmitterOnData(string dataFilename, string canonicalFilename) @system
{
    //Must exist due to Anchor, Tags reference counts.
    auto loader = Loader(dataFilename);
    auto events = cast(Event[])loader.parse();
    auto emitStream = new YMemoryStream;
    Dumper(emitStream).emit(events);

    static if(verbose)
    {
        writeln(dataFilename);
        writeln("ORIGINAL:\n", readText(dataFilename));
        writeln("OUTPUT:\n", cast(string)emitStream.data);
    }

    auto loader2        = Loader(emitStream.data.dup);
    loader2.name        = "TEST";
    loader2.constructor = new Constructor;
    loader2.resolver    = new Resolver;
    auto newEvents = cast(Event[])loader2.parse();
    assert(compareEvents(events, newEvents));
}

/// Test emitter by getting events from parsing a canonical YAML file, emitting
/// them both in canonical and normal format, parsing the emitted results and
/// comparing events from parsing the emitted result with originally parsed events.
///
/// Params:  canonicalFilename = Canonical YAML file to parse.
void testEmitterOnCanonical(string canonicalFilename) @system
{
    //Must exist due to Anchor, Tags reference counts.
    auto loader = Loader(canonicalFilename);
    auto events = cast(Event[])loader.parse();
    foreach(canonical; [false, true])
    {
        auto emitStream = new YMemoryStream;
        auto dumper = Dumper(emitStream);
        dumper.canonical = canonical;
        dumper.emit(events);
        static if(verbose)
        {
            writeln("OUTPUT (canonical=", canonical, "):\n",
                    cast(string)emitStream.data);
        }
        auto loader2        = Loader(emitStream.data.dup);
        loader2.name        = "TEST";
        loader2.constructor = new Constructor;
        loader2.resolver    = new Resolver;
        auto newEvents = cast(Event[])loader2.parse();
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
void testEmitterStyles(string dataFilename, string canonicalFilename) @system
{
    foreach(filename; [dataFilename, canonicalFilename])
    {
        //must exist due to Anchor, Tags reference counts
        auto loader = Loader(canonicalFilename);
        auto events = cast(Event[])loader.parse();
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
                                            tuple(event.implicit, event.implicit_2),
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
                auto emitStream = new YMemoryStream;
                Dumper(emitStream).emit(styledEvents);
                static if(verbose)
                {
                    writeln("OUTPUT (", filename, ", ", to!string(flowStyle), ", ",
                            to!string(style), ")");
                    writeln(emitStream.data);
                }
                auto loader2        = Loader(emitStream.data.dup);
                loader2.name        = "TEST";
                loader2.constructor = new Constructor;
                loader2.resolver    = new Resolver;
                auto newEvents = cast(Event[])loader2.parse();
                assert(compareEvents(events, newEvents));
            }
        }
    }
}

@system unittest
{
    writeln("D:YAML Emitter unittest");
    run("testEmitterOnData",      &testEmitterOnData,      ["data", "canonical"]);
    run("testEmitterOnCanonical", &testEmitterOnCanonical, ["canonical"]);
    run("testEmitterStyles",      &testEmitterStyles,      ["data", "canonical"]);
}

} // version(unittest)
