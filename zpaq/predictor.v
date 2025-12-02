// Context model predictor for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Squash table: convert stretch output to probability
// squash(d) = 1/(1+exp(-d/64)) * 32768, clamped to [1, 32767]
const squash_table = init_squash_table()

// Stretch table: convert probability to log odds
// stretch(p) = ln(p/(32768-p)) * 64, inverse of squash
const stretch_table = init_stretch_table()

// dt2k table for MATCH model
const dt2k_table = init_dt2k_table()

// Initialize squash table using pre-computed values matching libzpaq
fn init_squash_table() [4096]int {
	mut t := [4096]int{}
	for i := -2047; i <= 2047; i++ {
		// squash(x) = 1/(1 + exp(-x/64)) scaled to 0..32767
		mut d := f64(i) / 64.0
		if d < -20.0 {
			d = -20.0
		}
		if d > 20.0 {
			d = 20.0
		}
		mut e := 0.0
		if d >= 0 {
			e = 1.0 / (1.0 + exp_approx(-d))
		} else {
			tmp := exp_approx(d)
			e = tmp / (1.0 + tmp)
		}
		v := int(32767.0 * e + 0.5)
		if v < 1 {
			t[i + 2047] = 1
		} else if v > 32767 {
			t[i + 2047] = 32767
		} else {
			t[i + 2047] = v
		}
	}
	return t
}

// Approximate exponential function
fn exp_approx(x f64) f64 {
	if x < -20.0 {
		return 0.0
	}
	if x > 20.0 {
		return 485165195.4 // exp(20)
	}
	// Taylor series: e^x = 1 + x + x^2/2! + x^3/3! + ...
	mut result := 1.0
	mut term := 1.0
	for i := 1; i < 40; i++ {
		term *= x / f64(i)
		result += term
		if term < 1e-15 && term > -1e-15 {
			break
		}
	}
	return result
}

// Initialize stretch table (inverse of squash)
fn init_stretch_table() [32768]int {
	mut t := [32768]int{}
	for i := 0; i < 32768; i++ {
		// stretch is inverse of squash
		// stretch(p) = ln(p/(32768-p)) * 64
		p := f64(i) / 32767.0
		if p <= 0.0 {
			t[i] = -2047
		} else if p >= 1.0 {
			t[i] = 2047
		} else {
			ln_odds := ln_approx(p / (1.0 - p))
			v := int(ln_odds * 64.0)
			if v < -2047 {
				t[i] = -2047
			} else if v > 2047 {
				t[i] = 2047
			} else {
				t[i] = v
			}
		}
	}
	return t
}

// Initialize dt2k table for match model
fn init_dt2k_table() [256]int {
	mut t := [256]int{}
	for i := 0; i < 256; i++ {
		// dt2k[i] = 2048 * (1 - 1/(i+1))
		t[i] = 2048 - 2048 / (i + 1)
	}
	return t
}

// Approximate natural logarithm
fn ln_approx(x f64) f64 {
	if x <= 0.0 {
		return -20.0
	}
	if x > 1e9 {
		return 20.0
	}
	// Use identity: ln(x) = 2 * atanh((x-1)/(x+1))
	// Taylor series for atanh
	y := (x - 1.0) / (x + 1.0)
	y2 := y * y
	mut result := y
	mut term := y
	for i := 1; i < 50; i++ {
		term *= y2
		result += term / f64(2 * i + 1)
		if term < 1e-15 && term > -1e-15 {
			break
		}
	}
	return 2.0 * result
}

// Squash function: convert stretch output to probability (1..32767)
pub fn squash(d int) int {
	mut idx := d + 2047
	if idx < 0 {
		idx = 0
	}
	if idx >= 4094 {
		idx = 4093
	}
	return squash_table[idx]
}

// Stretch function: convert probability (1..32767) to log odds
pub fn stretch(p int) int {
	mut idx := p
	if idx < 1 {
		idx = 1
	}
	if idx >= 32768 {
		idx = 32767
	}
	return stretch_table[idx]
}

// Clamp value to 12-bit range [-2048, 2047]
fn clamp2k(x int) int {
	if x < -2048 {
		return -2048
	}
	if x > 2047 {
		return 2047
	}
	return x
}

// Clamp value to 19-bit range [-262144, 262143]
fn clamp512k(x int) int {
	if x < -262144 {
		return -262144
	}
	if x > 262143 {
		return 262143
	}
	return x
}

// Component represents one model component
pub struct Component {
pub mut:
	ctype int   // component type
	cm    []u32 // context model table
	ht    []u8  // hash table
	a16   []u16 // weights for MIX2
	a     int   // first parameter
	b     int   // second parameter
	c     int   // third parameter
	cxt   u32   // current context
	limit int   // update rate
}

// Create a new component
pub fn Component.new() Component {
	return Component{
		ctype: 0
		cm:    []u32{}
		ht:    []u8{}
		a16:   []u16{}
		a:     0
		b:     0
		c:     0
		cxt:   0
		limit: 0
	}
}

// Predictor combines multiple context models
pub struct Predictor {
pub mut:
	c8    u32         // last 0-7 bits with leading 1
	hmap4 u32         // hash of last 4 bytes
	h     []u32       // context hashes from ZPAQL
	p     []int       // predictions for each component (stretch domain)
	comp  []Component // model components
	z     &ZPAQL = unsafe { nil }
	st    StateTable
}

// Create a new predictor
pub fn Predictor.new() Predictor {
	return Predictor{
		c8:    1
		hmap4: 1
		h:     []u32{}
		p:     []int{}
		comp:  []Component{}
		st:    StateTable.new()
	}
}

// Initialize the predictor from ZPAQL header
pub fn (mut pred Predictor) init(mut z ZPAQL) {
	unsafe {
		pred.z = z
	}
	pred.c8 = 1
	pred.hmap4 = 1

	// Parse header for components
	if z.header.len < 7 {
		// No components defined - this is store mode, don't create any components
		pred.comp = []Component{}
		pred.p = []int{}
		pred.h = []u32{}
		return
	}

	// Header format: hm hh ph pm n [comp1] [comp2] ... [compN] 0
	// hm = log2 size of M array
	// hh = log2 size of H array
	// ph = log2 size of P array (PCOMP)
	// pm = log2 size of M array (PCOMP)
	// n = number of components

	n := int(z.header[6])
	if n == 0 {
		// Zero components - store mode
		pred.comp = []Component{}
		pred.p = []int{}
		pred.h = []u32{}
		return
	}

	pred.comp = []Component{len: n}
	pred.p = []int{len: n}
	pred.h = []u32{len: n}

	// Initialize components based on header
	mut cp := 7 // current position in header
	for i := 0; i < n && cp < z.cend; i++ {
		ctype := int(z.header[cp])
		pred.comp[i] = Component.new()
		pred.comp[i].ctype = ctype

		// Read component parameters based on type
		match ctype {
			1 { // CONST - just outputs a constant probability
				pred.comp[i].a = int(z.header[cp + 1])
				cp += compsize[1]
			}
			2 { // CM - context model
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				pred.comp[i].limit = int(z.header[cp + 2]) // limit
				size := 1 << pred.comp[i].a
				pred.comp[i].cm = []u32{len: size}
				// Initialize with initial probabilities
				for j := 0; j < size; j++ {
					pred.comp[i].cm[j] = u32(1 << 15) // 50% probability
				}
				cp += compsize[2]
			}
			3 { // ICM - indirect context model
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				// ICM ht size is 64 * 2^sizebits (same as libzpaq's cr.ht.resize(64, cp[1]))
				size := 1 << pred.comp[i].a
				pred.comp[i].cm = []u32{len: 256}
				pred.comp[i].ht = []u8{len: size * 64}
				// Initialize CM with state-based probabilities
				for j := 0; j < 256; j++ {
					pred.comp[i].cm[j] = u32(pred.st.cminit(j) << 8)
				}
				cp += compsize[3]
			}
			4 { // MATCH - match model
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits (index)
				pred.comp[i].b = int(z.header[cp + 2]) // bufbits
				pred.comp[i].cm = []u32{len: 1 << pred.comp[i].a}
				pred.comp[i].ht = []u8{len: 1 << pred.comp[i].b}
				pred.comp[i].limit = 0 // position in buffer
				pred.comp[i].c = 0 // predicted bit
				pred.comp[i].cxt = 0 // bit position (0-7)
				cp += compsize[4]
			}
			5 { // AVG - average of two predictions
				pred.comp[i].a = int(z.header[cp + 1]) // first component
				pred.comp[i].b = int(z.header[cp + 2]) // second component
				pred.comp[i].c = int(z.header[cp + 3]) // weight (0-256)
				cp += compsize[5]
			}
			6 { // MIX2 - weighted mix of 2 components
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				size := 1 << pred.comp[i].a
				pred.comp[i].b = int(z.header[cp + 2]) // rate
				pred.comp[i].c = size
				pred.comp[i].a16 = []u16{len: size, init: 32768}
				cp += compsize[6]
			}
			7 { // MIX - weighted mix of multiple components
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				m := int(z.header[cp + 2]) // number of inputs
				pred.comp[i].b = m
				size := 1 << pred.comp[i].a
				pred.comp[i].cm = []u32{len: size * m}
				pred.comp[i].c = size
				// Initialize weights equally
				for j := 0; j < size * m; j++ {
					pred.comp[i].cm[j] = u32(65536 / m)
				}
				cp += compsize[7]
			}
			8 { // ISSE - indirect SSE chain
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				// ISSE ht size is 64 * 2^sizebits (same as libzpaq's cr.ht.resize(64, cp[1]))
				size := 1 << pred.comp[i].a
				pred.comp[i].ht = []u8{len: size * 64}
				pred.comp[i].cm = []u32{len: 512}
				// Initialize weights
				for j := 0; j < 256; j++ {
					pred.comp[i].cm[j * 2] = u32(1 << 15)
					st_init := pred.st.cminit(j)
					pred.comp[i].cm[j * 2 + 1] = u32(clamp512k(stretch(st_init >> 3) * 1024))
				}
				cp += compsize[8]
			}
			9 { // SSE - secondary symbol estimation
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				size := 1 << pred.comp[i].a
				pred.comp[i].cm = []u32{len: size * 32}
				pred.comp[i].limit = int(z.header[cp + 3]) * 4
				// Initialize with linear stretch
				for j := 0; j < size * 32; j++ {
					q := (j & 31) * 64 - 992
					pred.comp[i].cm[j] = u32(squash(q) << 17) | u32(z.header[cp + 2])
				}
				cp += compsize[9]
			}
			else {
				cp += 1
			}
		}
	}
}

// Initialize with default simple order-1 context model
fn (mut pred Predictor) init_default() {
	pred.comp = []Component{len: 1}
	pred.p = []int{len: 1}
	pred.h = []u32{len: 1}

	// Simple order-1 context model
	pred.comp[0] = Component.new()
	pred.comp[0].ctype = 2 // CM
	pred.comp[0].a = 8 // 256 contexts
	pred.comp[0].limit = 4 // learning rate
	pred.comp[0].cm = []u32{len: 256}
	for i := 0; i < 256; i++ {
		pred.comp[0].cm[i] = u32(1 << 15) // 50% probability
	}
}

// Check if this is a modeled predictor (has components)
pub fn (pred &Predictor) is_modeled() bool {
	return pred.comp.len > 0
}

// Find context in hash table, returning row index
fn (mut pred Predictor) find_ht(mut ht []u8, sizebits int, cxt u32) int {
	size := 1 << sizebits
	chk := int((cxt >> sizebits) & 255)
	h0 := int((cxt * 16) & u32(ht.len - 16))

	if ht[h0] == u8(chk) {
		return h0
	}
	h1 := h0 ^ 16
	if ht[h1] == u8(chk) {
		return h1
	}
	h2 := h0 ^ 32
	if ht[h2] == u8(chk) {
		return h2
	}

	// Not found, replace the one with lowest priority
	if ht[h0 + 1] <= ht[h1 + 1] && ht[h0 + 1] <= ht[h2 + 1] {
		for k := 0; k < 16; k++ {
			ht[h0 + k] = 0
		}
		ht[h0] = u8(chk)
		return h0
	} else if ht[h1 + 1] < ht[h2 + 1] {
		for k := 0; k < 16; k++ {
			ht[h1 + k] = 0
		}
		ht[h1] = u8(chk)
		return h1
	} else {
		for k := 0; k < 16; k++ {
			ht[h2 + k] = 0
		}
		ht[h2] = u8(chk)
		return h2
	}
}

// Predict next bit probability (1..32767)
pub fn (mut pred Predictor) predict() int {
	n := pred.comp.len
	if n == 0 {
		return 16384 // 50%
	}

	// Compute prediction for each component
	for i := 0; i < n; i++ {
		mut cr := &pred.comp[i]
		match cr.ctype {
			1 { // CONST
				pred.p[i] = (cr.a - 128) * 16
			}
			2 { // CM
				cr.cxt = u32(pred.h[i]) ^ pred.hmap4
				idx := int(cr.cxt) & (cr.cm.len - 1)
				pred.p[i] = stretch(int(cr.cm[idx] >> 16))
			}
			3 { // ICM
				if pred.c8 == 1 || (pred.c8 & 0xf0) == 16 {
					cr.c = pred.find_ht(mut cr.ht, cr.a + 2, u32(pred.h[i]) + 16 * pred.c8)
				}
				cr.cxt = u32(cr.ht[cr.c + int(pred.hmap4 & 15)])
				pred.p[i] = stretch(int(cr.cm[int(cr.cxt)] >> 8))
			}
			4 { // MATCH
				if cr.a == 0 {
					pred.p[i] = 0
				} else {
					// Predict based on match
					idx := (cr.limit - cr.b) & (cr.ht.len - 1)
					cr.c = int((cr.ht[idx] >> (7 - int(cr.cxt))) & 1)
					weight := dt2k_table[cr.a]
					pred.p[i] = stretch(weight * (cr.c * 2 - 1) + 16384)
				}
			}
			5 { // AVG
				if cr.a < n && cr.b < n {
					pred.p[i] = (pred.p[cr.a] * cr.c + pred.p[cr.b] * (256 - cr.c)) >> 8
				} else {
					pred.p[i] = 0
				}
			}
			6 { // MIX2
				cr.cxt = (u32(pred.h[i]) + (pred.c8 & u32(cr.b))) & u32(cr.c - 1)
				w := int(cr.a16[int(cr.cxt)])
				j := cr.a // first input component
				k := cr.a + 1 // second input component (assuming consecutive)
				if j < n && k < n && j > 0 && k > 0 {
					// Default to mixing with previous predictions
					pred.p[i] = clamp2k((w * pred.p[j - 1] + (65536 - w) * pred.p[k - 1]) >> 16)
				} else {
					pred.p[i] = 0
				}
			}
			7 { // MIX
				m := cr.b // number of inputs
				cr.cxt = u32(pred.h[i]) + pred.c8
				idx := int(cr.cxt & u32(cr.c - 1)) * m
				mut sum := 0
				for j := 0; j < m && (i - m + j) >= 0; j++ {
					wt := int(cr.cm[idx + j]) >> 8
					sum += wt * pred.p[i - m + j]
				}
				pred.p[i] = clamp2k(sum >> 8)
			}
			8 { // ISSE
				if pred.c8 == 1 || (pred.c8 & 0xf0) == 16 {
					cr.c = pred.find_ht(mut cr.ht, cr.a + 2, u32(pred.h[i]) + 16 * pred.c8)
				}
				cr.cxt = u32(cr.ht[cr.c + int(pred.hmap4 & 15)])
				wt0 := int(cr.cm[int(cr.cxt) * 2])
				wt1 := int(cr.cm[int(cr.cxt) * 2 + 1])
				if i > 0 {
					pred.p[i] = clamp2k((wt0 * pred.p[i - 1] + wt1 * 64) >> 16)
				} else {
					pred.p[i] = clamp2k(wt1 >> 10)
				}
			}
			9 { // SSE
				cr.cxt = (u32(pred.h[i]) + pred.c8) * 32
				mut pq := 0
				if i > 0 {
					pq = pred.p[i - 1] + 992
				} else {
					pq = 992
				}
				if pq < 0 {
					pq = 0
				}
				if pq > 1983 {
					pq = 1983
				}
				wt := pq & 63
				pq >>= 6
				idx := int(cr.cxt) + pq
				idx2 := idx + 1
				if idx >= 0 && idx2 < cr.cm.len {
					p1 := int(cr.cm[idx] >> 10)
					p2 := int(cr.cm[idx2] >> 10)
					pred.p[i] = stretch((p1 * (64 - wt) + p2 * wt) >> 13)
				} else {
					pred.p[i] = 0
				}
				cr.cxt = u32(idx) + u32(wt >> 5)
			}
			else {
				pred.p[i] = 0
			}
		}
	}

	// Return final prediction (from last component)
	return squash(pred.p[n - 1])
}

// Update model after seeing actual bit y (0 or 1)
pub fn (mut pred Predictor) update(y int) {
	n := pred.comp.len

	// Update each component
	for i := 0; i < n; i++ {
		mut cr := &pred.comp[i]
		match cr.ctype {
			1 { // CONST - no update
			}
			2 { // CM
				idx := int(cr.cxt) & (cr.cm.len - 1)
				mut v := cr.cm[idx]
				// Adjust prediction based on error
				err := y * 32767 - int(v >> 16)
				v = u32(int(v) + ((err * cr.limit + (1 << 12)) >> 13))
				cr.cm[idx] = v
			}
			3 { // ICM
				cr.ht[cr.c + int(pred.hmap4 & 15)] = u8(pred.st.next(int(cr.ht[cr.c +
					int(pred.hmap4 & 15)]), y))
				mut v := cr.cm[int(cr.cxt)]
				v = u32(int(v) + ((y * 32767 - int(v >> 8)) >> 2))
				cr.cm[int(cr.cxt)] = v
			}
			4 { // MATCH
				if cr.c != y {
					cr.a = 0 // mismatch
				}
				idx := cr.limit & (cr.ht.len - 1)
				cr.ht[idx] = u8((int(cr.ht[idx]) << 1) | y)
				cr.cxt++
				if cr.cxt >= 8 {
					cr.cxt = 0
					cr.limit = (cr.limit + 1) & (cr.ht.len - 1)
					if cr.a == 0 {
						// Look for match
						h := pred.h[i]
						match_pos := int(cr.cm[int(h) & (cr.cm.len - 1)])
						cr.b = cr.limit - match_pos
						if cr.b != 0 && (cr.b & (cr.ht.len - 1)) != 0 {
							// Count match length
							cr.a = 0
							for cr.a < 255 {
								idx1 := (cr.limit - cr.a - 1) & (cr.ht.len - 1)
								idx2 := (cr.limit - cr.a - cr.b - 1) & (cr.ht.len - 1)
								if cr.ht[idx1] != cr.ht[idx2] {
									break
								}
								cr.a++
							}
						}
					} else {
						if cr.a < 255 {
							cr.a++
						}
					}
					cr.cm[int(pred.h[i]) & (cr.cm.len - 1)] = u32(cr.limit)
				}
			}
			5 { // AVG - no update
			}
			6 { // MIX2
				err := (y * 32767 - squash(pred.p[i])) * cr.b >> 5
				if i >= 2 {
					mut w := int(cr.a16[int(cr.cxt)])
					w += (err * (pred.p[i - 2] - pred.p[i - 1]) + (1 << 12)) >> 13
					if w < 0 {
						w = 0
					}
					if w > 65535 {
						w = 65535
					}
					cr.a16[int(cr.cxt)] = u16(w)
				}
			}
			7 { // MIX
				m := cr.b
				err := (y * 32767 - squash(pred.p[i])) * 4
				idx := int(cr.cxt & u32(cr.c - 1)) * m
				for j := 0; j < m && (i - m + j) >= 0; j++ {
					wt := clamp512k(int(cr.cm[idx + j]) + ((err * pred.p[i - m + j] +
						(1 << 12)) >> 13))
					cr.cm[idx + j] = u32(wt)
				}
			}
			8 { // ISSE
				err := y * 32767 - squash(pred.p[i])
				// Bounds check: ISSE at index 0 has no previous component
				if i > 0 {
					wt0 := clamp512k(int(cr.cm[int(cr.cxt) * 2]) + ((err * pred.p[i - 1] +
						(1 << 12)) >> 13))
					wt1 := clamp512k(int(cr.cm[int(cr.cxt) * 2 + 1]) + ((err + 16) >> 5))
					cr.cm[int(cr.cxt) * 2] = u32(wt0)
					cr.cm[int(cr.cxt) * 2 + 1] = u32(wt1)
				}
				cr.ht[cr.c + int(pred.hmap4 & 15)] = u8(pred.st.next(int(cr.cxt), y))
			}
			9 { // SSE
				idx := int(cr.cxt) & (cr.cm.len - 1)
				mut v := cr.cm[idx]
				err := y * 32767 - int(v >> 17)
				count := int(v) & 1023
				if count < cr.limit {
					v = u32(int(v) + ((err * (cr.limit - count) + (1 << 12)) >> 13) + 1)
				}
				cr.cm[idx] = v
			}
			else {}
		}
	}

	// Update context
	pred.c8 = (pred.c8 << 1) | u32(y)
	if pred.c8 >= 256 {
		// Full byte received, run ZPAQL to update H
		if pred.z != unsafe { nil } {
			pred.z.run(pred.c8 - 256)
			for i := 0; i < n && i < pred.z.h.len; i++ {
				pred.h[i] = pred.z.h[i]
			}
		}
		pred.hmap4 = 1
		pred.c8 = 1
	} else if pred.c8 >= 16 && pred.c8 < 32 {
		pred.hmap4 = ((pred.hmap4 & 0xf) << 5) | (u32(y) << 4) | 1
	} else {
		pred.hmap4 = (pred.hmap4 & 0x1f0) | (((pred.hmap4 & 0xf) * 2 + u32(y)) & 0xf)
	}
}

// Reset predictor state
pub fn (mut pred Predictor) reset() {
	pred.c8 = 1
	pred.hmap4 = 1
	for i := 0; i < pred.h.len; i++ {
		pred.h[i] = 0
	}
}
