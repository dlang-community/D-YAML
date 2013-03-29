
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///YAML anchor.
module dyaml.anchor;

import dyaml.zerostring;

///YAML anchor (reference) struct. Encapsulates an anchor to save memory.
alias ZeroString!"Anchor" Anchor;
