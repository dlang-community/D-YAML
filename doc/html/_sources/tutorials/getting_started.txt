===============
Getting started 
===============

Welcome to D:YAML! D:YAML is a `YAML <http://en.wikipedia.org/wiki/YAML>`_ 
parser library for the 
`D programming language <http://d-programming-language.org>`_. This tutorial 
will explain how to set D:YAML up and use it in your projects. 

This is meant to be the **simplest possible** introduction to D:YAML. Some of 
this information might already be known to you. Only basic usage is covered. 


----------
Setting up
----------

^^^^^^^^^^^^^^^^^^^^^^^^
Install the DMD compiler
^^^^^^^^^^^^^^^^^^^^^^^^

Digital Mars D compiler, or DMD, is the most commonly used D compiler. You can
find its newest version `here <http://www.digitalmars.com/d/download.html>`_. 
Download the version of DMD for your operating system and install it.

.. note:: 
   Other D compilers exist, such as 
   `GDC <http://bitbucket.org/goshawk/gdc/wiki/Home>`_ and 
   `LDC <http://www.dsource.org/projects/ldc/>`_. Setting up with either one of
   them should be similar to DMD, but they are not yet as stable as DMD.

^^^^^^^^^^^^^^^^^^^^^^^^^^^
Download and compile D:YAML
^^^^^^^^^^^^^^^^^^^^^^^^^^^

The newest version of D:YAML can be found
`here <https://github.com/Kiith-Sa/D-YAML>`_. Download a source archive, extract
it, and move to the extracted directory.

D:YAML uses a modified version of the `CDC <http://dsource.org/projects/cdc/>`_ 
script for compilation. To compile D:YAML, you first need to build CDC.
Do this by typing the following command into the console::

   dmd cdc.d

Now you can use CDC to compile D:YAML.
To do this on Unix/Linux, use the following command::

   ./cdc

On Windows::

   cdc.exe

This will compile the library to a file called ``libdyaml.a`` on Unix/Linux or
``libdyaml.lib`` on Windows.


-------------------------
Your first D:YAML project 
-------------------------

Create a directory for your project and in that directory, create a file called
``input.yaml`` with the following contents:

.. code-block:: yaml

   Hello World :
       - Hello
       - World
   Answer: 42

This will serve as input for our example.

Now we need to parse it. Create a file called "main.d". Paste following code 
into the file:

.. code-block:: d

   import std.stdio;
   import yaml;

   void main()
   {
       Node root = Loader("input.yaml").load();
       foreach(string word; root["Hello World"])
       {
           writeln(word);
       }
       writeln("The answer is ", root["Answer"].get!int);
   }


^^^^^^^^^^^^^^^^^^^^^^^
Explanation of the code
^^^^^^^^^^^^^^^^^^^^^^^

First, we import the *yaml* module. This is the only module you need to import 
to use D:YAML - it automatically imports all needed modules.

Next we load the file using the *Loader.load()* method. *Loader* is the struct 
used for parsing YAML documents, and *load()* is a method that loads the file as
**one** YAML document, or throws *YAMLException*, D:YAML exception type, if the 
file could not be parsed or does not contain exactly one document. Note that we 
don't do any error checking here in order to keep the example as simple as 
possible.

*Node* represents a node in a YAML document. It can be a sequence (array), 
mapping (associative array) or a scalar (value). Here the root node is a 
mapping, and we use the index operator to get subnodes with keys "Hello World"
and "Answer". We iterate over the first, as it is a sequence, and use the 
*Node.get()* method on the second to get its value as an integer.

You can iterate over a mapping or sequence as if it was an associative or normal 
array. If you try to iterate over a scalar, it will throw a *YAMLException*. 

You can iterate over subnodes using *Node* as the iterated type, or specify 
the type subnodes are expected to have. D:YAML will automatically convert 
iterated subnodes to that type if possible. Here we specify the *string* type, 
so we iterate over the "Hello World" sequence as an array of strings. If it is
not possible to convert to iterated type, a *YAMLException* is thrown. For 
instance, if we specified *int* here, we would get an error, as "Hello" 
cannot be converted to an integer.

The *Node.get()* method is used to get value of a scalar node, allowing to 
specify type. D:YAML will try to return the scalar as this type, converting if 
needed, throwing *YAMLException* if not possible.


^^^^^^^^^
Compiling
^^^^^^^^^

To compile your project, you must give DMD the directories containing import 
modules and the library. You also need to tell it to link with D:YAML. The import
directory should be the D:YAML package directory. You can specify it using the 
``-I`` option of DMD. The library directory should be where you put the compiled
D:YAML library. On Unix/Linux you can specify it using the ``-L-L`` option, and 
link with D:YAML using the ``-L-l`` option. On Windows, the import directory is
used as the library directory. To link with the library on Windows, just add the
path to it relative to the current directory.

For example, if you extracted and compiled D:YAML in ``/home/xxx/dyaml``, your
project is in ``/home/xxx/dyaml-project``, and you are currently in that 
directory, you can compile the project with the following command on Unix/Linux::

   dmd -I../dyaml -L-L../dyaml -L-ldyaml main.d

And the following on Windows::

   dmd -I../dyaml ../dyaml/libdyaml.lib main.d

This will produce an executable called ``main`` or ``main.exe`` in your 
directory. When you run it, it should produce the following output::

   Hello
   World                                                                                                                                                                                                                                                                          
   The answer is 42 


^^^^^^^^^^
Conclusion
^^^^^^^^^^

You should now have a basic idea about how to use D:YAML. To learn more, look at
the `API documentation <../api/index.html>`_ and other tutorials. You can find code for this
example in the ``example/getting_started`` directory in the package.
