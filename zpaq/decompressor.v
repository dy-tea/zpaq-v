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
	state       int           // current state
	z           ZPAQL         // ZPAQL VM for HCOMP
	dec         Decoder       // arithmetic decoder
	pr          Predictor     // prediction model
	pp          PostProcessor // post processor
	input       &Reader = unsafe { nil }
	output      &Writer = unsafe { nil }
	sha1        SHA1   // hash of decompressed data
	filename    string // current filename
	comment     string // current comment
	store_count u32    // remaining bytes in current store chunk
	first_seg   bool   // first segment in block (need to init decoder)
}

// Create a new decompresser
pub fn Decompresser.new() Decompresser {
	return Decompresser{
		state:       decomp_state_start
		z:           ZPAQL.new()
		dec:         Decoder.new()
		pr:          Predictor.new()
		pp:          PostProcessor.new()
		sha1:        SHA1.new()
		filename:    ''
		comment:     ''
		store_count: 0
		first_seg:   true
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

		// Read HCOMP header size (2 bytes, little-endian)
		len_lo := d.input.get()
		len_hi := d.input.get()
		if len_lo < 0 || len_hi < 0 {
			return false
		}
		hlen := len_lo | (len_hi << 8)

		// Read HCOMP header bytes
		d.z = ZPAQL.new()
		d.z.header.clear()
		for i := 0; i < hlen; i++ {
			b := d.input.get()
			if b < 0 {
				return false
			}
			d.z.header << u8(b)
		}

		// Parse header to find cend, hbegin, hend
		// Header format: hm hh ph pm n [comp1]...[compN] 0 [HCOMP code] 0 [PCOMP code] 0
		if hlen >= 5 {
			n := int(d.z.header[4])
			mut pos := 5
			// Skip component definitions
			for i := 0; i < n && pos < hlen; i++ {
				if pos >= hlen {
					break
				}
				ctype := int(d.z.header[pos])
				// Bounds check for ctype before accessing compsize array
				if ctype < 0 || ctype >= compsize.len {
					break
				}
				pos += compsize[ctype]
			}
			// pos now points to the 0 byte that ends component definitions
			d.z.cend = pos
			// hbegin is after the 0 that ends components
			if pos < hlen && d.z.header[pos] == 0 {
				pos++
			}
			d.z.hbegin = pos
			// Find end of HCOMP code (look for 0 byte or HALT instruction)
			for pos < hlen {
				if d.z.header[pos] == 0 {
					break
				}
				pos++
			}
			d.z.hend = pos
		} else {
			d.z.cend = hlen
			d.z.hbegin = hlen
			d.z.hend = hlen
		}

		// Initialize arrays
		d.z.inith()
		d.z.initp()

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

	// Skip any leading zeros (part of locator tag pattern)
	mut marker := 0
	for {
		marker = d.input.get()
		if marker < 0 {
			return false
		}
		if marker != 0 {
			break
		}
	}

	// Check segment marker (1) or end of block (255)
	if marker == 0xFF {
		// End of block marker
		d.state = decomp_state_start
		return false
	}
	// marker should be 1 for a valid segment; other values indicate format error
	// but we continue anyway for robustness

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
			// End of block marker encountered unexpectedly
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

	// Read reserved byte (must be 0 in libzpaq format)
	reserved := d.input.get()
	if reserved < 0 {
		return false
	}
	// Note: reserved byte is ignored for now

	// Only initialize decoder for compressed mode (not store mode)
	// For store mode, we read raw bytes without arithmetic decoding
	// A new decoder is created for each segment to ensure clean state
	if d.pr.is_modeled() {
		d.dec = Decoder.new()
		d.dec.init(mut d.pr, mut d.input)
	}

	// Reset SHA1
	d.sha1 = SHA1.new()

	// Reset store count for store mode
	d.store_count = 0
	d.first_seg = true

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

// Decompress n bytes or all remaining if n < 0
// Returns true if more data available
pub fn (mut d Decompresser) decompress(n int) bool {
	if d.state != decomp_state_segment {
		return false
	}

	// Check if using store mode (no components) or compressed mode
	if !d.pr.is_modeled() {
		return d.decompress_store(n)
	}

	// Compressed mode
	mut count := 0
	mut limit := n
	if limit < 0 {
		limit = 0x7FFFFFFF // decompress all
	}

	for count < limit {
		c := d.dec.decompress()
		if c < 0 {
			// EOF marker reached
			return false
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

// Decompress store mode (raw bytes with length prefix)
fn (mut d Decompresser) decompress_store(n int) bool {
	if d.input == unsafe { nil } {
		return false
	}

	mut count := 0
	mut limit := n
	if limit < 0 {
		limit = 0x7FFFFFFF // decompress all
	}

	for count < limit {
		// Read next chunk if current one is exhausted
		if d.store_count == 0 {
			// Read 4-byte big-endian length
			b0 := d.input.get()
			b1 := d.input.get()
			b2 := d.input.get()
			b3 := d.input.get()

			if b0 < 0 || b1 < 0 || b2 < 0 || b3 < 0 {
				return false
			}

			d.store_count = (u32(b0) << 24) | (u32(b1) << 16) | (u32(b2) << 8) | u32(b3)

			// Length 0 means end of data
			if d.store_count == 0 {
				return false
			}
		}

		// Read one byte from current chunk
		c := d.input.get()
		if c < 0 {
			return false
		}

		// Update hash
		d.sha1.put(c)

		// Write to output
		if d.output != unsafe { nil } {
			d.output.put(c)
		}

		d.store_count--
		count++
	}

	return true
}

// Read and verify segment end
pub fn (mut d Decompresser) read_segment_end() {
	if d.state != decomp_state_segment {
		return
	}

	// Read segment end marker
	// Format: 253 + 20 bytes SHA1, or 254 (no checksum)
	marker := d.input.get()

	if marker == 253 {
		// Read SHA1 hash (20 bytes)
		mut stored_hash := []u8{len: 20}
		for i := 0; i < 20; i++ {
			c := d.input.get()
			if c >= 0 {
				stored_hash[i] = u8(c)
			}
		}

		// Compare with computed hash (optional verification)
		computed_hash := d.sha1.result()
		mut hash_match := true
		for i := 0; i < 20 && i < computed_hash.len; i++ {
			if stored_hash[i] != computed_hash[i] {
				hash_match = false
				break
			}
		}
		// hash_match can be used for verification if needed
		_ = hash_match
	} else if marker == 254 {
		// No checksum, nothing more to read
	}
	// Other values are errors but we ignore them for robustness

	d.state = decomp_state_block
}

// Get SHA1 hash of decompressed data
pub fn (mut d Decompresser) get_sha1() []u8 {
	return d.sha1.result()
}
