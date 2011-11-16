
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.queue;


///Queue collection.
import core.stdc.stdlib;
import core.memory;

import std.container;
import std.traits;


package:

/**
 * Simple queue implemented as a singly linked list with a tail pointer.
 *
 * Needed in some D:YAML code that needs a queue-like structure without too 
 * much reallocation that goes with an array.
 *
 * This should be replaced once Phobos has a decent queue/linked list.
 *
 * Uses manual allocation through malloc/free.
 *
 * Also has some features uncommon for a queue, e.g. iteration.
 * Couldn't bother with implementing a range, as this is used only as
 * a placeholder until Phobos gets a decent replacement.
 */
struct Queue(T)
{
    private:
        ///Linked list node containing one element and pointer to the next node.
        struct Node
        {
            T payload_;
            Node* next_ = null;
        }

        ///Start of the linked list - first element added in time (end of the queue).
        Node* first_ = null;
        ///Last element of the linked list - last element added in time (start of the queue).
        Node* last_ = null;
        ///Cursor pointing to the current node in iteration.
        Node* cursor_ = null;
        ///Length of the queue.
        size_t length_ = 0;

    public:
        @disable void opAssign(ref Queue);
        @disable bool opEquals(ref Queue);
        @disable int opCmp(ref Queue);

        ///Destroy the queue, deallocating all its elements.
        ~this()
        {
            while(!empty){pop();}
            cursor_ = last_ = first_ = null;
            length_ = 0;
        }

        ///Start iterating over the queue.
        void startIteration()
        {
            cursor_ = first_;
        }

        ///Get next element in the queue.
        ref const(T) next() 
        in
        {
            assert(!empty);
            assert(cursor_ !is null);
        }
        body
        {
            const previous = cursor_;
            cursor_ = cursor_.next_; 
            return previous.payload_;
        }

        ///Are we done iterating?
        bool iterationOver() const
        {
            return cursor_ is null;
        }

        ///Push new item to the queue.
        void push(T item)
        {
            Node* newLast = allocate!Node(item, cast(Node*)null);
            if(last_ !is null){last_.next_ = newLast;}
            if(first_ is null){first_ = newLast;}
            last_ = newLast;
            ++length_;
        }

        ///Insert a new item putting it to specified index in the linked list.
        void insert(T item, in size_t idx)
        in
        {
            assert(idx <= length_);
        }
        body
        {
            if(idx == 0)
            {
                //Add after the first element - so this will be the next to pop.
                first_ = allocate!Node(item, first_);
                ++length_;
            }
            else if(idx == length_)
            {
                //Adding before last added element, so we can just push.
                push(item);
            }
            else
            {
                //Get the element before one we're inserting.
                Node* current = first_;
                foreach(i; 1 .. idx)
                {
                    current = current.next_;
                }

                //Insert a new node after current, and put current.next_ behind it.
                current.next_ = allocate!Node(item, current.next_);
                ++length_;
            }
        }

        ///Return the next element in the queue and remove it.
        T pop()
        in
        {
            assert(!empty, "Trying to pop an element from an empty queue");
        }
        body
        {
            T result = peek();
            Node* temp = first_;
            first_ = first_.next_;
            free(temp);
            if(--length_ == 0)
            {
                assert(first_ is null);
                last_ = null;
            }

            return result;
        }

        ///Return the next element in the queue.
        ref inout(T) peek() inout
        in
        {
            assert(!empty, "Trying to peek at an element in an empty queue");
        }
        body
        {
            return first_.payload_;
        }

        ///Is the queue empty?
        @property bool empty() const
        {
            return first_ is null;
        }

        ///Return number of elements in the queue.
        @property size_t length() const
        {
            return length_;
        }
}


private:

///Allocate a struct, passing arguments to its constructor or default initializer.
T* allocate(T, Args...)(Args args)
{
    T* ptr = cast(T*)malloc(T.sizeof);
    *ptr = T(args);
    //The struct might contain references to GC-allocated memory, so tell the GC about it.
    static if(hasIndirections!T){GC.addRange(cast(void*)ptr, T.sizeof);}
    return ptr;
}

///Deallocate struct pointed at by specified pointer.
void free(T)(T* ptr)
{
    //GC doesn't need to care about any references in this struct anymore.
    static if(hasIndirections!T){GC.removeRange(cast(void*)ptr);}
    static if(hasMember!(T, "__dtor")){clear(*ptr);}
    std.c.stdlib.free(ptr);
}

unittest
{
    auto queue = Queue!int();
    assert(queue.empty);
    foreach(i; 0 .. 65)
    {
        queue.push(5);
        assert(queue.pop() == 5);
        assert(queue.empty);
        assert(queue.length_ == 0);
    }

    int[] array = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5];
    foreach(i; array)
    {
        queue.push(i);
    }

    array = 42 ~ array[0 .. 3] ~ 42 ~ array[3 .. $] ~ 42;
    queue.insert(42, 3);
    queue.insert(42, 0);
    queue.insert(42, queue.length);

    int[] array2;
    while(!queue.empty)
    {
        array2 ~= queue.pop();
    }

    assert(array == array2);
}
