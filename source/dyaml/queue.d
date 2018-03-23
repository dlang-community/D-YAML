
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.queue;


/// Queue collection.
import core.stdc.stdlib;
import core.memory;

import std.container;
import std.traits;


package:

/// Simple queue implemented as a singly linked list with a tail pointer.
/// 
/// Needed in some D:YAML code that needs a queue-like structure without too much
/// reallocation that goes with an array.
/// 
/// This should be replaced once Phobos has a decent queue/linked list.
/// 
/// Uses manual allocation through malloc/free.
/// 
/// Also has some features uncommon for a queue, e.g. iteration. Couldn't bother with
/// implementing a range, as this is used only as a placeholder until Phobos gets a
/// decent replacement.
struct Queue(T)
    if(!hasMember!(T, "__dtor"))
{
    private:
        /// Linked list node containing one element and pointer to the next node.
        struct Node
        {
            T payload_;
            Node* next_ = null;
        }

        /// Start of the linked list - first element added in time (end of the queue).
        Node* first_ = null;
        /// Last element of the linked list - last element added in time (start of the queue).
        Node* last_ = null;
        /// Cursor pointing to the current node in iteration.
        Node* cursor_ = null;

        /// The first element of a linked list of freed Nodes available for recycling.
        Node* freeList_ = null;

        /// Length of the queue.
        size_t length_ = 0;

    public:
        @disable void opAssign(ref Queue);
        @disable bool opEquals(ref Queue);
        @disable int opCmp(ref Queue);

        /// Destroy the queue, deallocating all its elements.
        @trusted nothrow ~this()
        {
            while(!empty) { pop(); }
            while(freeList_ !is null)
            {
                auto toFree = freeList_;
                freeList_   = toFree.next_;
                free(toFree);
            }
            cursor_ = last_ = first_ = null;
            length_ = 0;
        }

        /// Start iterating over the queue.
        void startIteration() @safe pure nothrow @nogc
        {
            cursor_ = first_;
        }

        /// Get next element in the queue.
        ref const(T) next() @safe pure nothrow @nogc
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

        /// Are we done iterating?
        bool iterationOver() @safe pure nothrow const @nogc
        {
            return cursor_ is null;
        }

        /// Push new item to the queue.
        void push(T item) @trusted nothrow
        {
            Node* newLast = newNode(item, null);
            if(last_ !is null) { last_.next_ = newLast; }
            if(first_ is null) { first_      = newLast; }
            last_ = newLast;
            ++length_;
        }

        /// Insert a new item putting it to specified index in the linked list.
        void insert(T item, const size_t idx) @trusted nothrow
        in
        {
            assert(idx <= length_);
        }
        body
        {
            if(idx == 0)
            {
                first_ = newNode(item, first_);
                ++length_;
            }
            // Adding before last added element, so we can just push.
            else if(idx == length_) { push(item); }
            else
            {
                // Get the element before one we're inserting.
                Node* current = first_;
                foreach(i; 1 .. idx) { current = current.next_; }

                // Insert a new node after current, and put current.next_ behind it.
                current.next_ = newNode(item, current.next_);
                ++length_;
            }
        }

        /// Return the next element in the queue and remove it.
        T pop() @trusted nothrow
        in
        {
            assert(!empty, "Trying to pop an element from an empty queue");
        }
        body
        {
            T result     = peek();
            Node* popped = first_;
            first_       = first_.next_;

            Node* oldFree   = freeList_;
            freeList_       = popped;
            freeList_.next_ = oldFree;
            if(--length_ == 0)
            {
                assert(first_ is null);
                last_ = null;
            }

            return result;
        }

        /// Return the next element in the queue.
        ref inout(T) peek() @safe pure nothrow inout @nogc 
        in
        {
            assert(!empty, "Trying to peek at an element in an empty queue");
        }
        body
        {
            return first_.payload_;
        }

        /// Is the queue empty?
        bool empty() @safe pure nothrow const @nogc
        {
            return first_ is null;
        }

        /// Return number of elements in the queue.
        size_t length() @safe pure nothrow const @nogc
        {
            return length_;
        }

private:
        /// Get a new (or recycled) node with specified item and next node pointer.
        ///
        /// Tries to reuse a node from freeList_, allocates a new node if not possible.
        Node* newNode(ref T item, Node* next) @trusted nothrow
        {
            if(freeList_ !is null)
            {
                auto node = freeList_;
                freeList_ = freeList_.next_;
                *node     = Node(item, next);
                return node;
            }
            return allocate!Node(item, next);
        }
}


private:

/// Allocate a struct, passing arguments to its constructor or default initializer.
T* allocate(T, Args...)(Args args) @system nothrow
{
    T* ptr = cast(T*)malloc(T.sizeof);
    *ptr = T(args);
    // The struct might contain references to GC-allocated memory, so tell the GC about it.
    static if(hasIndirections!T) { GC.addRange(cast(void*)ptr, T.sizeof); }
    return ptr;
}

/// Deallocate struct pointed at by specified pointer.
void free(T)(T* ptr) @system nothrow
{
    // GC doesn't need to care about any references in this struct anymore.
    static if(hasIndirections!T) { GC.removeRange(cast(void*)ptr); }
    core.stdc.stdlib.free(ptr);
}

@safe unittest
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
