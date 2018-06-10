# Getting started

Welcome to D:YAML\! D:YAML is a
[YAML](http://en.wikipedia.org/wiki/YAML) parser library for the [D
programming language](http://dlang.org). This tutorial will explain how
to set D:YAML up and use it in your projects.

This is meant to be the **simplest possible** introduction to D:YAML.
Some of this information might already be known to you. Only basic usage
is covered.

## Setting up

### Install the DMD compiler

Digital Mars D compiler, or DMD, is the most commonly used D compiler.
You can find its newest version [here](http://dlang.org/download.html).
Download the version of DMD for your operating system and install it.

Note: Other D compilers exist, such as [GDC](http://gdcproject.org/) and
[LDC](https://github.com/ldc-developers/ldc).

### Install dub

[dub](http://code.dlang.org/about) is a build system and package manager
for D. It is the standard way to manage D projects and their
dependencies, compilation and so on.

DMD may include DUB in future releases, but at this point we need to
install it separately. See [installation
instructions](https://github.com/D-Programming-Language/dub#installation).

## Your first D:YAML project

Create a directory for your project and in that directory, create a new
file named `input.yaml` and paste this code into the file:

```YAML
Hello World : [Hello, World]
Answer: 42
```

This will serve as input for our example.

Now we need to parse it. Create a new file with name `main.d`. Paste
following code into the file:

```D
import std.stdio;
import yaml;

void main()
{
    //Read the input.
    Node root = Loader("input.yaml").load();

    //Display the data read.
    foreach(string word; root["Hello World"])
    {
        writeln(word);
    }
    writeln("The answer is ", root["Answer"].as!int);

    //Dump the loaded document to output.yaml.
    Dumper("output.yaml").dump(root);
}
```

### Explanation of the code

First, we import the *dyaml.all* module. This is the only D:YAML module
you need to import - it automatically imports all needed modules.

Next we load the file using the *Loader.load()* method. *Loader* is a
struct used for parsing YAML documents. The *load()* method loads the
file as **one** YAML document, or throws *YAMLException*, D:YAML
exception type, if the file could not be parsed or contains more than
one document. Note that we don't do any error checking here in order to
keep the example as simple as possible.

*Node* represents a node in a YAML document. It can be a sequence
(array), mapping (associative array) or a scalar (value). Here the root
node is a mapping, and we use the index operator to get subnodes with
keys "Hello World" and "Answer". We iterate over the former, as it is a
sequence, and use the *Node.as()* method on the latter to read its value
as an integer.

You can iterate over a mapping or sequence as if it was an associative
or normal array, respectively. If you try to iterate over a scalar, it
will throw a *YAMLException*.

You can iterate using *Node* as the iterated type, or specify the type
iterated nodes are expected to have. D:YAML will automatically convert
to that type if possible. Here we specify the *string* type, so we
iterate over the "Hello World" sequence as an array of strings. If it is
not possible to convert to iterated type, a *YAMLException* is thrown.
For instance, if we specified *int* here, we would get an error, as
"Hello" cannot be converted to an integer.

The *Node.as()* method is used to read value of a scalar node as
specified type. If the scalar does not have the specified type, D:YAML
will try to convert it, throwing *YAMLException* if not possible.

Finally we dump the document we just read to `output.yaml` with the
*Dumper.dump()* method. *Dumper* is a struct used to dump YAML
documents. The *dump()* method writes one or more documents to a file,
throwing *YAMLException* if the file could not be written to.

D:YAML tries to preserve style information in documents so e.g. `[Hello,
World]` is not turned into:

```YAML
- Hello
- World
```

However, comments are not preserved and neither are any extra formatting
whitespace that doesn't affect the meaning of YAML contents.

### Compiling

We're going to use dub, which we installed at the beginning, to compile
our project.

Create a file called `dub.json` with the following contents:

```JSON
{
    "name": "getting-started",
    "targetType": "executable",
    "sourceFiles": ["main.d"],
    "mainSourceFile": "main.d",
    "dependencies":
    {
        "dyaml": { "version" : "~>0.5.0" },
    },
}
```

This file tells dub that we're building an executable called
`getting-started` from a D source file `main.d`, and that our project
depends on D:YAML 0.5.0 or any newer, bugfix release of D:YAML 0.5 . DUB
will automatically find and download the correct version of D:YAML when
the project is built.

Now run the following command in your project's directory:

    dub build

dub will automatically download D:YAML and compile it, and then then it
will compile our program. This will generate an executable called
`getting-started` or `getting-started.exe` in your directory. When you
run it, it should produce the following output:

    Hello
    World
    The answer is 42

### Conclusion

You should now have a basic idea about how to use D:YAML. To learn more,
look at the [API documentation](https://dyaml.dpldocs.info/dyaml.html) and other tutorials.
You can find code for this example in the `example/getting_started`
directory in the package.
