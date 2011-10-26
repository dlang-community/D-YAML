
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///YAML tag.
module dyaml.tag;


import core.stdc.string;


///YAML tag (data type) struct. Encapsulates a tag to save memory and speed-up comparison.
struct Tag
{
    private:
        ///Zero terminated tag string.
        immutable(char)* tag_ = null;

    public:
        ///Construct a tag from a string representation.
        this(string tag)
        {
            if(tag is null || tag == "")
            {
                tag_ = null;
                return;
            }

            tag_ = (tag ~ '\0').ptr;
        }

        ///Get the tag string.
        @property string get() const
        in{assert(!isNull());}
        body
        {
            return cast(string)tag_[0 .. strlen(tag_)];
        }

        ///Test for equality with another tag.
        bool opEquals(const ref Tag tag) const
        {
            return isNull ? tag.isNull : 
                   tag.isNull ? false : (0 == strcmp(tag_, tag.tag_));
        }

        ///Compute a hash.
        hash_t toHash() const
        in{assert(!isNull);}
        body
        {
            static type = typeid(string);
            auto str = get();
            return type.getHash(&str);
        }

        ///Compare with another tag.
        int opCmp(const ref Tag tag) const 
        in{assert(!isNull && !tag.isNull);}
        body
        {
            return strcmp(tag_, tag.tag_);
        }

        ///Is this tag null (invalid)?
        @property bool isNull() const {return tag_ is null;}
}
