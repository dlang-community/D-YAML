module dyaml.testsuite;

import dyaml;
import dyaml.event;

import std.algorithm;
import std.conv;
import std.file;
import std.format;
import std.getopt;
import std.json;
import std.path;
import std.range;
import std.stdio;
import std.string;
import std.typecons;
import std.utf;
import std.uni;

void dumpEventString(string str) @safe
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
        writeln(line);
    }
}
void dumpTokens(string str) @safe
{
    writefln("%(%s\n%)", Loader.fromString(str).parse());
}


void main(string[] args) @system
{
    bool tokens;
    getopt(args,
        "t|tokens", &tokens);
    string str;
    if (args[1] == "-") {
        str = cast(string)(stdin.byChunk(4096).joiner().array);
    } else {
        str = readText(args[1]);
    }
    if (tokens) {
        dumpTokens(str);
    } else {
        dumpEventString(str);
    }
}
