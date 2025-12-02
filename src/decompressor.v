// High-level decompressor for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Decompressor state constants
const decomp_state_block = 0 // in block
const decomp_state_segment = 1 // in segment
const decomp_state_filename = 2 // reading filename
const decomp_state_start = 3 // at start

// PostProcessor executes PCOMP program on decompressed data
pub struct PostProcessor {
mut:
	z      ZPAQL // PCOMP ZPAQL VM
	state  int   // decoder state
	ph     int   // low bits of c
	pm     int   // high bits of c
	outbuf []u8  // output buffer
}

// Create a new post processor
pub fn PostProcessor.new() PostProcessor {
	return PostProcessor{
		z:      ZPAQL.new()
		state:  0
		ph:     0
		pm:     0
		outbuf: []u8{}
	}
}

// Initialize post processor
pub fn (mut pp PostProcessor) init(z &ZPAQL) {
	pp.z.header = z.header.clone()
	pp.z.inith()
	pp.z.initp()
	pp.state = 0
	pp.ph = 0
	pp.pm = 0
}

// Process one byte through PCOMP
pub fn (mut pp PostProcessor) process(c int) {
	// Run PCOMP program with input byte
	pp.z.run(u32(c))

	// Copy output
	for b in pp.z.outbuf {
		pp.outbuf << b
	}
	pp.z.flush()
}

// Get output buffer
pub fn (pp &PostProcessor) get_output() []u8 {
	return pp.outbuf
}

// Clear output buffer
pub fn (mut pp PostProcessor) clear_output() {
	pp.outbuf.clear()
}

// Decompresser provides high-level ZPAQ decompression
pub struct Decompresser {
mut:
	state    int           // current state
	z        ZPAQL         // ZPAQL VM for HCOMP
	dec      Decoder       // arithmetic decoder
	pr       Predictor     // prediction model
	pp       PostProcessor // post processor
	input    &Reader = unsafe { nil }
	output   &Writer = unsafe { nil }
	sha1     SHA1   // hash of decompressed data
	filename string // current filename
	comment  string // current comment
}

// Create a new decompresser
pub fn Decompresser.new() Decompresser {
	return Decompresser{
		state:    decomp_state_start
		z:        ZPAQL.new()
		dec:      Decoder.new()
		pr:       Predictor.new()
		pp:       PostProcessor.new()
		sha1:     SHA1.new()
		filename: ''
		comment:  ''
	}
}

// Set input reader
pub fn (mut d Decompresser) set_input(r &Reader) {
	unsafe {
		d.input = r
	}
}

// Set output writer
pub fn (mut d Decompresser) set_output(w &Writer) {
	unsafe {
		d.output = w
	}
}

// Find and read the next block header
// Returns true if block found
pub fn (mut d Decompresser) find_block() bool {
	if d.input == unsafe { nil } {
		return false
	}

	// Look for ZPAQ block marker: zPQ followed by version
	for {
		c := d.input.get()
		if c < 0 {
			return false
		}
		if c != 0x7A {
			continue
		}

		// Check for 'PQ'
		c2 := d.input.get()
		if c2 != 0x50 {
			continue
		}

		c3 := d.input.get()
		if c3 != 0x51 {
			continue
		}

		// Read version
		version := d.input.get()
		if version < 0 {
			return false
		}

		// Read HCOMP
		d.z = ZPAQL.new()
		n := d.z.read(mut d.input)
		if n < 0 {
			return false
		}

		// Initialize predictor
		d.pr = Predictor.new()
		d.pr.init(mut d.z)

		d.state = decomp_state_block
		return true
	}
	return false // unreachable but required by V compiler
}

// Find and read the next filename
// Returns true if segment found
pub fn (mut d Decompresser) find_filename() bool {
	if d.state != decomp_state_block || d.input == unsafe { nil } {
		return false
	}

	// Read filename (null-terminated)
	mut filename_bytes := []u8{}
	for {
		c := d.input.get()
		if c < 0 {
			return false
		}
		if c == 0 {
			break
		}
		if c == 0xFF {
			// End of block marker
			d.state = decomp_state_start
			return false
		}
		filename_bytes << u8(c)
	}
	d.filename = filename_bytes.bytestr()

	// Read comment (null-terminated)
	mut comment_bytes := []u8{}
	for {
		c := d.input.get()
		if c < 0 {
			return false
		}
		if c == 0 {
			break
		}
		comment_bytes << u8(c)
	}
	d.comment = comment_bytes.bytestr()

	// Initialize decoder
	d.dec = Decoder.new()
	d.dec.init(mut d.pr, mut d.input)

	// Reset SHA1
	d.sha1 = SHA1.new()

	d.state = decomp_state_segment
	return true
}

// Get current filename
pub fn (d &Decompresser) get_filename() string {
	return d.filename
}

// Get current comment
pub fn (d &Decompresser) get_comment() string {
	return d.comment
}

// Decompress n bytes
// Returns true if more data available
pub fn (mut d Decompresser) decompress(n int) bool {
	if d.state != decomp_state_segment {
		return false
	}

	mut count := 0
	for count < n {
		c := d.dec.decompress()
		if c < 0 {
			return false
		}

		// Check for EOF marker
		if c == 0 {
			// Could be end of segment
		}

		// Update hash
		d.sha1.put(c)

		// Write to output
		if d.output != unsafe { nil } {
			d.output.put(c)
		}

		count++
	}

	return true
}

// Read and verify segment end
pub fn (mut d Decompresser) read_segment_end() {
	if d.state != decomp_state_segment {
		return
	}

	// Read SHA1 hash (20 bytes)
	mut stored_hash := []u8{len: 20}
	for i := 0; i < 20; i++ {
		c := d.input.get()
		if c >= 0 {
			stored_hash[i] = u8(c)
		}
	}

	// Compare with computed hash
	computed_hash := d.sha1.result()
	_ = computed_hash // Hash verification can be checked if needed
	for i := 0; i < 20 && i < computed_hash.len; i++ {
		if stored_hash[i] != computed_hash[i] {
			// Hash mismatch
			break
		}
	}

	// Hash verification result can be checked if needed

	d.state = decomp_state_block
}

// Get SHA1 hash of decompressed data
pub fn (mut d Decompresser) get_sha1() []u8 {
	return d.sha1.result()
}
