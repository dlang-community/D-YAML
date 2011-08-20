
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///YAML tag.
module dyaml.tag;

import core.sync.mutex;


///YAML tag (data type) struct. Encapsulates a tag to save memory and speed-up comparison.
struct Tag
{
    private:
        ///Index of the tag in tags_.
        uint index_ = uint.max;

        /**
         * All known tags are in this array.
         *
         * Note that this is not shared among threads.
         * Working the same YAML file in multiple threads is NOT safe with D:YAML.
         */
        static string[] tags_;

    public:
        ///Construct a tag from a string representation.
        this(string tag)
        {
            if(tag is null || tag == "")
            {
                index_ = uint.max;
                return;
            }

            foreach(uint index, knownTag; tags_)
            {
                if(tag == knownTag)
                {
                    index_ = index;
                    return;
                }
            }
            index_ = cast(uint)tags_.length;
            tags_ ~= tag;
        }

        ///Get string representation of the tag.
        string toString() const
        in{assert(!isNull());}
        body
        {
            return tags_[index_];
        }

        ///Test for equality with another tag.
        bool opEquals(const ref Tag tag) const
        {
            return tag.index_ == index_;
        }

        ///Is this tag null (invalid)?
        bool isNull() const {return index_ == uint.max;}
}
