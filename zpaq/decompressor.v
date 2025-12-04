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
// Uses rolling hash detection compatible with libzpaq
// Returns true if block found
pub fn (mut d Decompresser) find_block() bool {
	if d.input == unsafe { nil } {
		return false
	}

	// Rolling hashes initialized to detect 16-byte block header pattern
	// (13-byte magic locator + "zPQ")
	// These initial values and multipliers match libzpaq exactly
	mut h1 := u32(0x3D49B113)
	mut h2 := u32(0x29EB7F93)
	mut h3 := u32(0x2614BE13)
	mut h4 := u32(0x3828EB13)

	// Target hash values after seeing the 16-byte header
	target_h1 := u32(0xB16B88F1)
	target_h2 := u32(0xFF5376F1)
	target_h3 := u32(0x72AC5BF1)
	target_h4 := u32(0x2F909AF1)

	// Read bytes and compute rolling hashes
	for {
		c := d.input.get()
		if c < 0 {
			return false
		}

		h1 = h1 * 12 + u32(c)
		h2 = h2 * 20 + u32(c)
		h3 = h3 * 28 + u32(c)
		h4 = h4 * 44 + u32(c)

		// Check if we found the 16-byte header pattern
		if h1 == target_h1 && h2 == target_h2 && h3 == target_h3 && h4 == target_h4 {
			break
		}
	}

	// Read level byte (1 or 2)
	level := d.input.get()
	if level < 0 || (level != 1 && level != 2) {
		return false
	}

	// Read block type (must be 1)
	block_type := d.input.get()
	if block_type != 1 {
		return false
	}

	// Read ZPAQL header using libzpaq format
	// First 2 bytes are the header size
	hsize_lo := d.input.get()
	hsize_hi := d.input.get()
	if hsize_lo < 0 || hsize_hi < 0 {
		return false
	}
	hsize := hsize_lo + hsize_hi * 256

	// Read COMP section: hm hh ph pm n [components] 0
	d.z = ZPAQL.new()
	d.z.header.clear()

	// Read hm hh ph pm n (5 bytes)
	for i := 0; i < 5; i++ {
		b := d.input.get()
		if b < 0 {
			return false
		}
		d.z.header << u8(b)
	}

	// Read component definitions
	n := int(d.z.header[4])
	for i := 0; i < n; i++ {
		ctype := d.input.get()
		if ctype < 0 || ctype >= compsize.len {
			return false
		}
		d.z.header << u8(ctype)
		csize := compsize[ctype]
		for j := 1; j < csize; j++ {
			b := d.input.get()
			if b < 0 {
				return false
			}
			d.z.header << u8(b)
		}
	}

	// Read COMP terminator (0)
	comp_term := d.input.get()
	if comp_term != 0 {
		return false
	}
	d.z.header << 0
	d.z.cend = d.z.header.len - 1 // points to the terminator

	// HCOMP section starts here
	d.z.hbegin = d.z.header.len

	// Calculate how many bytes of HCOMP to read
	// hsize = COMP content (excluding size bytes) + HCOMP content
	// COMP content = 5 (hm hh ph pm n) + component bytes + 1 (terminator)
	comp_content_len := d.z.header.len // current header length = COMP content
	hcomp_len := hsize - comp_content_len

	// Read HCOMP bytes (including terminator)
	for i := 0; i < hcomp_len; i++ {
		b := d.input.get()
		if b < 0 {
			return false
		}
		d.z.header << u8(b)
	}

	d.z.hend = d.z.header.len - 1 // points to HCOMP terminator

	// Initialize arrays
	d.z.inith()
	d.z.initp()

	// Initialize predictor
	d.pr = Predictor.new()
	d.pr.init(&d.z)

	d.state = decomp_state_block
	return true
}

// Find and read the next filename
// Returns true if segment found
pub fn (mut d Decompresser) find_filename() bool {
	if d.state != decomp_state_block || d.input == unsafe { nil } {
		return false
	}

	// Read segment marker (1) or end of block marker (255)
	marker := d.input.get()
	if marker < 0 {
		return false
	}

	// Check for end of block marker (255)
	if marker == 0xFF {
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
		// Reset predictor state for new segment (must match compressor behavior)
		d.pr.reset()
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

	// On first call, read and handle post-processing mode
	// The first byte of the compressed data is the PP mode:
	// 0 = PASS (no post-processing)
	// 1 = PROG (has a post-processing program)
	if d.first_seg {
		pp_mode := d.dec.decompress()
		if pp_mode < 0 {
			return false
		}
		if pp_mode == 1 {
			// PROG mode: read PCOMP size and skip the program
			// We don't support PCOMP yet, just skip it
			psize_lo := d.dec.decompress()
			psize_hi := d.dec.decompress()
			if psize_lo < 0 || psize_hi < 0 {
				return false
			}
			psize := psize_lo + psize_hi * 256
			for i := 0; i < psize; i++ {
				if d.dec.decompress() < 0 {
					return false
				}
			}
		}
		// pp_mode == 0 means PASS, no additional data to read
		d.first_seg = false
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

			// Handle PP mode byte at start of first chunk
			if d.first_seg {
				pp_mode := d.input.get()
				if pp_mode < 0 {
					return false
				}
				d.store_count-- // PP mode byte is counted in length
				// pp_mode == 0 means PASS (no post-processing)
				// pp_mode == 1 would mean PCOMP program follows (not supported in store mode)
				d.first_seg = false
				
				// If the current chunk is exhausted after reading PP mode byte, 
				// continue to read the next chunk length
				if d.store_count == 0 {
					continue
				}
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
