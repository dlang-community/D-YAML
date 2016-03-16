module dyaml.stream;

interface YStream {
	void writeExact(const void* buffer, size_t size);
	size_t write(const(ubyte)[] buffer);
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
}

class YFile : YStream {
	static import std.stdio;
	std.stdio.File file;

	this(string fn) {
		this.file = std.stdio.File(fn, "w");
	}

	void writeExact(const void* buffer, size_t size) {
		this.file.write(buffer[0 .. size]);
	}

	size_t write(const(ubyte)[] buffer) {
		this.file.write(buffer[0 .. size]);
	}
}
