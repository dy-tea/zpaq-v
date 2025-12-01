// Arithmetic encoder for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

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

// Encode a bit with given probability
// p is probability of 1 (1..32767)
pub fn (mut e Encoder) encode(y int, p int) {
	// Clamp probability to valid range
	mut pr := p
	if pr < 1 {
		pr = 1
	}
	if pr > 32766 {
		pr = 32766
	}

	// Split range based on probability
	// mid = low + (high-low) * p / 65536
	range_ := e.high - e.low
	mid := e.low + u32((u64(range_) * u64(pr)) >> 16)

	if y != 0 {
		e.low = mid + 1
	} else {
		e.high = mid
	}

	// Output bytes when range is small enough
	for (e.high ^ e.low) < 0x1000000 {
		if e.output != unsafe { nil } {
			e.output.put(int(e.high >> 24))
		}
		e.low <<= 8
		e.high = (e.high << 8) | 0xFF
	}
}

// Compress one byte using predictor
pub fn (mut e Encoder) compress(c int) {
	if e.pr == unsafe { nil } {
		return
	}

	// Encode each bit MSB first
	for i := 7; i >= 0; i-- {
		y := (c >> i) & 1
		// Get probability * 2 + 1 for scaling
		p := e.pr.predict() * 2 + 1
		e.encode(y, p)
		e.pr.update(y)
	}
}

// Compress multiple bytes
pub fn (mut e Encoder) compress_bytes(data []u8) {
	for b in data {
		e.compress(int(b))
	}
}

// Flush remaining bits
pub fn (mut e Encoder) flush() {
	if e.output == unsafe { nil } {
		return
	}
	// Output remaining bytes
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
