# YAML syntax

This is an introduction to the most common YAML constructs. For more detailed
information, see [PyYAML documentation](http://pyyaml.org/wiki/PyYAMLDocumentation),
which this article is based on,
[Chapter 2 of the YAML specification](http://yaml.org/spec/1.1/#id857168)
or the [Wikipedia page](http://en.wikipedia.org/wiki/YAML).

YAML is a data serialization format designed for human readability. YAML is a
recursive acronym for "YAML Ain't Markup Language".

YAML is similar to JSON, and in fact, JSON is a subset of YAML 1.2; but YAML has
some more advanced features and is easier to read. However, it is also more
difficult to parse (and probably somewhat slower). Data is stored in mappings
(associative arrays), sequences (lists) and scalars (single values). Data
structure hierarchy depends either on indentation (block context, similar to
Python code), or nesting of brackets and braces (flow context, similar to JSON).
YAML comments begin with `#` and continue until the end of line.


## Documents

A YAML stream consists of one or more documents starting with `---` and
optionally ending with `...` . `---` can be left out for the first document.

Single document with no explicit start or end:

```
   - Red
   - Green
   - Blue
```
Same document with explicit start and end:
```
   ---
   - Red
   - Green
   - Blue
   ...
```
A stream containing multiple documents:
```
   ---
   - Red
   - Green
   - Blue
   ---
   - Linux
   - BSD
   ---
   answer : 42
```

## Sequences

Sequences are arrays of nodes of any type, similar e.g. to Python lists.
In block context, each item begins with hyphen+space "- ". In flow context,
sequences have syntax similar to D arrays.

```
   #Block context
   - Red
   - Green
   - Blue
```
```
   #Flow context
   [Red, Green, Blue]
```
```
   #Nested
   -
     - Red
     - Green
     - Blue
   -
     - Linux
     - BSD
```
```
   #Nested flow
   [[Red, Green, Blue], [Linux, BSD]]
```
```
   #Nested in a mapping
   Colors:
     - Red
     - Green
     - Blue
   Operating systems:
     - Linux
     - BSD
```

## Mappings

Mappings are associative arrays where each key and value can be of any type,
similar e.g. to Python dictionaries. In block context, keys and values are
separated by colon+space ": ". In flow context, mappings have syntax similar
to D associative arrays, but with braces instead of brackets:

```
   #Block context
   CPU: Athlon
   GPU: Radeon
   OS: Linux

```
```
   #Flow context
   {CPU: Athlon, GPU: Radeon, OS: Linux}

```
```
   #Nested
   PC:
     CPU: Athlon
     GPU: Radeon
     OS: Debian
   Phone:
     CPU: Cortex
     GPU: PowerVR
     OS: Android

```
```
   #Nested flow
   {PC: {CPU: Athlon, GPU: Radeon, OS: Debian},
    Phone: {CPU: Cortex, GPU: PowerVR, OS: Android}}
```
```
   #Nested in a sequence
   - CPU: Athlon
     GPU: Radeon
     OS: Debian
   - CPU: Cortex
     GPU: PowerVR
     OS: Android
```

Complex keys start with question mark+space "? ".

```
   #Nested in a sequence
   ? [CPU, GPU]: [Athlon, Radeon]
   OS: Debian
```

## Scalars

Scalars are simple values such as integers, strings, timestamps and so on.
There are multiple scalar styles.

Plain scalars use no quotes, start with the first non-space and end with the
last non-space character:

```
   scalar: Plain scalar
```

Single quoted scalars start and end with single quotes. A single quote is
represented by a pair of single quotes ''.

```
   scalar: 'Single quoted scalar ending with some spaces    '
```

Double quoted scalars support C-style escape sequences.

```
   scalar: "Double quoted scalar \n with some \\ escape sequences"
```

Block scalars are convenient for multi-line values. They start either with
`|` or with `>`. With `|`, the newlines in the scalar are preserved.
With `>`, the newlines between two non-empty lines are removed.

```
   scalar: |
     Newlines are preserved
     First line
     Second line
```
```
   scalar: >
     Newlines are folded
     This is still the first paragraph

     This is the second
     paragraph
```

## Anchors and aliases

Anchors and aliases can reduce size of YAML code by allowing you to define a
value once, assign an anchor to it and use alias referring to that anchor
anywhere else you need that value. It is possible to use this to create
recursive data structures and some parsers support this; however, D:YAML does
not (this might change in the future, but it is unlikely).

```
   Person: &AD
     gender: male
     name: Arthur Dent
   Clone: *AD
```

## Tags

Tags are identifiers that specify data types of YAML nodes. Most default YAML
tags are resolved implicitly, so there is no need to specify them. D:YAML also
supports implicit resolution for custom, user specified tags.

Explicitly specified tags:

```
   answer: !!int "42"
   name:   !!str "Arthur Dent"
```

Implicit tags:

```
   answer: 42        #int
   name: Arthur Dent #string
```

This table shows D types stored in *yaml.Node* default YAML tags are converted to.
Some of these might change in the future (especially !!map and !!set).

|YAML tag               |D type                 |
|-----------------------|-----------------------|
|!!null                 |dyaml.node.YAMLNull    |
|!!bool                 |bool                   |
|!!int                  |long                   |
|!!float                |real                   |
|!!binary               |ubyte[]                |
|!!timestamp            |std.datetime.SysTime   |
|!!map, !!omap, !!pairs |dyaml.node.Node.Pair[] |
|!!seq, !!set           |dyaml.node.Node[]      |
|!!str                  |string                 |
