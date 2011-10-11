
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///YAML anchor.
module dyaml.anchor;

import dyaml.sharedobject;


///YAML anchor (reference) struct. Encapsulates an anchor to save memory.
struct Anchor
{
    public:
        mixin SharedObject!(string, Anchor);

        ///Construct an anchor from a string representation.
        this(string anchor)
        {
            if(anchor is null || anchor == "")
            {
                index_ = uint.max;
                return;
            }

            add(anchor);
        }
}
