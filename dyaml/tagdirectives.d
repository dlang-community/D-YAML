
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///Tag directives.
module dyaml.tagdirectives;

import std.typecons;

import dyaml.sharedobject;


///Tag directives stored in Event.
struct TagDirectives
{
    public:
        mixin SharedObject!(Tuple!(string, string)[], TagDirectives);

        ///Construct a tags object from an array of tag directives.
        this(Tuple!(string, string)[] tagDirectives)
        {
            add(tagDirectives);
        }
}
