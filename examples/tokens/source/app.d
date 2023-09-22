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
    auto events = new Parser(Scanner(Reader(cast(ubyte[])str.dup)));
    foreach (event; events)
    {
        writeln(event);
    }
}
void dumpTokens(string str) @safe
{
    writefln("%(%s\n%)", new Parser(Scanner(Reader(cast(ubyte[])str.dup))));
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
