//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Functionality that may sometimes be needed but allows unsafe or unstandard behavior, and should only be used in specific cases.
module dyaml.hacks;

import dyaml.node;
import dyaml.style;


/** Get the scalar style a node had in the file it was loaded from.
 *
 * This is only useful for nodes loaded from files.
 *
 * This is a "hack" because a YAML application is supposed to be unaware of styles
 * used in YAML styles,  i.e. treating different styles differently is unstandard.
 * However, determining style may be useful in some cases, e.g. YAML utilities.
 *
 * May only be called on scalar nodes (nodes where node.isScalar() == true).
 */
ScalarStyle scalarStyleHack(ref const(Node) node) @safe nothrow
{
    assert(node.isScalar, "Trying to get scalar style of a non-scalar node");
    return node.scalarStyle;
}
///
@safe unittest
{
    import dyaml;
    Node node = Loader.fromString(`"42"`.dup).load(); // loaded from a file
    if(node.isScalar)
    {
        assert(node.scalarStyleHack() == ScalarStyle.DoubleQuoted);
    }
}
@safe unittest
{
    auto node = Node(5);
    assert(node.scalarStyleHack() == ScalarStyle.Invalid);
}

/** Get the collection style a YAML node had in the file it was loaded from.
 *
 * May only be called on collection nodes (nodes where node.isScalar() != true).
 *
 * See_Also: scalarStyleHack
 */
CollectionStyle collectionStyleHack(ref const(Node) node) @safe nothrow
{
    assert(!node.isScalar, "Trying to get collection style of a scalar node");
    return node.collectionStyle;
}
@safe unittest
{
    auto node = Node([1, 2, 3, 4, 5]);
    assert(node.collectionStyleHack() == CollectionStyle.Invalid);
}


/** Set the scalar style node should have when written to a file.
 *
 * Setting the style might be useful when generating YAML or reformatting existing files.
 *
 * May only be called on scalar nodes (nodes where node.isScalar() == true).
 */
void scalarStyleHack(ref Node node, const ScalarStyle rhs) @safe nothrow
{
    assert(node.isScalar, "Trying to set scalar style of a non-scalar node");
    node.scalarStyle = rhs;
}
///
@safe unittest
{
    auto node = Node(5);
    node.scalarStyleHack = ScalarStyle.DoubleQuoted;
    assert(node.scalarStyleHack() == ScalarStyle.DoubleQuoted);
}

/** Set the collection style node should have when written to a file.
 *
 * Setting the style might be useful when generating YAML or reformatting existing files.
 *
 * May only be called on collection nodes (nodes where node.isScalar() != true).
 */
void collectionStyleHack(ref Node node, const CollectionStyle rhs) @safe nothrow
{
    assert(!node.isScalar, "Trying to set collection style of a scalar node");
    node.collectionStyle = rhs;
}
///
@safe unittest
{
    auto node = Node([1, 2, 3, 4, 5]);
    node.collectionStyleHack = CollectionStyle.Block;
    assert(node.collectionStyleHack() == CollectionStyle.Block);
}
