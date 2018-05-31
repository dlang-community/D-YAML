# 0.5.0

## Breaking changes

As many people have been using D:YAML from git master since the 0.4
release, each change is prefixed by the year the change was introduced.

  - `2014` The `cdc.d` build script has been removed; dub is now the
    only 'official' way to build D:YAML.
  - `2014` Broke compatibility with all DMD versions before 2.066
  - `2014` `Loader` API depending on `std.stream` is now deprecated and
    will be removed in the next release.
  - `2014` `Loader.fromString(string)` is now deprecated and replaced by
    `Loader.fromString(char[])`, which will reuse and overwrite the
    input during parsing. The string overload will be removed in the
    next release.
  - `2012` Values in D:YAML are less 'dynamic-typed'. E.g. removing
    `"42"` won't also remove `42`. Such automatic conversion still
    happens e.g. in a foreach over a mapping with a string key. The
    `Node.as()` method has a template parameter to disable automatic
    conversion from strings to other types.

## API improvements

  - `Loader` is now, by default, constructed from a non-const buffer
    containing YAML data instead of a `std.stream.Stream`. D:YAML reuses
    and overwrites this buffer to minimize memory allocations during
    parsing. Convenience API such as the `Loader` constructor from a
    filename is unchanged although it loads the file to a buffer
    internally.
  - `Node.contains()` method to check if a YAML sequence/mapping
    contains specified value (as opposed to a key).
  - `Node.containsKey()` method to check if a YAML mapping contains
    specified key.
  - `Node.isNull()` property.
  - `Node operator in` analogous to associative array `in`.
  - `Loader.fromString()` method as a quick wrapper to parse YAML from a
    string.
  - `dyaml.hacks` module for potentially useful things YAML
    specification doesn't allow.
  - Most of the API is `@safe` or at least `@trusted`. Also `pure` and
    `nothrow` where possible.
  - User-defined constructors can now also construct builtin YAML types.
  - Input is now validated at Loader construction to detect invalid UTF
    sequences early and to minimize internal exception handling during
    parsing.

## Other improvements

  - D:YAML now works with a UTF-8 buffer internally. This decreases
    memory usage for UTF-8 input, and UTF-32 inputs can be encoded into
    UTF-8 in-place without allocating. UTF-16 inputs still need an
    allocation. This also gets rid of all dchar\[\]-\>char\[\]
    conversions which were a significant source of GC allocations.
  - Various optimizations in `Reader`/`Scanner`, especially for
    mostly-ASCII files containing plain scalars (most common YAML
    files). Measured speedup of ~80% when parsing mostly-ASCII files,
    slowdown of ~12% for mostly non-ASCII files (all tested files were
    UTF-8).
  - Less GC usage during YAML node construction.
  - `Scanner` is now mostly `@nogc`; it never allocates memory for token
    values, using slices into the input buffer instead.
  - Custom, `@nogc` UTF decoding/encoding code based on `std.utf` to
    enable more use of `@nogc` in D:YAML internals and to improve
    performance.
  - Less memory allocations during scanning in general, including manual
    allocations.
  - Default `Constructor`/`Resolver` are now only constructed if the
    user doesn't specify their own.
  - Replaced `std.stream.EndianStream` with
    [tinyendian](https://github.com/kiith-sa/tinyendian).
  - D:YAML is now a DUB package.
  - Removed static data structures such as default Constructor and
    Resolver.
  - Compile-time checks for size of data structures that should be
    small.
  - Better error messages.
  - Various refactoring changes, using more 'modern' D features, better
    tests.
  - Updated documentation, examples to reflect changes in 0.5.
  - Updated the `yaml_bench` example/tool with options to keep the input
    file in memory instead of reloading it for repeated parses, and to
    only benchmark scanning time instead of the entire parser.
  - The `yaml_gen` example/tool can now generate strings from
    user-specified alphabets which may contain non-ASCII characters.

## Bugfixes

  - Fixed mappings longer than 65535 lines.
  - Removed a lot of `in` parameters that were used due to a
    misunderstanding of what `in` is supposed to do.
  - Fixed `real` emitting.
  - Fixed 32bit compilation (again).
  - Various small bugfixes.

# 0.4.0

## Features/improvements

  - **API BREAKING**: All structs and classes stored directly in YAML
    nodes (aka custom YAML data types) now need to define the opCmp
    operator. This is used for duplicate detection instead of AAs (which
    are broken) and will allow efficient access to data in unordered
    maps.
  - **API BREAKING**: Simplified the Constructor API. Constructor
    functions now don't need to get Marks through parameters - any
    exceptions thrown by the constructor functions are caught and
    wrapped along with Mark info.
  - Various small improvements in the API documentation.
  - Updated API documentation, tutorials and examples to match the
    changes.
  - Small CDC (build script) improvements.

## Bugfixes

  - Fixed compilation with DMD 2.057.
  - Fixed a bug caused by std.regex changes that broke null value
    parsing.
  - Fixed compilation on 32bit.
  - Various small bugfixes.

# 0.3.0

## Features/improvements

  - **API BREAKING**: Removed Node.getToVar as it turned out to be a
    premature optimization.
  - **API BREAKING**: Constructor API for constructing custom YAML data
    types has been improved to make it easier to load custom
    classes/structs. See the custom types tutorial and Constructor API
    documentation.
  - Node.opIndex now returns a reference to a node.
  - Added a shortcut alias Node.as for Node.get . Node.as might
    eventually replace Node.get (in a 1.0 release).
  - User can now access a string representation of tag of a node.
  - Nodes now remember their scalar and collection styles between
    loading and dumping. These are not accessible to user. User can set
    output styles in Representer.
  - Updated API documentation to reflect the new changes, added more
    examples and overall made the documentation more readable.
  - Improved error messages of exceptions.
  - Drastically optimized scanning and parsing, decreasing parsing time
    to about 10% (no precise benchmark comparison with 0.2 at the
    moment).
  - Eliminated most GC usage, improving speed and memory usage.
  - Optimized Dumper for speed, especially when dumping many small
    files.
  - Reader has been reimplemented to improve performance.
  - Many other speed and memory optimizations.
  - Added a profiling build target and a parsing/dumping benchmark.
  - Added a random YAML file generator and a YAML file analyzer, as
    example applications and for benchmarking.
  - Added a "clean" target to example Makefiles.
  - Got rid of all global state.

## Bugfixes

  - Fixed compatibility issues with DMD 2.056.
  - Fixed an Emitter bug which caused tags to always be emitted in full
    format.
  - Fixed a bug that caused errors when loading documents with YAML
    version directives.
  - Fixed many const-correctness bugs.
  - Minor bugfixes all over the code.
  - Fixed many documentation bugs.

# 0.2.0

## Features/improvements

  - Implemented YAML emitter, and related unittests/documentation.
  - Tags are now stored in nodes, allowing D:YAML to be closer to the
    specification.
  - Loader API has been broken to make it more extensible in future
    -Representer and Constructor are no more specified in the
    constructor, and the load() shortcut functions have been removed, as
    all that's needed to load a YAML document now is
    Loader("file.yaml").load() .

## Bugfixes

  - Fixed many bugs in the parser, scanner, composer and constructor.
