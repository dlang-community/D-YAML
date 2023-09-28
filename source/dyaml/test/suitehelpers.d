
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.suitehelpers;

import dyaml;
import dyaml.emitter;
import dyaml.event;
import dyaml.parser;
import dyaml.reader;
import dyaml.scanner;
import dyaml.token;
import dyaml.test.constructor;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.range;
import std.string;

package version(unittest):

// Like other types, wchar and dchar use the system's endianness, so \uFEFF
// will always be the 'correct' BOM and '\uFFFE' will always be the 'wrong' one
enum wchar[] bom16 = ['\uFEFF', '\uFFFE'];
enum dchar[] bom32 = ['\uFEFF', '\uFFFE'];

Parser parseData(string data, string name = "TEST") @safe
{
    auto reader = Reader(cast(ubyte[])data.dup, name);
    auto scanner = Scanner(reader);
    return new Parser(scanner);
}

/**
Test scanner by scanning a document, expecting no errors.

Params:
    name = Name of the document being scanned
    data = Data to scan.
*/
void testScanner(string name, string data) @safe
{
    ubyte[] yamlData = cast(ubyte[])data.dup;
    string[] tokens;
    foreach (token; Scanner(Reader(yamlData, name)))
    {
        tokens ~= token.id.text;
    }
}

/**
Implicit tag resolution unittest.

Params:
    name = Name of the document being tested
    data = Document to compare
    detectData = The tag that each scalar should resolve to
*/
bool testImplicitResolver(string name, string data, string detectData, out string generatedTags, out string expectedTags) @safe
{
    const correctTag = detectData.strip();

    const node = Loader.fromString(data, name).load();
    if (node.nodeID != NodeID.sequence)
    {
        return false;
    }
    bool success = true;
    foreach (const Node scalar; node)
    {
        generatedTags ~= scalar.tag ~ "\n";
        expectedTags ~= correctTag ~ "\n";
        if ((scalar.nodeID != NodeID.scalar) || (scalar.tag != correctTag))
        {
            success = false;
        }
    }
    return success;
}

// Try to emit an event range.
Event[] emitTestCommon(string name, Event[] events, bool canonical) @safe
{
    auto emitStream = new Appender!string();
    auto emitter = Emitter!(typeof(emitStream), char)(emitStream, canonical, 2, 80, LineBreak.unix);
    foreach (event; events)
    {
        emitter.emit(event);
    }
    return parseData(emitStream.data, name).array;
}
/**
Test emitter by checking if events remain equal after round-tripping, with and
without canonical output enabled.

Params:
    name = Name of the document being tested
    events = Events to test
    results = Events that were produced by round-tripping
*/
bool testEmitter(string name, Event[] events, out Event[][2] results) @safe
{
    bool matching = true;
    foreach (idx, canonicalOutput; [false, true])
    {
        results[idx] = emitTestCommon(name, events, canonicalOutput);

        if (!equal!eventCompare(events, results[idx]))
        {
            matching = false;
        }
    }
    return matching;
}
/**
Test emitter by checking if events remain equal after round-tripping, with all
combinations of styles.

Params:
    name = Name of the document being tested
    events = Events to test
    results = Events that were produced by round-tripping
*/
bool testEmitterStyles(string name, Event[] events, out Event[][2 * 2 * 5] results) @safe
{
    size_t idx;
    foreach (styles; cartesianProduct(
            [CollectionStyle.block, CollectionStyle.flow],
            [ScalarStyle.literal, ScalarStyle.folded,
                ScalarStyle.doubleQuoted, ScalarStyle.singleQuoted,
                ScalarStyle.plain],
            [false, true]))
    {
        const collectionStyle = styles[0];
        const scalarStyle = styles[1];
        const canonical = styles[2];
        Event[] styledEvents;
        foreach (event; events)
        {
            if (event.id == EventID.scalar)
            {
                event = scalarEvent(Mark(), Mark(), event.anchor, event.tag,
                                    event.implicit,
                                    event.value, scalarStyle);
            }
            else if (event.id == EventID.sequenceStart)
            {
                event = sequenceStartEvent(Mark(), Mark(), event.anchor,
                                           event.tag, event.implicit, collectionStyle);
            }
            else if (event.id == EventID.mappingStart)
            {
                event = mappingStartEvent(Mark(), Mark(), event.anchor,
                                          event.tag, event.implicit, collectionStyle);
            }
            styledEvents ~= event;
        }
        auto newEvents = emitTestCommon(name, styledEvents, canonical);
        results[idx++] = newEvents;
        if (!equal!eventCompare(events, newEvents))
        {
            return false;
        }
    }
    return true;
}

/**
Constructor unittest.

Params:
    data = The document being tested
    base = A unique id corresponding to one of the premade sequences in dyaml.test.constructor
*/
bool testConstructor(string data, string base) @safe
{
    assert((base in expected) !is null, "Unimplemented constructor test: " ~ base);
    auto loader = Loader.fromString(data);

    Node[] exp = expected[base];

    //Compare with expected results document by document.
    return equal(loader, exp);
}

bool eventCompare(const Event a, const Event b) @safe pure
{
    //Different event types.
    if (a.id != b.id)
    {
        return false;
    }
    //Different anchor (if applicable).
    if (a.id.among!(EventID.sequenceStart, EventID.mappingStart, EventID.alias_, EventID.scalar)
        && a.anchor != b.anchor)
    {
        return false;
    }
    //Different collection tag (if applicable).
    if (a.id.among!(EventID.sequenceStart, EventID.mappingStart) && a.tag != b.tag)
    {
        return false;
    }
    if (a.id == EventID.scalar)
    {
        //Different scalar tag (if applicable).
        if (!(a.implicit || b.implicit) && a.tag != b.tag)
        {
            return false;
        }
        //Different scalar value.
        if (a.value != b.value)
        {
            return false;
        }
    }
    return true;
}
