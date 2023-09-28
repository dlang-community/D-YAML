module dyaml.test.suite;

import std.algorithm;
import std.conv;
import std.datetime.stopwatch;
import std.exception;
import std.file;
import std.format;
import std.meta;
import std.path;
import std.range;
import std.stdio;
import std.string;
import std.typecons;
import dyaml;
import dyaml.event;
import dyaml.parser;
import dyaml.reader;
import dyaml.scanner;
import dyaml.test.suitehelpers;

private version(unittest):

debug(verbose)
{
    enum alwaysPrintTestResults = true;
}
else
{
    enum alwaysPrintTestResults = false;
}

struct TestResult {
    string name;
    Nullable!bool emitter;
    Nullable!bool constructor;
    Nullable!bool loaderError;
    Nullable!bool mark1Error;
    Nullable!bool mark2Error;
    Nullable!bool implicitResolver;
    Nullable!bool events;
    Nullable!bool specificLoaderError;
    Nullable!Mark mark1;
    Nullable!Mark mark2;
    Event[] parsedData;
    Event[][2 * 2 * 5] parsedDataResult;
    Node[] loadedData;
    Exception nonDYAMLException;
    MarkedYAMLException exception;
    string eventsExpected;
    string eventsGenerated;
    string generatedLoadErrorMessage;
    string expectedLoadErrorMessage;
    string expectedTags;
    string generatedTags;
}

/// Pretty-print the differences between two arrays
auto prettyDifferencePrinter(alias eqPred = (a,b) => a == b, T)(string title, T[] expected, T[] got, bool trimWhitespace = false) @safe
{
    struct Result
    {
        void foo() {
            toString(nullSink);
        }
        void toString(W)(ref W writer) const
        {
            import std.format : formattedWrite;
            import std.range : put;
            import std.string : lineSplitter;
            size_t minWidth = 10;
            foreach (line; chain(expected, got))
            {
                if (line.text.length + 1 > minWidth)
                {
                    minWidth = line.text.length + 1;
                }
            }
            void writeSideBySide(ubyte colour, string a, string b)
            {
                if (trimWhitespace)
                {
                    a = strip(a);
                    b = strip(b);
                }
                writer.formattedWrite!"%s%-(%s%)%s"(colourPrinter(colour, a), " ".repeat(minWidth - a.length), colourPrinter(colour, b));
            }
            writefln!"%-(%s%)%s%-(%s%)"("=".repeat(max(0, minWidth * 2 - title.length) / 2), title, "=".repeat(max(0, minWidth * 2 - title.length) / 2));
            writeSideBySide(0, "Expected", "Got");
            put(writer, "\n");
            foreach (line1, line2; zip(StoppingPolicy.longest, expected, got))
            {
                static if (is(T : const char[]))
                {
                    if (trimWhitespace)
                    {
                        line1 = strip(line1);
                        line2 = strip(line2);
                    }
                }
                ubyte colour = (eqPred(line1, line2)) ? 32 : 31;
                writeSideBySide(colour, line1.text, line2.text);
                put(writer, "\n");
            }
        }
    }
    return Result();
}

/**
Run a single test from the test suite.
Params:
    name = The filename of the document to load, containing the test data
*/
TestResult runTest(string name, Node doc) @safe
{
    TestResult result;
    string[string] testData;
    void tryLoadTestData(string what)
    {
        if (what in doc)
        {
            testData[what] = doc[what].as!string;
            doc.removeAt(what);
        }
    }
    string yamlPath(string testName, string section)
    {
        return format!"%s:%s"(testName, section);
    }
    tryLoadTestData("name");
    result.name = name~"#"~testData.get("name", "UNNAMED");
    Nullable!Mark getMark(string key)
    {
        if (auto node = key in doc)
        {
            Mark mark;
            if ("name" in *node)
            {
                mark.name = (*node)["name"].as!string;
            }
            else // default to the test name
            {
                // if we ever have multiple yaml blocks to parse, be sure to change this
                mark.name = yamlPath(result.name, "yaml");
            }
            if ("line" in *node)
            {
                mark.line = cast(ushort)((*node)["line"].as!ushort - 1);
            }
            if ("column" in *node)
            {
                mark.column = cast(ushort)((*node)["column"].as!ushort - 1);
            }
            return Nullable!Mark(mark);
        }
        return Nullable!Mark.init;
    }
    tryLoadTestData("tags");
    tryLoadTestData("from");
    tryLoadTestData("yaml");
    tryLoadTestData("fail");
    tryLoadTestData("json"); //not yet implemented
    tryLoadTestData("dump"); //not yet implemented
    tryLoadTestData("detect");
    tryLoadTestData("tree");
    tryLoadTestData("error");
    tryLoadTestData("code");
    assert("yaml" in testData);
    {
        result.expectedLoadErrorMessage = testData.get("error", "");
        result.mark1 = getMark("mark");
        result.mark2 = getMark("mark2");
        try
        {
            result.parsedData = parseData(testData["yaml"], yamlPath(result.name, "yaml")).array;
            result.loadedData = Loader.fromString(testData["yaml"], yamlPath(result.name, "yaml")).array;
            result.emitter = testEmitterStyles(yamlPath(result.name, "canonical"), result.parsedData, result.parsedDataResult);
            result.mark1Error = result.mark1.isNull;
            result.mark2Error = result.mark2.isNull;
        }
        catch (MarkedYAMLException e)
        {
            result.exception = e;
            result.generatedLoadErrorMessage = e.msg;
            result.mark1Error = !result.mark1.isNull && (result.mark1.get() == e.mark);
            result.mark2Error = result.mark2 == e.mark2;
            if (testData.get("fail", "false") == "false")
            {
                result.loaderError = false;
            }
            else
            {
                result.loaderError = true;
            }
        }
        catch (Exception e)
        {
            // all non-DYAML exceptions are failures.
            result.nonDYAMLException = e;
            result.generatedLoadErrorMessage = e.msg;
            result.loaderError = false;
        }
        result.specificLoaderError = strip(result.generatedLoadErrorMessage) == strip(result.expectedLoadErrorMessage);
    }
    if (result.loaderError.get(false))
    {
        // skip other tests if loading failure was expected, because we don't
        // have a way to run them yet
        return result;
    }
    if ("tree" in testData)
    {
        result.eventsGenerated = result.parsedData.map!(x => strip(x.text)).join("\n");
        result.eventsExpected = testData["tree"].lineSplitter.map!(x => strip(x)).join("\n");
        result.events = result.eventsGenerated == result.eventsExpected;
    }
    if ("code" in testData)
    {
        result.constructor = testConstructor(testData["yaml"], testData["code"]);
    }
    if ("detect" in testData)
    {
        result.implicitResolver = testImplicitResolver(yamlPath(result.name, "yaml"), testData["yaml"], testData["detect"], result.generatedTags, result.expectedTags);
    }
    foreach (string remaining, Node _; doc)
    {
        writeln("Warning: Unhandled section '", remaining, "' in ", result.name);
    }
    return result;
}

enum goodColour = 32;
enum badColour = 31;
/**
Print something to the console in colour.
Params:
    colour = The id of the colour to print, using the 256-colour palette
    data = Something to print
*/
private auto colourPrinter(T)(ubyte colour, T data) @safe pure
{
    struct Printer
    {
        void toString(S)(ref S sink)
        {
            sink.formattedWrite!"\033[%s;1m%s\033[0m"(colour, data);
        }
    }
    return Printer();
}

/**
Run all tests in the test suite and print relevant results. The test docs are
all found in the ./test/data dir.
*/
bool runTests()
{
    auto stopWatch = StopWatch(AutoStart.yes);
    bool failed;
    uint testsRun, testSetsRun, testsFailed;
    foreach (string name; dirEntries(buildNormalizedPath("test"), "*.yaml", SpanMode.depth)/*.chain(dirEntries(buildNormalizedPath("yaml-test-suite/src"), "*.yaml", SpanMode.depth))*/)
    {
        Node doc;
        try
        {
            doc = Loader.fromFile(name).load();
        }
        catch (Exception e)
        {
            writefln!"[%s] %s"(colourPrinter(badColour, "FAIL"), name);
            writeln(colourPrinter(badColour, e));
            assert(0, "Could not load test doc '"~name~"', bailing");
        }
        assert (doc.nodeID == NodeID.sequence, name~"'s root node is not a sequence!");
        foreach (Node test; doc)
        {
            testSetsRun++;
            bool resultPrinted;
            // make sure the paths are normalized on windows by replacing backslashes with slashes
            TestResult result = runTest(name.replace("\\", "/"), test);
            void printResult(string label, Nullable!bool value)
            {
                if (!value.isNull)
                {
                    if (!value.get)
                    {
                        testsFailed++;
                    }
                    testsRun++;
                }
                if (alwaysPrintTestResults && value.get(false))
                {
                    resultPrinted = true;
                    writef!"[%s]"(colourPrinter(goodColour, label));
                }
                else if (!value.get(true))
                {
                    resultPrinted = true;
                    failed = true;
                    writef!"[%s]"(colourPrinter(badColour, label));
                }
            }
            printResult("Emitter", result.emitter);
            printResult("Constructor", result.constructor);
            printResult("Mark", result.mark1Error);
            printResult("Context mark", result.mark2Error);
            printResult("LoaderError", result.loaderError);
            printResult("Resolver", result.implicitResolver);
            printResult("Events", result.events);
            printResult("SpecificLoaderError", result.specificLoaderError);
            if (resultPrinted)
            {
                writeln(" ", result.name);
            }
            if (!result.loaderError.get(true))
            {
                if (result.exception is null && result.nonDYAMLException is null)
                {
                    writeln("\tNo Exception thrown");
                }
                else if (result.nonDYAMLException !is null)
                {
                    writeln(result.nonDYAMLException);
                }
                else if (result.exception !is null)
                {
                    writeln(result.exception);
                }
            }
            else
            {
                if (!result.mark1Error.get(true))
                {
                    writeln(prettyDifferencePrinter("Mark mismatch", [result.mark1.text], [result.exception.mark.text]));
                }
                if (!result.mark2Error.get(true))
                {
                    writeln(prettyDifferencePrinter("Context mark mismatch", [result.mark2.text], [result.exception.mark2.text]));
                }
            }
            if (!result.emitter.get(true))
            {
                enum titles = [ "Normal", "Canonical" ];
                enum styleTitles =
                [
                    "Block literal", "Block folded", "Block double-quoted", "Block single-quoted", "Block plain",
                    "Flow literal", "Flow folded", "Flow double-quoted", "Flow single-quoted", "Flow plain",
                    "Block literal", "Block folded", "Block double-quoted", "Block single-quoted", "Block plain",
                    "Flow literal", "Flow folded", "Flow double-quoted", "Flow single-quoted", "Flow plain",
                ];
                foreach (idx, parsed; result.parsedDataResult)
                {
                    writeln(prettyDifferencePrinter!eventCompare(styleTitles[idx], result.parsedData, parsed));
                }
            }
            if (!result.events.get(true))
            {
                writeln(prettyDifferencePrinter("Events", result.eventsExpected.splitLines, result.eventsGenerated.splitLines, true));
            }
            if (!result.specificLoaderError.get(true))
            {
                writeln(prettyDifferencePrinter("Expected error", result.expectedLoadErrorMessage.splitLines, result.generatedLoadErrorMessage.splitLines));
            }
            if (!result.implicitResolver.get(true))
            {
                writeln(prettyDifferencePrinter("Expected error", result.expectedTags.splitLines, result.generatedTags.splitLines));
            }
        }
    }
    if (alwaysPrintTestResults || failed)
    {
        if (testsFailed > 0)
        {
            writeln(colourPrinter(badColour, "tests failed: "), testsFailed);
        }
        writeln(testSetsRun, " test sets (", testsRun, " tests total) completed successfully in ", stopWatch.peek());
    }
    return failed;
}

unittest {
    assert(!runTests());
}
