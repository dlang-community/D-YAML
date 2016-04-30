module dyaml.stream;

enum BOM {
        UTF8,           /// UTF-8
        UTF16LE,        /// UTF-16 Little Endian
        UTF16BE,        /// UTF-16 Big Endian
        UTF32LE,        /// UTF-32 Little Endian
        UTF32BE,        /// UTF-32 Big Endian
}

import std.system;

private enum int NBOMS = 5;
immutable Endian[NBOMS] BOMEndian =
[ std.system.endian,
  Endian.littleEndian, Endian.bigEndian,
  Endian.littleEndian, Endian.bigEndian
  ];

immutable ubyte[][NBOMS] ByteOrderMarks =
[ [0xEF, 0xBB, 0xBF],
  [0xFF, 0xFE],
  [0xFE, 0xFF],
  [0xFF, 0xFE, 0x00, 0x00],
  [0x00, 0x00, 0xFE, 0xFF]
  ];

interface YStream {
	void writeExact(const void* buffer, size_t size);
	size_t write(const(ubyte)[] buffer);
	void flush();
	@property bool writeable();
}

class YMemoryStream : YStream {
	ubyte[] data;

	void writeExact(const void* buffer, size_t size) {
		data ~= cast(ubyte[])buffer[0 .. size];
	}

	size_t write(const(ubyte)[] buffer) {
		data ~= buffer;
		return buffer.length;
	}

	void flush() {}

	@property bool writeable() { return true; }
}

class YFile : YStream {
	static import std.stdio;
	std.stdio.File file;

	this(string fn) {
		this.file = std.stdio.File(fn, "w");
	}

	void writeExact(const void* buffer, size_t size) {
		this.file.write(cast(const ubyte[])buffer[0 .. size]);
	}

	size_t write(const(ubyte)[] buffer) {
		this.file.write(buffer);
		return buffer.length;
	}

	void flush() {
		this.file.flush();
	}

	@property bool writeable() { return true; }
}
