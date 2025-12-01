// High-level compressor for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Compressor state constants
const comp_state_block = 0 // in block
const comp_state_segment = 1 // in segment
const comp_state_start = 2 // at start

// Compressor provides high-level ZPAQ compression
pub struct Compressor {
mut:
	state  int       // current state
	z      ZPAQL     // ZPAQL VM for HCOMP
	pz     ZPAQL     // ZPAQL VM for PCOMP
	enc    Encoder   // arithmetic encoder
	pr     Predictor // prediction model
	input  &Reader = unsafe { nil }
	output &Writer = unsafe { nil }
	sha1   SHA1 // hash of compressed data
}

// Create a new compressor
pub fn Compressor.new() Compressor {
	return Compressor{
		state: comp_state_start
		z:     ZPAQL.new()
		pz:    ZPAQL.new()
		enc:   Encoder.new()
		pr:    Predictor.new()
		sha1:  SHA1.new()
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

// Start a new compression block with preset level
// level: 0=store, 1=fast, 2=normal, 3=max
pub fn (mut c Compressor) start_block(level int) {
	if c.state != comp_state_start {
		return
	}

	// Initialize based on level
	c.z.clear()

	// Write block header
	if c.output != unsafe { nil } {
		// Write ZPAQ block marker
		c.output.put(0x7A) // 'z'
		c.output.put(0x50) // 'P'
		c.output.put(0x51) // 'Q'
		c.output.put(0x01) // version 1

		// Write level byte
		c.output.put(level)
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
		// Write segment header
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
	}

	// Initialize encoder
	c.enc = Encoder.new()
	c.enc.init(mut c.pr, mut c.output)

	// Reset SHA1
	c.sha1 = SHA1.new()

	c.state = comp_state_segment
}

// Compress n bytes from input
// Returns true if more data available
pub fn (mut c Compressor) compress(n int) bool {
	if c.state != comp_state_segment || c.input == unsafe { nil } {
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

		// Compress byte
		c.enc.compress(ch)

		count++
	}

	return true
}

// End the current segment
pub fn (mut c Compressor) end_segment() {
	if c.state != comp_state_segment {
		return
	}

	// Write end of segment marker (256)
	// Encode the EOF symbol
	for i := 7; i >= 0; i-- {
		mut y := 1 // high bit is always 1 for EOF
		if i < 7 {
			y = 0
		}
		p := c.pr.predict()
		c.enc.encode(y, p)
		c.pr.update(y)
	}
	// Encode the trailing byte (0x00)
	for i := 7; i >= 0; i-- {
		y := 0
		p := c.pr.predict()
		c.enc.encode(y, p)
		c.pr.update(y)
	}

	// Flush encoder
	c.enc.flush()

	// Write SHA1 hash
	hash := c.sha1.result()
	if c.output != unsafe { nil } {
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
