
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///Shared object.
module dyaml.sharedobject;

/**
 * Mixin for shared objects (need a better name). 
 *
 * This works as an index to a static array of type T. Any new object created is 
 * checked for presence in the array to prevent duplication.
 *
 * This is useful for e.g. token/event data that rarely needs to be
 * stored (e.g. tag directives) to prevent inflation of these structs,
 * and when there are many instances of a data type that are mostly
 * duplicates (e.g. tags). 
 *
 * Disadvantage is, this is not thread-safe (and neither is D:YAML, at the 
 * moment). That might be fixed in futurere, though.
 *
 * This is not the most elegant way to store the extra data  and change in future.
 */
template SharedObject(T, MixedIn)
{
    private:
        ///Index of the object in objects_.
        uint index_ = uint.max;

        /**
         * Reference count.
         *
         * When this reaches zero, objects_ are cleared. This count is not
         * the number of shared objects, but rather of objects using this kind 
         * of shared object. This is used e.g. with Anchor, but not with Tag 
         * - tags can be stored by the user in Nodes so there is no way to know 
         * when there are no Tags anymore.
         */
        static int referenceCount_ = 0;

        /**
         * All known objects of this type are in this array.
         *
         * Note that this is not shared among threads.
         * Working the same YAML file in multiple threads is NOT safe with D:YAML.
         */
        static T[] objects_;

        ///Add a new object, checking if identical object already exists.
        void add(ref T object)
        {
            foreach(uint index, known; objects_)
            {
                if(object == known)
                {
                    index_ = index;
                    return;
                }
            }
            index_ = cast(uint)objects_.length;
            objects_ ~= object;
        }

    public:
        ///Increment the reference count.
        static void addReference()
        {
            assert(referenceCount_ >= 0);
            ++referenceCount_;
        }

        ///Decrement the reference count and clear the constructed objects if zero.
        static void removeReference()
        {
            --referenceCount_;
            assert(referenceCount_ >= 0);
            if(referenceCount_ == 0){objects_ = [];}
        }

        ///Get the object.
        @property T get() const
        in{assert(!isNull());}
        body
        {
            return objects_[index_];
        }

        ///Test for equality with another object.
        bool opEquals(const ref MixedIn object) const
        {
            return object.index_ == index_;
        }

        ///Is this object null (invalid)?
        bool isNull() const {return index_ == uint.max;}
}

