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

## Your first D:YAML project

First, create a directory for your project and navigate to that directory
using your preferred command line. Then simply execute these two commands:

    dub init
    dub add dyaml

In that directory, create a new file named `input.yaml` and paste this data
into the file:

```YAML
Hello World : [Hello, World]
Answer: 42
```

This will serve as input for our example.

Now we need to parse it. Open the file named `source/app.d` and paste the
following code into the file:

```D
import std.stdio;
import dyaml;

void main()
{
    //Read the input.
    Node root = Loader.fromFile("input.yaml").load();

    //Display the data read.
    foreach(string word; root["Hello World"])
    {
        writeln(word);
    }
    writeln("The answer is ", root["Answer"].as!int);

    //Dump the loaded document to output.yaml.
    dumper.dump(File("output.yaml", "w").lockingTextWriter, root);
}
```

### Explanation of the code

First, we import the *dyaml* module. This is the only D:YAML module
you need to import - it automatically imports all needed modules.

Next we load the file using the *Loader.fromFile().load()* method. *Loader* is a
struct used for parsing YAML documents. The *fromFile()* method loads the
document from a file. The *load()* method loads the
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
documents. *dumper()* returns a *Dumper* with the default setting.
The *dump()* method writes one or more documents to a range,
throwing *YAMLException* if it could not be written to.

D:YAML tries to preserve style information in documents so e.g. `[Hello,
World]` is not turned into:

```YAML
- Hello
- World
```

However, comments are not preserved and neither are any extra formatting
whitespace that doesn't affect the meaning of YAML contents.

### Compiling

Run the following command in your project's directory:

    dub build

DUB will automatically download D:YAML and compile it, and then it
will compile our program. This will generate an executable called
`getting-started` or `getting-started.exe` in your directory. When you
run it, it should produce the following output:

    Hello
    World
    The answer is 42

You may also run ```dub run``` to combine the compile+run steps.

### Conclusion

You should now have a basic idea about how to use D:YAML. To learn more,
look at the [API documentation](https://dyaml.dpldocs.info/dyaml.html) and other tutorials.
You can find code for this example in the `example/getting_started`
directory in the package.
