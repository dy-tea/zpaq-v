// High-level compressor for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Compressor state constants
const comp_state_block = 0 // in block
const comp_state_segment = 1 // in segment
const comp_state_start = 2 // at start

// ZPAQ block locator tag (magic bytes 'zPQ')
const zpaq_block_tag = [u8(0x7A), 0x50, 0x51]

// ZPAQ segment locator tag
const zpaq_segment_tag = [u8(0x01)]

// Compressor provides high-level ZPAQ compression
pub struct Compressor {
mut:
	state      int       // current state
	z          ZPAQL     // ZPAQL VM for HCOMP
	pz         ZPAQL     // ZPAQL VM for PCOMP
	enc        Encoder   // arithmetic encoder
	pr         Predictor // prediction model
	input      &Reader = unsafe { nil }
	output     &Writer = unsafe { nil }
	sha1       SHA1   // SHA1 hash of original uncompressed data for integrity verification
	level      int    // compression level (0-5)
	store_buf  []u8   // buffer for store mode
	store_size u32    // bytes in store buffer
}

// Create a new compressor
pub fn Compressor.new() Compressor {
	return Compressor{
		state:      comp_state_start
		z:          ZPAQL.new()
		pz:         ZPAQL.new()
		enc:        Encoder.new()
		pr:         Predictor.new()
		sha1:       SHA1.new()
		level:      1
		store_buf:  []u8{cap: 65536}
		store_size: 0
	}
}

// Set input reader
pub fn (mut c Compressor) set_input(r &Reader) {
	unsafe {
		c.input = r
	}
}

// Set output writer
pub fn (mut c Compressor) set_output(w &Writer) {
	unsafe {
		c.output = w
	}
}

// Write a 4-byte locator tag for block/segment detection
fn (mut c Compressor) write_locator_tag(tag []u8) {
	if c.output == unsafe { nil } {
		return
	}
	// Write the 13-byte locator tag pattern
	// Tag consists of: 7 bytes of 0x00, followed by the tag bytes
	for _ in 0 .. 7 {
		c.output.put(0x00)
	}
	for b in tag {
		c.output.put(int(b))
	}
}

// Start a new compression block with preset level
// level: 0=store, 1=fast, 2=normal, 3=high, 4=max
pub fn (mut c Compressor) start_block(level int) {
	if c.state != comp_state_start {
		return
	}

	c.level = level

	// Get compression configuration for this level
	config := get_compression_level(level)

	// Initialize ZPAQL with header
	c.z.clear()
	c.z.header = config.hcomp.clone()
	c.z.cend = c.z.header.len
	c.z.hbegin = c.z.cend
	c.z.hend = c.z.cend
	c.z.inith()
	c.z.initp()

	if c.output != unsafe { nil } {
		// Write block locator tag: 7 zeros + 'zPQ'
		c.write_locator_tag(zpaq_block_tag)

		// Write block type (1 = compressed)
		c.output.put(1)

		// Write HCOMP header size (2 bytes, little-endian)
		hlen := c.z.header.len
		c.output.put(hlen & 0xFF)
		c.output.put((hlen >> 8) & 0xFF)

		// Write HCOMP header
		for b in c.z.header {
			c.output.put(int(b))
		}
	}

	// Initialize predictor
	c.pr = Predictor.new()
	c.pr.init(mut c.z)

	c.state = comp_state_block
}

// Start a new compression block with HCOMP string
pub fn (mut c Compressor) start_block_hcomp(hcomp string) {
	if c.state != comp_state_start {
		return
	}

	// Parse HCOMP and initialize
	c.z.header.clear()
	for b in hcomp.bytes() {
		c.z.header << b
	}
	c.z.inith()
	c.z.initp()

	// Initialize predictor
	c.pr = Predictor.new()
	c.pr.init(mut c.z)

	c.state = comp_state_block
}

// Start a new segment with optional filename and comment
pub fn (mut c Compressor) start_segment(filename string, comment string) {
	if c.state != comp_state_block {
		return
	}

	if c.output != unsafe { nil } {
		// Write segment locator tag
		c.write_locator_tag(zpaq_segment_tag)

		// Write filename (null-terminated)
		for b in filename.bytes() {
			c.output.put(int(b))
		}
		c.output.put(0)

		// Write comment (null-terminated)
		for b in comment.bytes() {
			c.output.put(int(b))
		}
		c.output.put(0)

		// Write segment flags (0 = reserved byte, required by libzpaq)
		c.output.put(0)
	}

	// Initialize encoder for this segment
	c.enc = Encoder.new()
	c.enc.init(mut c.pr, mut c.output)

	// Reset SHA1 for this segment
	c.sha1 = SHA1.new()

	// Reset predictor state for new segment
	c.pr.reset()

	// Reset store buffer for store mode
	c.store_buf.clear()
	c.store_size = 0

	c.state = comp_state_segment
}

// Compress n bytes from input
// Returns true if more data available
pub fn (mut c Compressor) compress(n int) bool {
	if c.state != comp_state_segment || c.input == unsafe { nil } {
		return false
	}

	// Level 0 = store (no compression)
	if c.level == 0 {
		return c.compress_store(n)
	}

	mut count := 0
	for count < n {
		ch := c.input.get()
		if ch < 0 {
			return false
		}

		// Update hash
		c.sha1.put(ch)

		// Compress byte
		c.enc.compress(ch)

		count++
	}

	return true
}

// Store mode compression (level 0) - no compression, just store with length prefix
// libzpaq format: 4-byte big-endian length + raw data, repeated. Length 0 = end.
fn (mut c Compressor) compress_store(n int) bool {
	if c.input == unsafe { nil } || c.output == unsafe { nil } {
		return false
	}

	mut count := 0
	for count < n {
		ch := c.input.get()
		if ch < 0 {
			return false
		}

		// Update hash
		c.sha1.put(ch)

		// Add to buffer
		c.store_buf << u8(ch)
		c.store_size++

		// Flush buffer when full (64KB chunks)
		if c.store_size >= 65536 {
			c.flush_store_buffer()
		}

		count++
	}

	return true
}

// Flush the store buffer to output with length prefix
fn (mut c Compressor) flush_store_buffer() {
	if c.output == unsafe { nil } || c.store_size == 0 {
		return
	}

	// Write 4-byte big-endian length
	c.output.put(int((c.store_size >> 24) & 0xFF))
	c.output.put(int((c.store_size >> 16) & 0xFF))
	c.output.put(int((c.store_size >> 8) & 0xFF))
	c.output.put(int(c.store_size & 0xFF))

	// Write raw data
	for b in c.store_buf {
		c.output.put(int(b))
	}

	// Clear buffer
	c.store_buf.clear()
	c.store_size = 0
}

// End the current segment
pub fn (mut c Compressor) end_segment() {
	if c.state != comp_state_segment {
		return
	}

	if c.output != unsafe { nil } {
		// Level 0 is store mode - flush remaining buffer and write terminator
		if c.level == 0 || !c.pr.is_modeled() {
			// Flush any remaining buffered data
			c.flush_store_buffer()

			// Write 4 zero bytes (length = 0 means end of data)
			c.output.put(0)
			c.output.put(0)
			c.output.put(0)
			c.output.put(0)
		} else {
			// Compressed mode: encode EOF marker using compress(-1)
			c.enc.compress(-1)

			// Flush encoder (writes remaining state)
			c.enc.flush()
		}

		// Compute SHA1 hash
		hash := c.sha1.result()

		// Write segment end marker with SHA1 (253) followed by 20-byte hash
		c.output.put(253)
		for b in hash {
			c.output.put(int(b))
		}
	}

	c.state = comp_state_block
}

// End the current block
pub fn (mut c Compressor) end_block() {
	if c.state != comp_state_block {
		return
	}

	// Write end of block marker
	if c.output != unsafe { nil } {
		c.output.put(0xFF)
	}

	c.state = comp_state_start
}

// Get SHA1 hash of compressed data
pub fn (mut c Compressor) get_sha1() []u8 {
	return c.sha1.result()
}
