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

TestResult runTests(string tml) @safe
{
    TestResult output;
    output.state = TestState.success;
    auto splitFile = tml.splitter("\n--- ");
    output.name = splitFile.front.findSplit("=== ")[2];
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
    void compareLineByLine(const string a, const string b, const string msg) @safe
    {
        foreach (line1, line2; zip(a.lineSplitter, b.lineSplitter))
        {
            if (line1 != line2)
            {
                fail(text(msg, " Got ", line1, ", expected ", line2));
                break;
            }
        }
    }
    foreach (section; splitFile.drop(1))
    {
        auto splitSection = section.findSplit("\n");
        auto splitSectionHeader = splitSection[0].findSplit(":");
        const splitSectionName = splitSectionHeader[0].findSplit("(");
        const sectionName = splitSectionName[0];
        const sectionParams = splitSectionName[2].findSplit(")")[0];
        string sectionData = splitSection[2];
        if (sectionData != "")
        {
            //< means dedent.
            if (sectionParams.canFind("<"))
            {
                sectionData = sectionData[4..$].substitute("\n    ", "\n", "<SPC>", " ", "<TAB>", "\t").toUTF8;
            }
            else
            {
                sectionData = sectionData.substitute("<SPC>", " ", "<TAB>", "\t").toUTF8;
            }
            //Not sure what + means.
        }
        switch(sectionName)
        {
            case "in-yaml":
                parseYAML(sectionData);
                break;
            case "in-json":
                json = parseJSON(sectionData);
                break;
            case "test-event":
                events = sectionData;
                break;
            case "error":
                shouldFail = true;
                testsRun++;
                break;
            case "out-yaml":
                compareYAMLString = sectionData;
                break;
            case "emit-yaml":
                // TODO: Figure out how/if to implement this
                //fail("Unhandled test - emit-yaml");
                break;
            case "lex-token":
                // TODO: Should this be implemented?
                //fail("Unhandled test - lex-token");
                break;
            case "from": break;
            case "tags": break;
            default: assert(false, text("Unhandled section ", sectionName, "in ", output.name));
        }
    }
    if (!loadFailed && !compareYAMLString.isNull && !shouldFail)
    {
        Appender!string buf;
        dumper().dump(buf);
        compareLineByLine(buf.data, compareYAMLString, "Dumped YAML mismatch");
        testsRun++;
    }
    if (!loadFailed && !events.isNull && !shouldFail)
    {
        const compare = dumpEventString(yamlString);
        compareLineByLine(compare, events, "Event mismatch");
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
    string path = "yaml-test-suite/test";

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
    foreach (file; dirEntries(path, "*.tml", SpanMode.shallow))
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
