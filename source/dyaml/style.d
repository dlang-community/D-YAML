
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///YAML node formatting styles.
module dyaml.style;


///Scalar styles.
enum ScalarStyle : ubyte
{
    Invalid = 0,  /// Invalid (uninitialized) style
    Literal,      /// `|` (Literal block style)
    Folded,       /// `>` (Folded block style)
    Plain,        /// Plain scalar
    SingleQuoted, /// Single quoted scalar
    DoubleQuoted  /// Double quoted scalar
}

///Collection styles.
enum CollectionStyle : ubyte
{
    Invalid = 0, /// Invalid (uninitialized) style
    Block,       /// Block style.
    Flow         /// Flow style.
}
