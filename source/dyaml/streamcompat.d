//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Backward compatibility with std.stream (which was used by D:YAML API in the past).
module dyaml.streamcompat;


import std.stream;

import tinyendian;


/// A streamToBytes wrapper that allocates memory using the GC.
///
/// See_Also: streamToBytes
ubyte[] streamToBytesGC(Stream stream) @trusted nothrow
{
    try return stream.streamToBytes(new ubyte[stream.available]);
    catch(Exception e)
    {
        assert(false, "Unexpected exception in streamToBytesGC: " ~ e.msg);
    }
}

/// Read all data from a std.stream.Stream into an array of bytes.
///
/// Params:
///
/// stream = Stream to read from. Must be readable and seekable.
/// memory = Memory to use. Must be long enough to store the entire stream
///          (memory.length >= stream.available).
///
/// Returns: A slice of memory containing all contents of the stream on success.
///          NULL if unable to read the entire stream.
ubyte[] streamToBytes(Stream stream, ubyte[] memory) @system nothrow
{
    try
    {
        assert(stream.readable && stream.seekable,
                "Can't read YAML from a stream that is not readable and seekable");
        assert(memory.length >= stream.available,
                "Not enough memory passed to streamToBytes");

        auto buffer = memory[0 .. stream.available];
        size_t bytesRead = 0;
        for(; bytesRead < buffer.length;)
        {
            // Returns 0 on eof
            const bytes = stream.readBlock(&buffer[bytesRead], buffer.length - bytesRead);
            // Reached EOF before reading buffer.length bytes.
            if(bytes == 0) { return null; }
            bytesRead += bytes;
        }
        return buffer;
    }
    catch(Exception e)
    {
        assert(false, "Unexpected exception in streamToBytes " ~ e.msg);
    }
}
