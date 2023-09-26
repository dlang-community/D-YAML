module dyaml.testsuite;

import dyaml;
import dyaml.event;
import dyaml.parser;
import dyaml.reader;
import dyaml.scanner;

import std.algorithm;
import std.conv;
import std.file;
import std.format;
import std.json;
import std.path;
import std.range;
import std.stdio;
import std.string;
import std.typecons;
import std.utf;
import std.uni;

auto dumpEventString(string str) @safe
{
    string[] output;
    try
    {
        auto events = new Parser(Scanner(Reader(cast(ubyte[])str.dup)));
        foreach (event; events)
        {
            output ~= event.text;
        }
    }
    catch (Exception) {} //Exceptions should just stop adding output
    return output.join("\n");
}

enum TestState
{
    success,
    skipped,
    failure
}

struct TestResult
{
    string name;
    TestState state;
    string failMsg;
    bool parserFailure;
    bool dumperFailure;
    bool composerFailure;

    const void toString(OutputRange)(ref OutputRange writer)
        if (isOutputRange!(OutputRange, char))
    {
        enum goodColour = 32;
        enum badColour = 31;
        enum skipColour = 93;
        ubyte statusColour;
        string statusString;
        final switch (state) {
            case TestState.success:
                statusColour = goodColour;
                statusString = "Succeeded";
                break;
            case TestState.failure:
                statusColour = badColour;
                statusString = "Failed";
                break;
            case TestState.skipped:
                statusColour = skipColour;
                statusString = "Skipped";
                break;
        }
        writer.formattedWrite!"[\033[%s;1m%s\033[0m]"(statusColour, statusString);
        writer.formattedWrite!" [\033[%s;1mP\033[0m"(parserFailure ? badColour : goodColour);
        writer.formattedWrite!"\033[%s;1mD\033[0m"(dumperFailure ? badColour : goodColour);
        writer.formattedWrite!"\033[%s;1mC\033[0m] "(composerFailure ? badColour : goodColour);
        put(writer, name);
        if (state != TestState.success)
        {
            writer.formattedWrite!" (%s)"(failMsg.replace("\n", " "));
        }
    }
}

TestResult runTests(string yaml) @safe
{
    TestResult output;
    output.state = TestState.success;
    auto testDoc = Loader.fromString(yaml).load();
    output.name = testDoc[0]["name"].as!string;
    bool loadFailed, shouldFail;
    string failMsg;
    JSONValue json;
    Node[] nodes;
    string yamlString;
    Nullable!string compareYAMLString;
    Nullable!string events;
    ulong testsRun;

    void fail(string msg) @safe
    {
        output.state = TestState.failure;
        output.failMsg = msg;
    }
    void skip(string msg) @safe
    {
        output.state = TestState.skipped;
        output.failMsg = msg;
    }
    void parseYAML(string yaml) @safe
    {
        yamlString = yaml;
        try {
            nodes = Loader.fromString(yamlString).array;
        }
        catch (Exception e)
        {
            loadFailed = true;
            output.composerFailure = true;
            failMsg = e.msg;
        }
    }
    void compareLineByLine(const string a, const string b, bool skipWhitespace, const string msg) @safe
    {
        foreach (line1, line2; zip(a.lineSplitter, b.lineSplitter))
        {
            if (skipWhitespace)
            {
                line1.skipOver!isWhite;
                line2.skipOver!isWhite;
            }
            if (line1 != line2)
            {
                fail(text(msg, " Got ", line1, ", expected ", line2));
                break;
            }
        }
    }
    foreach (Node test; testDoc)
    {
        if ("yaml" in test)
        {
            parseYAML(cleanup(test["yaml"].as!string));
        }
        if ("json" in test)
        {
            json = parseJSON(test["json"].as!string);
        }
        if ("tree" in test)
        {
            events = cleanup(test["tree"].as!string);
        }
        if ("fail" in test)
        {
            shouldFail = test["fail"].as!bool;
            if (shouldFail)
            {
                testsRun++;
            }
        }
        if ("emit" in test)
        {
            compareYAMLString = test["emit"].as!string;
        }
    }
    if (!loadFailed && !compareYAMLString.isNull && !shouldFail)
    {
        Appender!string buf;
        dumper().dump(buf);
        compareLineByLine(buf.data, compareYAMLString.get, false, "Dumped YAML mismatch");
        output.dumperFailure = output.state == TestState.failure;
        testsRun++;
    }
    if (!loadFailed && !events.isNull && !shouldFail)
    {
        const compare = dumpEventString(yamlString);
        compareLineByLine(compare, events.get, true, "Event mismatch");
        output.parserFailure = output.state == TestState.failure;
        testsRun++;
    }
    if (loadFailed && !shouldFail)
    {
        fail(failMsg);
    }
    if (shouldFail && !loadFailed)
    {
        fail("Invalid YAML accepted");
    }
    if ((testsRun == 0) && (output.state != TestState.failure))
    {
        skip("No tests run");
    }
    return output;
}

// Can't be @safe due to dirEntries()
void main(string[] args) @system
{
    string path = "yaml-test-suite/src";

    void printResult(string id, TestResult result)
    {
        writeln(id, " ", result);
    }

    if (args.length > 1)
    {
        path = args[1];
    }

    ulong total;
    ulong successes;
    ulong parserFails;
    ulong dumperFails;
    foreach (file; dirEntries(path, "*.yaml", SpanMode.shallow))
    {
        auto result = runTests(readText(file));
        dumperFails += result.dumperFailure;
        parserFails += result.parserFailure;
        if (result.state == TestState.success)
        {
            debug(verbose) printResult(file.baseName, result);
            successes++;
        }
        else
        {
            printResult(file.baseName, result);
        }
        total++;
    }
    writefln!"Tests: %d/%d passed"(successes, total);
    writefln!"Parser: %d/%d passed"(total - parserFails, total);
    writefln!"Dumper: %d/%d passed"(total - dumperFails, total);
}

string cleanup(string input) @safe
{
    return input.substitute(
        "␣", " ",
        "————»", "\t",
        "———»", "\t",
        "——»", "\t",
        "—»", "\t",
        "»", "\t",
        "↵", "\n",
        "∎", "",
        "←", "\r",
        "⇔", "\uFEFF"
    ).toUTF8;
}
