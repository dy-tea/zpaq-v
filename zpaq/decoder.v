// Arithmetic decoder for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Decoder implements arithmetic decoding with optional prediction
pub struct Decoder {
mut:
	low   u32 // low end of range
	high  u32 // high end of range
	code  u32 // current code
	pr    &Predictor = unsafe { nil }
	input &Reader    = unsafe { nil }
	buf   []u8 // input buffer
	pos   int  // position in buffer
}

// Create a new decoder
pub fn Decoder.new() Decoder {
	return Decoder{
		low:  1
		high: 0xFFFFFFFF
		code: 0
		buf:  []u8{}
		pos:  0
	}
}

// Initialize decoder with predictor and input
pub fn (mut d Decoder) init(mut pr Predictor, mut input Reader) {
	unsafe {
		d.pr = &pr
		d.input = &input
	}
	d.low = 1
	d.high = 0xFFFFFFFF

	// Read initial 4 code bytes
	d.code = 0
	for _ in 0 .. 4 {
		c := d.get()
		if c < 0 {
			d.code = (d.code << 8)
		} else {
			d.code = (d.code << 8) | u32(c)
		}
	}
}

// Set input reader
pub fn (mut d Decoder) set_input(mut input Reader) {
	unsafe {
		d.input = &input
	}
}

// Get one byte from input
pub fn (mut d Decoder) get() int {
	if d.input != unsafe { nil } {
		return d.input.get()
	}
	return -1
}

// Check if input is buffered
pub fn (d &Decoder) buffered() bool {
	return d.buf.len > d.pos
}

// Decode a bit given probability (libzpaq compatible)
// p is probability of 1 in range (0..65535), where p/65536 is the actual probability
// Special case: p=0 is used for EOF marker decoding - this effectively makes
// y=1 very unlikely (probability 0), which is correct for detecting EOF markers
pub fn (mut d Decoder) decode(p int) int {
	// Clamp probability - allow 0 for EOF bit
	mut pr := p
	if pr < 0 {
		pr = 0
	}
	if pr > 65535 {
		pr = 65535
	}

	// Split range based on probability
	range_ := d.high - d.low
	mid := d.low + u32((u64(range_) * u64(pr)) >> 16)

	// Determine bit based on code position
	// libzpaq: if (curr<=mid) y=1, high=mid; else y=0, low=mid+1;
	// y=1 means code is in lower half (probability p), y=0 means upper half (probability 1-p)
	mut y := 0
	if d.code <= mid {
		y = 1
		d.high = mid
	} else {
		y = 0
		d.low = mid + 1
	}

	// Read more bytes when range is small
	for (d.high ^ d.low) < 0x1000000 {
		d.low <<= 8
		d.high = (d.high << 8) | 0xFF
		// Prevent decoding issues with 4 zero bytes (libzpaq compatibility)
		if d.low == 0 {
			d.low = 1
		}
		c := d.get()
		if c < 0 {
			d.code = (d.code << 8)
		} else {
			d.code = (d.code << 8) | u32(c)
		}
	}

	return y
}

// Decompress one byte using predictor (libzpaq compatible)
// Returns -1 on EOF
pub fn (mut d Decoder) decompress() int {
	if d.pr == unsafe { nil } {
		return -1
	}

	// First, decode EOF bit
	eof_bit := d.decode(eof_probability)
	if eof_bit != 0 {
		return -1 // EOF
	}

	// Decode 8 bits using predictor
	mut c := u32(1)
	for c < 256 {
		p := d.pr.predict()
		// Scale: p * 65536 / 32768 = p * 2
		scaled_p := p * 2 + 1 // +1 to match libzpaq's p*2+1
		y := d.decode(scaled_p)
		d.pr.update(y)
		c = (c << 1) | u32(y)
	}

	return int(c) - 256
}

// Skip n bytes without decoding
pub fn (mut d Decoder) skip() int {
	// Read one byte from input
	return d.get()
}

// Get current low value
pub fn (d &Decoder) get_low() u32 {
	return d.low
}

// Get current high value
pub fn (d &Decoder) get_high() u32 {
	return d.high
}

// Get current code value
pub fn (d &Decoder) get_code() u32 {
	return d.code
}
