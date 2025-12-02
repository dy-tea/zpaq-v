// ZPAQ I/O interfaces
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Reader interface for input streams
pub interface Reader {
mut:
	// Read one byte, return -1 on EOF
	get() int
	// Read up to buf.len bytes into buf, return bytes read
	read(mut buf []u8) int
}

// Writer interface for output streams
pub interface Writer {
mut:
	// Write one byte
	put(c int)
	// Write buffer
	write(buf []u8)
}

// Convert 2 bytes to u16 (little-endian)
pub fn to_u16(p []u8) int {
	if p.len < 2 {
		return 0
	}
	return int(p[0]) + int(p[1]) * 256
}

// Convert 4 bytes to u32 (little-endian)
pub fn to_u32(p []u8) u32 {
	if p.len < 4 {
		return 0
	}
	return u32(p[0]) + u32(p[1]) << 8 + u32(p[2]) << 16 + u32(p[3]) << 24
}

// FileReader reads from a byte buffer
pub struct FileReader {
mut:
	data []u8
	pos  int
}

// Create a new FileReader from byte data
pub fn FileReader.new(data []u8) FileReader {
	return FileReader{
		data: data
		pos:  0
	}
}

// Read one byte, return -1 on EOF
pub fn (mut f FileReader) get() int {
	if f.pos >= f.data.len {
		return -1
	}
	c := f.data[f.pos]
	f.pos++
	return int(c)
}

// Get current position
pub fn (f &FileReader) position() int {
	return f.pos
}

// Read bytes into buffer, return count
pub fn (mut f FileReader) read(mut buf []u8) int {
	mut n := 0
	for i := 0; i < buf.len && f.pos < f.data.len; i++ {
		buf[i] = f.data[f.pos]
		f.pos++
		n++
	}
	return n
}

// FileWriter writes to a byte buffer
pub struct FileWriter {
mut:
	data []u8
}

// Create a new FileWriter
pub fn FileWriter.new() FileWriter {
	return FileWriter{
		data: []u8{}
	}
}

// Write one byte
pub fn (mut f FileWriter) put(c int) {
	f.data << u8(c)
}

// Write buffer
pub fn (mut f FileWriter) write(buf []u8) {
	for b in buf {
		f.data << b
	}
}

// Get the written data
pub fn (f &FileWriter) bytes() []u8 {
	return f.data
}

// StringBuffer implements both Reader and Writer on a byte buffer
pub struct StringBuffer {
mut:
	data     []u8
	read_pos int
}

// Create a new StringBuffer
pub fn StringBuffer.new() StringBuffer {
	return StringBuffer{
		data:     []u8{}
		read_pos: 0
	}
}

// Create StringBuffer from existing data
pub fn StringBuffer.from_bytes(data []u8) StringBuffer {
	return StringBuffer{
		data:     data.clone()
		read_pos: 0
	}
}

// Read one byte, return -1 on EOF
pub fn (mut s StringBuffer) get() int {
	if s.read_pos >= s.data.len {
		return -1
	}
	c := s.data[s.read_pos]
	s.read_pos++
	return int(c)
}

// Read bytes into buffer, return count
pub fn (mut s StringBuffer) read(mut buf []u8) int {
	mut n := 0
	for i := 0; i < buf.len && s.read_pos < s.data.len; i++ {
		buf[i] = s.data[s.read_pos]
		s.read_pos++
		n++
	}
	return n
}

// Write one byte
pub fn (mut s StringBuffer) put(c int) {
	s.data << u8(c)
}

// Write buffer
pub fn (mut s StringBuffer) write(buf []u8) {
	for b in buf {
		s.data << b
	}
}

// Get the underlying data
pub fn (s &StringBuffer) bytes() []u8 {
	return s.data
}

// Get length
pub fn (s &StringBuffer) len() int {
	return s.data.len
}

// Reset read position
pub fn (mut s StringBuffer) reset_read() {
	s.read_pos = 0
}

// Clear all data
pub fn (mut s StringBuffer) clear() {
	s.data.clear()
	s.read_pos = 0
}
