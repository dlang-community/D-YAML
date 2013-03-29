
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.encoding;


///Text encodings supported by D:YAML.
enum Encoding : ubyte
{
    ///Unicode UTF-8
    UTF_8,
    ///Unicode UTF-16
    UTF_16,
    ///Unicode UTF-32
    UTF_32
}
