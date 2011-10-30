
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
 * This is not the most elegant way to store the extra data and might change in future.
 */
template SharedObject(T, MixedIn)
{
    private:
        ///This class stores the data that is shared between the objects.
        class SharedData
        {
            private:
                /**
                 * Reference count.
                 *
                 * When this reaches zero, objects_ are cleared. This is not
                 * the number of shared objects, but rather of objects using this kind 
                 * of shared object. 
                 */
                int referenceCount_ = 0;  

                ///All known objects of type T are in this array.
                T[] objects_;

            public:
                ///Increment the reference count.
                void addReference()
                {
                    assert(referenceCount_ >= 0);
                    ++referenceCount_;
                }

                ///Decrement the reference count and clear the constructed objects if zero.
                void removeReference()
                {
                    --referenceCount_;
                    assert(referenceCount_ >= 0);
                    if(referenceCount_ == 0)
                    {
                        clear(objects_);
                        objects_ = [];
                    }
                }

                ///Add an object and return its index.
                uint add(ref T object)
                {
                    foreach(index, ref known; objects_) if(object == known)
                    {
                        return cast(uint)index;
                    }
                    objects_ ~= object;
                    return cast(uint)objects_.length - 1;
                }

                ///Get the object at specified object.
                @property T get(in uint index) 
                {
                    return objects_[index];
                }
        }

        ///Index of the object in data_.
        uint index_ = uint.max;

        ///Stores the actual objects.
        static __gshared SharedData data_;

        static this()
        {
            data_ = new SharedData;
        }

    public:
        ///Increment the reference count.
        static void addReference()
        {
            synchronized(data_){data_.addReference();}
        }

        ///Decrement the reference count and clear the constructed objects if zero.
        static void removeReference()
        {
            synchronized(data_){data_.removeReference();}
        }

        ///Get the object.
        @property T get() const
        in{assert(!isNull());}
        body
        {
            T result;
            synchronized(data_){result = data_.get(index_);}
            return result;
        }

        ///Test for equality with another object.
        bool opEquals(const ref MixedIn object) const
        {
            return object.index_ == index_;
        }

        ///Is this object null (invalid)?
        @property bool isNull() const {return index_ == uint.max;}

    private:
        ///Add a new object, checking if identical object already exists.
        void add(ref T object)
        {
            synchronized(data_){index_ = data_.add(object);}
        }
}

