
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///Zero terminated string.
module dyaml.zerostring;

import core.stdc.string;

/**
 * Zero terminated string used to decrease data structure size. 
 *
 * TypeName is used to differentiate types (better than simple alias).
 */
struct ZeroString(string TypeName)
{
    private:
        ///Zero terminated string.
        immutable(char)* str_ = null;

    public:
        @disable int opCmp(ref ZeroString);

        ///Construct a string.
        this(in string str)
        {
            if(str is null || str == "")
            {
                str_ = null;
                return;
            }

            str_ = (str ~ '\0').ptr;
        }

        ///Get the string.
        @property string get() const
        in{assert(!isNull());}
        body
        {
            return cast(string)str_[0 .. strlen(str_)];
        }

        ///Test for equality with another string.
        bool opEquals(const ref ZeroString str) const
        {
            return isNull ? str.isNull : 
                   str.isNull ? false : (0 == strcmp(str_, str.str_));
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

        ///Compare with another string.
        int opCmp(const ref ZeroString str) const 
        in{assert(!isNull && !str.isNull);}
        body
        {
            return strcmp(str_, str.str_);
        }

        ///Is this string null (invalid)?
        @property bool isNull() const {return str_ is null;}
}
