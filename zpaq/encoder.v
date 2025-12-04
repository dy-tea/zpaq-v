// Arithmetic encoder for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Probability for EOF/data bit - libzpaq uses 0 for this
// p=0 means encode(1, 0) outputs bit 1 with probability 0
const eof_probability = 0

// Encoder implements arithmetic encoding with optional prediction
pub struct Encoder {
pub mut:
	low    u32 // low end of range
	high   u32 // high end of range
	pr     &Predictor = unsafe { nil }
	output &Writer    = unsafe { nil }
}

// Create a new encoder
pub fn Encoder.new() Encoder {
	return Encoder{
		low:  1
		high: 0xFFFFFFFF
	}
}

// Initialize encoder with predictor and output
pub fn (mut e Encoder) init(mut pr Predictor, mut output Writer) {
	unsafe {
		e.pr = &pr
		e.output = &output
	}
	e.low = 1
	e.high = 0xFFFFFFFF
}

// Set output writer
pub fn (mut e Encoder) set_output(mut output Writer) {
	unsafe {
		e.output = &output
	}
}

// Encode a bit with given probability (libzpaq compatible)
// p is probability of 1 in range (0..65535), where p/65536 is the actual probability
// Special case: p=0 is used for EOF marker encoding - this effectively makes
// y=1 very unlikely (probability 0), which is correct for EOF markers
// Uses 32-bit arithmetic with proper range scaling
pub fn (mut e Encoder) encode(y int, p int) {
	// Clamp probability to valid range (0..65535)
	// libzpaq allows p=0 for EOF marker encoding
	mut pr := p
	if pr < 0 {
		pr = 0
	}
	if pr > 65535 {
		pr = 65535
	}

	// Split range based on probability
	// mid = low + (range * p) / 65536
	// This matches libzpaq's exact calculation
	range_ := e.high - e.low
	mid := e.low + u32((u64(range_) * u64(pr)) >> 16)

	// libzpaq: if (y) high=mid; else low=mid+1;
	// y=1 means take lower portion [low, mid] (probability p)
	// y=0 means take upper portion (mid, high] (probability 1-p)
	if y != 0 {
		e.high = mid
	} else {
		e.low = mid + 1
	}

	// Output bytes when range is small enough
	// When top 8 bits match, output them
	for (e.high ^ e.low) < 0x1000000 {
		if e.output != unsafe { nil } {
			e.output.put(int(e.high >> 24))
		}
		e.low <<= 8
		e.high = (e.high << 8) | 0xFF
		// Prevent coding 4 zero bytes in a row (libzpaq compatibility)
		if e.low == 0 {
			e.low = 1
		}
	}
}

// Compress one byte using predictor (libzpaq compatible)
// Pass c=-1 to encode EOF marker
pub fn (mut e Encoder) compress(c int) {
	if e.pr == unsafe { nil } {
		return
	}

	// First encode EOF/data bit
	// y=1 means EOF, y=0 means data follows
	// Use small probability for EOF so data bytes are cheap to encode
	if c == -1 {
		// EOF marker (expensive)
		e.encode(1, eof_probability)
		return
	}

	// Data byte follows (cheap)
	e.encode(0, eof_probability)

	// Encode each bit MSB first
	for i := 7; i >= 0; i-- {
		y := (c >> i) & 1
		// Get probability - predictor returns 1..32767, scale to 1..65535
		p := e.pr.predict()
		// Scale: p * 65536 / 32768 = p * 2 + 1 to match libzpaq
		scaled_p := p * 2 + 1
		e.encode(y, scaled_p)
		e.pr.update(y)
	}
}

// Compress multiple bytes
pub fn (mut e Encoder) compress_bytes(data []u8) {
	for b in data {
		e.compress(int(b))
	}
}

// Flush remaining bits (libzpaq compatible)
pub fn (mut e Encoder) flush() {
	if e.output == unsafe { nil } {
		return
	}
	// Output remaining 4 bytes from high register
	e.output.put(int(e.high >> 24))
	e.output.put(int(e.high >> 16))
	e.output.put(int(e.high >> 8))
	e.output.put(int(e.high))
}

// Get current low value
pub fn (e &Encoder) get_low() u32 {
	return e.low
}

// Get current high value
pub fn (e &Encoder) get_high() u32 {
	return e.high
}
