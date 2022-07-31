module dyaml.testsuite;

import dyaml;
import dyaml.event;

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
        auto events = Loader.fromString(str).parse();
        foreach (event; events)
        {
            string line;
            final switch (event.id)
            {
                case EventID.scalar:
                    line = "=VAL ";
                    if (event.anchor != "")
                    {
                        line ~= text("&", event.anchor, " ");
                    }
                    if (event.tag != "")
                    {
                        line ~= text("<", event.tag, "> ");
                    }
                    switch(event.scalarStyle)
                    {
                        case ScalarStyle.singleQuoted:
                            line ~= "'";
                            break;
                        case ScalarStyle.doubleQuoted:
                            line ~= '"';
                            break;
                        case ScalarStyle.literal:
                            line ~= "|";
                            break;
                        case ScalarStyle.folded:
                            line ~= ">";
                            break;
                        default:
                            line ~= ":";
                            break;
                    }
                    if (event.value != "")
                    {
                        line ~= text(event.value.substitute("\n", "\\n", `\`, `\\`, "\r", "\\r", "\t", "\\t", "\b", "\\b"));
                    }
                    break;
                case EventID.streamStart:
                    line = "+STR";
                    break;
                case EventID.documentStart:
                    line = "+DOC";
                    if (event.explicitDocument)
                    {
                        line ~= text(" ---");
                    }
                    break;
                case EventID.mappingStart:
                    line = "+MAP";
                    if (event.collectionStyle == CollectionStyle.flow)
                    {
                        line ~= text(" {}");
                    }
                    if (event.anchor != "")
                    {
                        line ~= text(" &", event.anchor);
                    }
                    if (event.tag != "")
                    {
                        line ~= text(" <", event.tag, ">");
                    }
                    break;
                case EventID.sequenceStart:
                    line = "+SEQ";
                    if (event.collectionStyle == CollectionStyle.flow)
                    {
                        line ~= text(" []");
                    }
                    if (event.anchor != "")
                    {
                        line ~= text(" &", event.anchor);
                    }
                    if (event.tag != "")
                    {
                        line ~= text(" <", event.tag, ">");
                    }
                    break;
                case EventID.streamEnd:
                    line = "-STR";
                    break;
                case EventID.documentEnd:
                    line = "-DOC";
                    if (event.explicitDocument)
                    {
                        line ~= " ...";
                    }
                    break;
                case EventID.mappingEnd:
                    line = "-MAP";
                    break;
                case EventID.sequenceEnd:
                    line = "-SEQ";
                    break;
                case EventID.alias_:
                    line = text("=ALI *", event.anchor);
                    break;
                case EventID.invalid:
                    assert(0, "Invalid EventID produced");
            }
            output ~= line;
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

    const void toString(OutputRange)(ref OutputRange writer)
        if (isOutputRange!(OutputRange, char))
    {
        ubyte statusColour;
        string statusString;
        final switch (state) {
            case TestState.success:
                statusColour = 32;
                statusString = "Succeeded";
                break;
            case TestState.failure:
                statusColour = 31;
                statusString = "Failed";
                break;
            case TestState.skipped:
                statusColour = 93;
                statusString = "Skipped";
                break;
        }
        writer.formattedWrite!"[\033[%s;1m%s\033[0m] %s"(statusColour, statusString, name);
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
        testsRun++;
    }
    if (!loadFailed && !events.isNull && !shouldFail)
    {
        const compare = dumpEventString(yamlString);
        compareLineByLine(compare, events.get, true, "Event mismatch");
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
    foreach (file; dirEntries(path, "*.yaml", SpanMode.shallow))
    {
        auto result = runTests(readText(file));
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
    writefln!"%d/%d tests passed"(successes, total);
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
