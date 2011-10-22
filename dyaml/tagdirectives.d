
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///Tag directives.
module dyaml.tagdirectives;

import std.typecons;

import dyaml.sharedobject;

///Single tag directive. handle is the shortcut, prefix is the prefix that replaces it.
alias Tuple!(string, "handle", string, "prefix") tagDirective;

///Tag directives stored in Event.
struct TagDirectives
{
    public:
        mixin SharedObject!(tagDirective[], TagDirectives);

        ///Construct a tags object from an array of tag directives.
        this(tagDirective[] tagDirectives)
        {
            add(tagDirectives);
        }
}
