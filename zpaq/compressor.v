// High-level compressor for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Compressor state constants
const comp_state_block = 0 // in block
const comp_state_segment = 1 // in segment
const comp_state_start = 2 // at start

// ZPAQ block locator magic bytes (13-byte pattern that produces correct rolling hash)
// This pattern when followed by 'zPQ' produces the rolling hashes expected by libzpaq
const zpaq_block_locator = [u8(0x37), 0x6b, 0x53, 0x74, 0xa0, 0x31, 0x83, 0xd3, 0x8c, 0xb2, 0x28,
	0xb0, 0xd3]

// Compressor provides high-level ZPAQ compression
pub struct Compressor {
mut:
	state        int       // current state
	z            ZPAQL     // ZPAQL VM for HCOMP
	pz           ZPAQL     // ZPAQL VM for PCOMP
	enc          Encoder   // arithmetic encoder
	pr           Predictor // prediction model
	input        &Reader = unsafe { nil }
	output       &Writer = unsafe { nil }
	sha1         SHA1 // SHA1 hash of original uncompressed data for integrity verification
	level        int  // compression level (0-5)
	store_buf    []u8 // buffer for store mode
	store_size   u32  // bytes in store buffer
	first_byte   bool // true if this is first byte of segment (need to write PP mode)
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
		first_byte: true
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

// Write the block locator pattern (13 magic bytes + 'zPQ')
fn (mut c Compressor) write_block_locator() {
	if c.output == unsafe { nil } {
		return
	}
	// Write the 13-byte magic pattern that produces correct rolling hashes
	for b in zpaq_block_locator {
		c.output.put(int(b))
	}
	// Write 'zPQ'
	c.output.put(0x7a) // 'z'
	c.output.put(0x50) // 'P'
	c.output.put(0x51) // 'Q'
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

	// Parse header to find cend, hbegin, hend
	// Our header format: hm hh ph pm n [comp1]...[compN] 0 [HCOMP code] 0
	// Note: This is the raw content format without size prefix
	if c.z.header.len >= 5 {
		n := int(c.z.header[4])
		mut pos := 5
		// Skip component definitions
		for i := 0; i < n && pos < c.z.header.len; i++ {
			if pos >= c.z.header.len {
				break
			}
			ctype := int(c.z.header[pos])
			// Bounds check for ctype before accessing compsize array
			if ctype < 0 || ctype >= compsize.len {
				break
			}
			pos += compsize[ctype]
		}
		// pos now points to the 0 byte that ends component definitions
		c.z.cend = pos
		// hbegin is after the 0 that ends components
		if pos < c.z.header.len && c.z.header[pos] == 0 {
			pos++
		}
		c.z.hbegin = pos
		// Find end of HCOMP code - need to parse opcodes and skip operands
		// HCOMP code ends when we encounter a 0 byte that is NOT an operand
		// Opcode format: if (opcode & 7) == 7 and opcode > 0, it has a 1-byte operand
		// Special case: LJ (opcode 63) has a 2-byte operand
		for pos < c.z.header.len {
			op := c.z.header[pos]
			if op == 0 {
				// 0 byte that's not an operand = end of HCOMP
				break
			}
			pos++
			// Check if this opcode has operands
			if (op & 7) == 7 {
				// This opcode has a 1-byte operand (skip it)
				if op == 63 {
					// LJ has 2-byte operand
					pos += 2
				} else {
					pos += 1
				}
			}
		}
		c.z.hend = pos
	} else {
		c.z.cend = c.z.header.len
		c.z.hbegin = c.z.header.len
		c.z.hend = c.z.header.len
	}

	c.z.inith()
	c.z.initp()

	if c.output != unsafe { nil } {
		// Write 13-byte block locator magic + "zPQ" (compatible with libzpaq)
		c.write_block_locator()

		// Determine level byte:
		// Level 1: has at least 1 component (z.header[4] != 0)
		// Level 2: no components (z.header[4] == 0)
		zpaq_level := if c.z.header.len >= 5 && c.z.header[4] != 0 { 1 } else { 2 }
		c.output.put(zpaq_level)

		// Write block type (1 = compressed block)
		c.output.put(1)

		// Compute and write ZPAQL header size
		// COMP section: hm hh ph pm n [components] 0 (bytes 0 to cend inclusive)
		// HCOMP section: [HCOMP code] 0 (bytes hbegin to hend inclusive)
		// hsize = total bytes in COMP + HCOMP sections
		hsize := (c.z.cend + 1) + (c.z.hend - c.z.hbegin + 1)

		c.output.put(hsize & 0xFF)
		c.output.put((hsize >> 8) & 0xFF)

		// Write COMP section: hm hh ph pm n [components] 0
		for i := 0; i <= c.z.cend && i < c.z.header.len; i++ {
			c.output.put(int(c.z.header[i]))
		}

		// Write HCOMP section: [HCOMP code] 0
		for i := c.z.hbegin; i <= c.z.hend && i < c.z.header.len; i++ {
			c.output.put(int(c.z.header[i]))
		}
	}

	// Initialize predictor
	c.pr = Predictor.new()
	c.pr.init(&c.z)

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
	c.pr.init(&c.z)

	c.state = comp_state_block
}

// Start a new segment with optional filename and comment
pub fn (mut c Compressor) start_segment(filename string, comment string) {
	if c.state != comp_state_block {
		return
	}

	if c.output != unsafe { nil } {
		// Write segment marker (0x01)
		c.output.put(1)

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

	// Mark that we need to write post-processing mode
	c.first_byte = true

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

	// Write post-processing mode (0 = PASS) at start of first segment data
	// This is required by libzpaq format
	if c.first_byte {
		c.enc.compress(0) // 0 = PASS (no post-processing)
		c.first_byte = false
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
// libzpaq format: 4-byte big-endian length + PP mode + raw data, repeated. Length 0 = end.
fn (mut c Compressor) compress_store(n int) bool {
	if c.input == unsafe { nil } || c.output == unsafe { nil } {
		return false
	}

	// Write PP mode (0=PASS) at start of first chunk
	if c.first_byte {
		c.store_buf << 0 // PP mode = PASS
		c.store_size++
		c.first_byte = false
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

			// Flush encoder (writes remaining state bytes)
			c.enc.flush()

			// Note: No 4-zero-byte terminator for compressed mode
			// The encoder's flush() outputs the final state bytes
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
