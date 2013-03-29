
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///YAML tag.
module dyaml.tag;

import dyaml.zerostring;

///YAML tag (data type) struct. Encapsulates a tag to save memory and speed up comparison.
alias ZeroString!"Tag" Tag;
