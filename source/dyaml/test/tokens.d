
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.test.tokens;


version(unittest)
{

import std.array;
import std.file;

import dyaml.test.common;
import dyaml.token;


/**
 * Test tokens output by scanner.
 *
 * Params:  verbose        = Print verbose output?
 *          dataFilename   = File to scan.
 *          tokensFilename = File containing expected tokens.
 */
void testTokens(bool verbose, string dataFilename, string tokensFilename) @safe
{
    //representations of YAML tokens in tokens file.
    auto replace = [TokenID.Directive          : "%"   ,
                    TokenID.DocumentStart      : "---" ,
                    TokenID.DocumentEnd        : "..." ,
                    TokenID.Alias              : "*"   ,
                    TokenID.Anchor             : "&"   ,
                    TokenID.Tag                : "!"   ,
                    TokenID.Scalar             : "_"   ,
                    TokenID.BlockSequenceStart : "[["  ,
                    TokenID.BlockMappingStart  : "{{"  ,
                    TokenID.BlockEnd           : "]}"  ,
                    TokenID.FlowSequenceStart  : "["   ,
                    TokenID.FlowSequenceEnd    : "]"   ,
                    TokenID.FlowMappingStart   : "{"   ,
                    TokenID.FlowMappingEnd     : "}"   ,
                    TokenID.BlockEntry         : ","   ,
                    TokenID.FlowEntry          : ","   ,
                    TokenID.Key                : "?"   ,
                    TokenID.Value              : ":"   ];

    string[] tokens1;
    string[] tokens2 = readText(tokensFilename).split();
    scope(exit)
    {
        if(verbose){writeln("tokens1: ", tokens1, "\ntokens2: ", tokens2);}
    }

    auto loader = Loader(dataFilename);
    foreach(token; loader.scan())
    {
        if(token.id != TokenID.StreamStart && token.id != TokenID.StreamEnd)
        {
            tokens1 ~= replace[token.id];
        }
    }

    assert(tokens1 == tokens2);
}

/**
 * Test scanner by scanning a file, expecting no errors.
 *
 * Params:  verbose           = Print verbose output?
 *          dataFilename      = File to scan.
 *          canonicalFilename = Another file to scan, in canonical YAML format.
 */
void testScanner(bool verbose, string dataFilename, string canonicalFilename) @safe
{
    foreach(filename; [dataFilename, canonicalFilename])
    {
        string[] tokens;
        scope(exit)
        {
            if(verbose){writeln(tokens);}
        }
        auto loader = Loader(filename);
        foreach(ref token; loader.scan()){tokens ~= to!string(token.id);}
    }
}

@safe unittest
{
    writeln("D:YAML tokens unittest");
    run("testTokens",  &testTokens, ["data", "tokens"]);
    run("testScanner", &testScanner, ["data", "canonical"]);
}

} // version(unittest)
