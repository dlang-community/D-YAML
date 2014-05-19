//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Functionality that may be sometimes needed but allows unsafe or unstandard
/// behavior, and should only be used in specific cases.
module dyaml.hacks;


import std.stdio;

import dyaml.node;
import dyaml.style;


/// Get the scalar style a YAML node had in the file it was loaded from.
///
/// This is only useful for nodes loaded from files.
///
/// This is a "hack" because a YAML application is supposed to be unaware of styles
/// used in YAML styles,  i.e. treating different styles differently is unstandard.
/// However, determining style may be useful in some cases, e.g. YAML utilities.
///
/// May only be called on scalar nodes (nodes where node.isScalar() == true).
///
/// Example:
/// --------------------
/// // Node node // loaded from a file
/// if(node.isScalar)
/// {
///     import std.stdio;
///     writeln(node.scalarStyleHack());
/// }
/// --------------------
ScalarStyle scalarStyleHack(ref const(Node) node) @safe nothrow
{
    assert(node.isScalar, "Trying to get scalar style of a non-scalar node");
    return node.scalarStyle;
}
unittest
{
    writeln("D:YAML scalarStyleHack getter unittest");
    auto node = Node(5);
    assert(node.scalarStyleHack() == ScalarStyle.Invalid);
}

/// Get the collection style a YAML node had in the file it was loaded from.
///
/// May only be called on collection nodes (nodes where node.isScalar() != true).
///
/// See_Also: scalarStyleHack
CollectionStyle collectionStyleHack(ref const(Node) node) @safe nothrow
{
    assert(!node.isScalar, "Trying to get collection style of a scalar node");
    return node.collectionStyle;
}
unittest
{
    writeln("D:YAML collectionStyleHack getter unittest");
    auto node = Node([1, 2, 3, 4, 5]);
    assert(node.collectionStyleHack() == CollectionStyle.Invalid);
}


/// Set the scalar style a YAML node had in the file it was loaded from.
///
/// Setting the style might be useful when generating YAML or reformatting existing
/// files.
///
/// May only be called on scalar nodes (nodes where node.isScalar() == true).
void scalarStyleHack(ref Node node, const ScalarStyle rhs) @safe nothrow
{
    assert(node.isScalar, "Trying to set scalar style of a non-scalar node");
    node.scalarStyle = rhs;
}
///
unittest
{
    writeln("D:YAML scalarStyleHack setter unittest");
    auto node = Node(5);
    node.scalarStyleHack = ScalarStyle.DoubleQuoted;
    assert(node.scalarStyleHack() == ScalarStyle.DoubleQuoted);
}

/// Set the scalar style a YAML node had in the file it was loaded from.
///
/// Setting the style might be useful when generating YAML or reformatting existing
/// files.
///
/// May only be called on collection nodes (nodes where node.isScalar() != true).
void collectionStyleHack(ref Node node, const CollectionStyle rhs) @safe nothrow
{
    assert(!node.isScalar, "Trying to set collection style of a scalar node");
    node.collectionStyle = rhs;
}
///
unittest
{
    writeln("D:YAML collectionStyleHack setter unittest");
    auto node = Node([1, 2, 3, 4, 5]);
    node.collectionStyleHack = CollectionStyle.Block;
    assert(node.collectionStyleHack() == CollectionStyle.Block);
}
