#!/usr/bin/rdmd

/**
 * License: Boost 1.0
 *
 * Copyright (c) 2009-2010 Eric Poggel, Changes 2011 Ferdinand Majerech
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * Description:
 *
 * This is a D programming language build script (and library) that can be used
 * to compile D (version 1) source code.  Unlike Bud, DSSS/Rebuild, Jake, and
 * similar tools, CDC is contained within a single file that can easily be
 * distributed with projects.  This simplifies the build process since no other
 * tools are required.  The main() function can be utilized to turn
 * CDC into a custom build script for your project.
 *
 * CDC's only requirement is a D compiler. It is/will be supported on any 
 * operating system supported by the language. It works with dmd, ldc (soon), 
 * and gdc.
 *
 * CDC can be used just like dmd, except for the following improvements.
 * <ul>
 *   <li>CDC can accept paths as as well as individual source files for compilation.
 *    Each path is recursively searched for source, library, object, and ddoc files.</li>
 *   <li>CDC automatically creates a modules.ddoc file for use with CandyDoc and
 *    similar documentation utilities.</li>
 *   <li>CDC defaults to use the compiler that was used to build itself. Compiler
 *    flags are passed straight through to that compiler.</li>
 *   <li>The -op flag is always used, to prevent name conflicts in object and doc files.</li>
 *   <li>Documentation files are all placed in the same folder with their full package
 *    names. This makes relative links between documents easier.</li>
 * </ul>

 * These DMD/LDC options are automatically translated to the correct GDC
 * options, or handled manually:
 * <dl>
 * <dt>-c</dt>         <dd>do not link</dd>
 * <dt>-D</dt>         <dd>generate documentation</dd>
 * <dt>-Dddocdir</dt>  <dd>write fully-qualified documentation files to docdir directory</dd>
 * <dt>-Dfdocfile</dt> <dd>write fully-qualified documentation files to docfile file</dd>
 * <dt>-lib</dt>       <dd>Generate library rather than object files</dd>
 * <dt>-Ipath</dt>     <dd>where to look for imports</dd>
 * <dt>-o-</dt>        <dd>do not write object file.</dd>
 * <dt>-offilename</dt><dd>name output file to filename</dd>
 * <dt>-odobjdir</dt>  <dd>write object & library files to directory objdir</dd>
 * </dl>
 *
 * In addition, these optional flags have been added.
 * <dl>
 * <dt>--dmd</dt>       <dd>Use dmd to compile</dd>
 * <dt>--gdc</dt>       <dd>Use gdc to compile</dd>
 * <dt>--ldc</dt>       <dd>Use ldc to compile</dd>
 * </dl>
 *
 * Bugs:
 * <ul>
 * <li>Doesn't yet work with LDC.  See dsource.org/projects/ldc/ticket/323</li>
 * <li>Dmd writes out object files as foo/bar.o, while gdc writes foo.bar.o</li>
 * <li>Dmd fails to write object files when -od is an absolute path.</li>
 * </ul>
 *
 * TODO:
 * <ul>
 * <li>Add support for a --script argument to accept another .d file that calls cdc's functions.</li>
 * <li>-Df option</li>
 * <li>GDC - Remove dependancy on "ar" on windows? </li>
 * <li>LDC - Scanning a folder for files is broken. </li>
 * <li>Unittests</li>
 * <li>More testing on paths with spaces. </li>
 * </ul>
 *
 * API:
 * Use any of these functions in your own build script.
 */


import core.stdc.stdlib;

import std.algorithm;
import std.array;
import std.exception;
import std.conv;
import std.file;
import std.path;
import std.process;
import std.range;
import std.string;
import std.stdio : writeln;

alias std.process.system system;


///Name of the default compiler, which is the compiler used to build cdc.
version(DigitalMars){string compiler = "dmd";}
version(GNU){string compiler = "gdmd";}
version(LDC){string compiler = "ldmd2";}

version(Windows)
{   
    ///Valid object file extensions. 
    const string[] obj_ext = ["obj", "o"]; 
    ///Library extension.
    const string lib_ext = "lib";
    ///Binary executable extension.
    const string bin_ext = "exe";
    ///Path separator character.
    char file_separator ='\\';
}
else
{    
    ///Valid object file extensions. 
    const string[] obj_ext = ["o"];
    ///Library extension.
    const string lib_ext = "a";
    ///Binary executable extension.
    const string bin_ext = "";
    ///Path separator character.
    char file_separator ='/';
}

void main(string[] args)
{
    scope(failure){help(); core.stdc.stdlib.exit(-1);}

    string[] targets;
    string[] extra_args = ["-w", "-wi"];

    args = args[1 .. $];
    foreach(arg; args)
    {
        if(arg[0] == '-') switch(arg)
        {
            case "--help", "-h": help(); return;
            case "--dmd": compiler = "dmd"; break;
            case "--gdc": compiler = "gdmd"; break;
            case "--ldc": compiler = "ldmd2"; break;
            default: extra_args ~= arg;
        }
        else
        {
            targets ~= arg;
        }
    }

    if(targets.length == 0){targets = ["release"];}

    auto dbg      = ["-debug", "-gc"];
    auto optimize = ["-O", "-inline", "-release", "-noboundscheck"];
    auto profile  = ["-O", "-release", "-noboundscheck", "-gc"];
    auto lib_src  = ["source"];

    void compile_(string[] args, string[] files)
    {
        compile(args ~ extra_args, files);
    }

    void build_unittest()
    {
        writeln("building unittests");
        compile_(dbg ~ ["-unittest", "-ofunittest"], lib_src ~ "unittest.d" ~ "test/src");
    }

    void build_debug()
    {
        writeln("building debug target");
        compile_(dbg ~ ["-oflibdyaml-debug", "-lib"], lib_src);
    }

    void build_release()
    {
        writeln("building release target");
        compile_(optimize ~ ["-oflibdyaml", "-lib"], lib_src);
    }

    void build_profile()
    {
        writeln("building profile target");
        compile_(profile ~ ["-oflibdyaml", "-lib"], lib_src);
    }

    void build_tar_gz()
    {
        if(system("git archive HEAD | gzip -9v  > dyaml.tar.gz") != 0)
        {
            writeln("Error creating a tar.gz package.");
        }
    }

    void build_tar_xz()
    {
        if(system("git archive HEAD | xz -9ev > dyaml.tar.xz ") != 0)
        {
            writeln("Error creating a tar.xz package.");
        }
    }

    void build_zip()
    {
        if(system("git archive -odyaml.zip -9 HEAD") != 0)
        {
            writeln("Error creating a zip package");
        }
    }
 
    void build(string[] targets ...)
    {
        foreach(target; targets) switch(target)
        {
            case "debug":    build_debug();    break;
            case "release":  build_release();  break;
            case "profile":  build_profile();  break;
            case "unittest": build_unittest(); break;
            case "tar.gz":   build_tar_gz();   break;
            case "tar.xz":   build_tar_xz();   break;
            case "zip":      build_zip();      break;
            case "all":      build("debug", "release", "unittest"); break;
            default:
                writeln("unknown build target: ", target);
                writeln("available targets: 'debug', 'release', 'profile', 'all'");
        }
    }

    try{build(targets);}
    catch(CompileException e){writeln("Could not compile: " ~ e.msg);}
    catch(ProcessException e){writeln("Compilation failed: " ~ e.msg);}

    writeln("DONE");
}

///Print help information.
void help()
{
    string help =
        "D:YAML build script\n"
        "Changes Copyright (C) 2011 Ferdinand Majerech\n"
        "Based on CDC script Copyright (C) 2009-2010 Eric Poggel\n"
        "Usage: cdc [OPTION ...] [EXTRA COMPILER OPTION ...] [TARGET ...]\n"
        "By default, cdc uses the compiler it was built with to compile the project.\n"
        "\n"
        "Any options starting with '-' not parsed by the script will be\n"
        "passed to the compiler used.\n"
        "\n"
        "Optionally, build target can be specified, 'debug' is default.\n"
        "Available build targets:\n"
        "    unittest        Build unit tests.\n"
        "    debug           Debug information, unittests, contracts built in.\n"
        "                    No optimizations.\n"
        "    release         No debug information, no unittests, contracts.\n"
        "                    Optimizations, inlining enabled.\n"
        "    profile         Debug information, no unittests, contracts.\n"
        "                    Optimizations, inlining enabled.\n"
        "    all             Unittest, debug and release.\n"
        "    tar.gz          Needs git, gzip: Create a tar.gz package.\n"
        "    tar.xz          Needs git, xz: Create a tar.xz package.\n"
        "    zip             Needs zip: Create a zip package.\n"
        "\n"
        "Available options:\n"
        " -h --help          Show this help information.\n"
        "    --gdc           Use GDC for compilation.\n"
        "    --dmd           Use DMD for compilation.\n"
        "    --ldc           Use LDC for compilation. (not tested)\n"
        ;
    writeln(help);
}

/**
 * Compile D code using the current compiler.
 *
 * Params:  options = Compiler options.
 *          paths   = Source and library files/directories. Directories are recursively searched. 
 *
 * Example:
 * --------
 * //Compile all source files in src/core along with src/main.d, 
 * //link with all library files in the libs folder
 * //and generate documentation in the docs folder.
 * compile(["src/core", "src/main.d", "libs"], ["-D", "-Dddocs"]);
 * --------
 *
 * TODO Add a dry run option to just return an array of commands to execute. 
 */
void compile(string[] options, string[] paths)
{    
    //Convert src and lib paths to files
    string[] sources, libs, ddocs;
    foreach(src; paths)
    {
        enforceEx!CompileException(exists(src), 
                  "Source file/folder \"" ~ src ~ "\" does not exist.");
        //Directory of source or lib files 
        if(isDir(src))
        {    
            sources ~= scan(src, ".d");
            ddocs   ~= scan(src, ".ddoc");
            libs    ~= scan(src, lib_ext);
        } 
        //File
        else if(isFile(src))
        {
            string ext = src.extension();
            if(ext == ".d"){sources ~= src;}
            else if(ext == lib_ext){libs ~= src;}
        }
    }

    //Add dl.a for dynamic linking on linux
    version(linux){libs ~= ["-L-ldl"];}

    //Combine all options, sources, ddocs, and libs
    CompileOptions co = CompileOptions(options, sources);
    options = co.get_options(compiler);

    if(compiler == "gdc")
    {
        foreach(ref d; ddocs){d = "-fdoc-inc=" ~ d;}
        //or should this only be version(Windows) ?
        //TODO: Check in dmd and gdc 
        foreach(ref l; libs){l = "-L" ~ l;}
    }

    //Create modules.ddoc and add it to array of ddocs
    if(co.generate_doc)
    {    
        string modules = "MODULES = \n";
        sources.sort;
        foreach(src; sources)
        {    
            //get filename 
            src = split(src, "\\.")[0];
            src = src.replace("/", ".").replace("\\", ".");
            modules ~= "\t$(MODULE " ~ src ~ ")\n";
        }
        scope(failure){remove("modules.ddoc");}
        write("modules.ddoc", modules);
        ddocs ~= "modules.ddoc";
    }
    
    string[] arguments = options ~ sources ~ ddocs ~ libs;

    //Compile
    if(compiler == "gdc")
    {
        //Add support for building libraries to gdc.
        //GDC must build incrementally if creating documentation or a lib. 
        if(co.generate_lib || co.generate_doc || co.no_linking)
        {
            //Remove options we don't want to pass to gdc when building incrementally.
            auto incremental_options = 
                 array(filter!`a != "-lib" && !startsWith(a, "-o")`(options));

            //Compile files individually, outputting full path names
            string[] obj_files;
            foreach(source; sources)
            {    
                string obj = source.replace("/", ".")[0 .. $ - 2] ~ ".o";
                string ddoc = obj[0 .. $ - 2];
                if(co.obj_directory !is null)
                {
                    obj = co.obj_directory ~ file_separator ~ obj;
                }
                obj_files ~= obj;
                string[] exec = incremental_options ~ ["-o" ~ obj, "-c"] ~ [source];
                //ensure doc files are always fully qualified. 
                if(co.generate_doc){exec ~= ddocs ~ ["-fdoc-file=" ~ ddoc ~ ".html"];}
                //throws ProcessException on compile failure
                execute(compiler, exec);
            }

            //use ar to join the .o files into a lib and cleanup obj files
            //TODO: how to join on GDC windows?
            if(co.generate_lib)
            {    
                //since ar refuses to overwrite it. 
                remove(co.out_file);
                execute("ar", "cq " ~ co.out_file ~ obj_files);
            }

            //Remove obj files if -c or -od not were supplied.
            if(!co.obj_directory && !co.no_linking)
            {
                foreach(o; obj_files){remove(o);}
            }
        }

        if(!co.generate_lib && !co.no_linking)
        {
            //Remove documentation arguments since they were handled above
            execute_compiler(compiler, 
                             array(filter!`!startsWith(a, "-fdoc", "-od")`(arguments)));
        }
    }
    //Compilers other than gdc 
    else
    {    
        execute_compiler(compiler, arguments);        
        //Move all html files in doc_path to the doc output folder 
        //and rename them with the "package.module" naming convention.
        if(co.generate_doc) foreach(src; sources)
        {    
            if(src.extension != ".d"){continue;}

            string html = src[0 .. $ - 2] ~ ".html";
            string dest = html.replace("/", ".").replace("\\", ".");
            if(co.doc_directory.length > 0)
            {    
                dest = co.doc_directory ~ file_separator ~ dest;
                html = co.doc_directory ~ file_separator ~ html;
            }
            //TODO: Delete remaining folders where source files were placed.
            if(html != dest)
            {    
                copy(html, dest);
                remove(html);
            }    
        }    
    }

    //Remove extra files
    string basename = split(co.out_file, "/")[$ - 1];

    if(co.generate_doc){remove("modules.ddoc");}
    if(co.out_file && !(co.no_linking || co.obj_directory))
    {
        foreach(ext; obj_ext)
        {
            //Delete object files with same name as output file that dmd sometimes leaves. 
            try{remove(co.out_file.setExtension(ext));}
            catch(FileException e){continue;}
        }
    }
}

/**
 * Stores compiler options and translates them between compilers.
 *
 * Also enables -of and -op for easier handling. 
 */
struct CompileOptions
{
    public:
        ///Do not link.
        bool no_linking;                
        ///Generate documentation.
        bool generate_doc;
        ///Write documentation to this directory.
        string doc_directory;
        ///Write documentation to this file.
        string doc_file;            
        ///Generate library rather than object files.
        bool generate_lib;            
        ///Do not write object files.
        bool no_objects;                
        ///write object, library files to this directory.
        string obj_directory;            
        ///Name of output file.
        string out_file;

    private:
        ///Compiler options.
        string[] options_;

    public:
        /**
         * Construct CompileOptions from command line options.
         *
         * Params:  options = Compiler command line options.
         *          sources = Source files to compile.
         */
        this(string[] options, const string[] sources)
        {   
            foreach(i, opt; options)
            {
                if(opt == "-c")                               {no_linking = true;}
                else if(["-D", "-fdoc"].canFind(opt))         {generate_doc = true;}
                else if(opt.startsWith("-Dd"))                {doc_directory = opt[3..$];}
                else if(opt.startsWith("-fdoc-dir="))         {doc_directory = opt[10..$];}
                else if(opt.startsWith("-Df"))                {doc_file = opt[3..$];}
                else if(opt.startsWith("-fdoc-file="))        {doc_file = opt[11..$];}
                else if(opt == "-lib")                        {generate_lib = true;}
                else if(["-o-", "-fsyntax-only"].canFind(opt)){no_objects = true;}
                else if(opt.startsWith("-of"))                {out_file = opt[3..$];}
                else if(opt.startsWith("-od"))                {obj_directory = opt[3..$];}
                else if(opt.startsWith("-o") && opt != "-op") {out_file = opt[2..$];}
                options_ ~= opt;
            }

            //Set the -o (output filename) flag to the first source file if not already set.
            //This matches the default behavior of dmd.
            string ext = generate_lib ? lib_ext : bin_ext; 
            if(out_file.length == 0 && !no_linking && !no_objects && sources.length > 0)
            {    
                out_file = sources[0].split("/").back.split("\\.")[0] ~ ext;
                options_ ~= "-of" ~ out_file;
            }
            version (Windows)
            {    
                auto dot = find(out_file, '.');
                auto backslash = retro(find(retro(out_file), '/'));
                if(dot <= backslash)
                {
                    out_file ~= bin_ext;
                }
            }
        }

        /**
         * Translate DMD compiler options to options of the target compiler.
         *
         * This function is incomplete. (what about -L? )
         *
         * Params:  compiler = Compiler to translate to.
         *
         * Returns: Translated options.
         */
        string[] get_options(const string compiler)
        {    
            string[] result = options_.dup;

            if(compiler != "gdc")
            {
                version(Windows) foreach(ref option; result)
                {
                    option = option.startsWith("-of") ? option.replace("/", "\\") : option;
                }

                //ensure ddocs don't overwrite one another.
                return result.canFind("-op") ? result : result ~ "-op";
            }

            //is gdc
            auto translate = ["-Dd"       : "-fdoc-dir=",
                              "-Df"       : "-fdoc-file=",
                              "-debug="   : "-fdebug=",
                              "-debug"    : "-fdebug", // will this still get selected?
                              "-inline"   : "-finline-functions",
                              "-L"        : "-Wl",
                              "-lib"      : "",
                              "-O"        : "-O3",
                              "-o-"       : "-fsyntax-only",
                              "-of"       : "-o ",
                              "-unittest" : "-funittest",
                              "-version"  : "-fversion=",
                              "-version=" : "-fversion=",
                              "-wi"       : "-Wextra",
                              "-w"        : "-Wall",
                              "-gc"       : "-g"];

            //Perform option translation
            foreach(ref option; result)
            {    
                //remove unsupported -od
                if(option.startsWith("-od")){option = "";}
                if(option == "-D"){option = "-fdoc";}
                //Options with a direct translation 
                else foreach(before, after; translate) 
                {
                    if(option.startsWith(before))
                    {    
                        option = after ~ option[before.length..$];
                        break;
                    }
                }
            }
            return result;
        }
        unittest
        {
            auto sources = ["foo.d"];
            auto options = ["-D", "-inline", "-offoo"];
            auto result = CompileOptions(options, sources).get_options("gdc");
            assert(result[0 .. 3] == ["-fdoc", "-finline-functions", "-o foo"]);
        }
}

///Thrown at errors in execution of other processes (e.g. compiler commands).
class CompileException : Exception 
{
    this(const string message, const string file, in size_t line){super(message, file, line);}
};

/**
 * Wrapper around execute to write compile options to a file to get around max arg lenghts on Windows.
 *
 * Params:  compiler  = Compiler to execute.
 *          arguments = Compiler arguments.
 */
void execute_compiler(const string compiler, string[] arguments)
{    
    try
    {
        version(Windows)
        {    
            write("compile", arguments.join(" "));
            scope(exit){remove("compile");}
            execute(compiler ~ " ", ["@compile"]);
        } 
        else{execute(compiler, arguments);}
    } 
    catch(ProcessException e)
    {
        writeln("Compiler failed: " ~ e.msg);
    }
}

///Thrown at errors in execution of other processes (e.g. compiler commands).
class ProcessException : Exception {this(const string message){super(message);}};

/**
 * Execute a command-line program and print its output.
 *
 * Params: command = The command to execute, e.g. "dmd".
 *         args    = Arguments to pass to the command.
 *
 * Throws: ProcessException on failure or status code 1.
 */
void execute(string command, string[] args)
{    
    version(Windows)
    {
        if(command.startsWith("./")){command = command[2 .. $];}
    }

    string full = command ~ " " ~ args.join(" ");
    writeln("CDC:  " ~ full);
    if(int status = system(full ~ "\0") != 0)
    {
        throw new ProcessException("Process " ~ command ~ " exited with status " ~ 
                                   to!string(status));
    }
}

/**
 * Recursively get all files with specified extensions in directory and subdirectories.
 *
 * Params:  directory  = Absolute or relative path to the current directory.
 *          extensions = Extensions to match.
 *
 * Returns: An array of paths (including filename) relative to directory.
 *
 * Bugs:    LDC fails to return any results. 
 */
string[] scan(const string directory, string extensions ...)
{    
    string[] result;
    foreach(string name; dirEntries(directory, SpanMode.depth))
    {
        if(isFile(name) && name.endsWith(extensions)){result ~= name;}
    }
    return result;
}
