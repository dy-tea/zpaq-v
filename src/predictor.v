// Context model predictor for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Squash table: convert log probability to linear
const squash_table = init_squash_table()

// Stretch table: convert linear probability to log
const stretch_table = init_stretch_table()

// Initialize squash table
fn init_squash_table() [4096]int {
	mut t := [4096]int{}
	for i := -2047; i <= 2047; i++ {
		// squash(x) = 1/(1 + exp(-x/64))
		// Scaled to 0..4095
		mut d := f64(i) / 64.0
		if d < -20.0 {
			d = -20.0
		}
		if d > 20.0 {
			d = 20.0
		}
		mut e := 0.0
		// Use Taylor series approximation for small values
		if d >= 0 {
			e = 1.0 / (1.0 + exp_approx(-d))
		} else {
			tmp := exp_approx(d)
			e = tmp / (1.0 + tmp)
		}
		t[i + 2047] = int(4095.0 * e + 0.5)
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
	for i := 1; i < 30; i++ {
		term *= x / f64(i)
		result += term
		if term < 1e-10 && term > -1e-10 {
			break
		}
	}
	return result
}

// Initialize stretch table (inverse of squash)
fn init_stretch_table() [4096]int {
	mut t := [4096]int{}
	for i := 0; i < 4096; i++ {
		// stretch is inverse of squash
		// stretch(p) = ln(p/(1-p)) * 64
		p := f64(i) / 4095.0
		if p <= 0.0 {
			t[i] = -2047
		} else if p >= 1.0 {
			t[i] = 2047
		} else {
			ln_odds := ln_approx(p / (1.0 - p))
			v := int(ln_odds * 64.0 + 0.5)
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
	for i := 1; i < 30; i++ {
		term *= y2
		result += term / f64(2 * i + 1)
		if term < 1e-10 && term > -1e-10 {
			break
		}
	}
	return 2.0 * result
}

// Squash function: convert stretch output to probability (0..4095)
pub fn squash(d int) int {
	idx := d + 2047
	if idx < 0 {
		return 0
	}
	if idx >= 4096 {
		return 4095
	}
	return squash_table[idx]
}

// Stretch function: convert probability (0..4095) to log odds
pub fn stretch(p int) int {
	if p < 0 {
		return stretch_table[0]
	}
	if p >= 4096 {
		return stretch_table[4095]
	}
	return stretch_table[p]
}

// Component represents one model component
pub struct Component {
mut:
	ctype int   // component type
	cm    []u32 // context model
	ht    []u8  // hash table
	a     int   // parameters
	b     int
	c     int
	limit int // update limit
}

// Create a new component
pub fn Component.new() Component {
	return Component{
		ctype: 0
		cm:    []u32{}
		ht:    []u8{}
		a:     0
		b:     0
		c:     0
		limit: 0
	}
}

// Predictor combines multiple context models
pub struct Predictor {
mut:
	c8    u32 // last 0-7 bits with leading 1
	hmap4 u32 // hash of last 4 bytes

	comp  []Component // model components
	z     &ZPAQL = unsafe { nil }
	st    StateTable
	pr    []int // predictions for each component
	state []u8  // bit history states
}

// Create a new predictor
pub fn Predictor.new() Predictor {
	return Predictor{
		c8:    1
		hmap4: 0
		comp:  []Component{}
		st:    StateTable.new()
		pr:    []int{}
		state: []u8{}
	}
}

// Initialize the predictor from ZPAQL header
pub fn (mut p Predictor) init(mut z ZPAQL) {
	p.z = z
	p.c8 = 1
	p.hmap4 = 0

	// Parse header for components
	if z.header.len < 3 {
		return
	}

	// Read number of components
	n := if z.header.len > 2 { int(z.header[2]) } else { 0 }

	p.comp = []Component{len: n}
	p.pr = []int{len: n}

	// Initialize components based on header
	mut pos := 3
	for i := 0; i < n && pos < z.header.len; i++ {
		ctype := int(z.header[pos])
		pos++

		p.comp[i] = Component.new()
		p.comp[i].ctype = ctype

		// Get component size
		csz := if ctype < compsize.len { compsize[ctype] } else { 1 }

		// Read parameters
		if csz >= 2 && pos < z.header.len {
			p.comp[i].a = int(z.header[pos])
			pos++
		}
		if csz >= 3 && pos < z.header.len {
			p.comp[i].b = int(z.header[pos])
			pos++
		}
		if csz >= 4 && pos < z.header.len {
			p.comp[i].c = int(z.header[pos])
			pos++
		}

		// Initialize component arrays based on type
		match ctype {
			2 { // CM
				size := 1 << p.comp[i].a
				p.comp[i].cm = []u32{len: size, init: 0x80000000}
				p.comp[i].limit = 1023
			}
			3 { // ICM
				size := 1 << p.comp[i].a
				p.comp[i].cm = []u32{len: size}
				p.comp[i].ht = []u8{len: 1 << (p.comp[i].b + 2)}
			}
			4 { // MATCH
				size := 1 << p.comp[i].a
				p.comp[i].cm = []u32{len: size}
				p.comp[i].ht = []u8{len: 1 << p.comp[i].b}
			}
			6 { // MIX2
				p.comp[i].cm = []u32{len: 1 << p.comp[i].a, init: 0x80000000}
			}
			7 { // MIX
				size := 1 << p.comp[i].a
				p.comp[i].cm = []u32{len: size}
			}
			8 { // ISSE
				size := 1 << p.comp[i].a
				p.comp[i].cm = []u32{len: size}
				p.comp[i].ht = []u8{len: size}
			}
			9 { // SSE
				size := 1 << p.comp[i].a
				p.comp[i].cm = []u32{len: size * 33}
			}
			else {}
		}
	}

	// Initialize state array
	p.state = []u8{len: if p.comp.len > 0 { p.comp.len * 256 } else { 256 }}
}

// Predict next bit probability (0..4095)
pub fn (mut p Predictor) predict() int {
	if p.comp.len == 0 {
		return 2048
	}

	// Combine predictions from all components
	mut pr := 2048

	for i := 0; i < p.comp.len; i++ {
		match p.comp[i].ctype {
			1 { // CONST
				p.pr[i] = p.comp[i].a * 16
			}
			2 { // CM
				// Use context to look up prediction
				ctx := int(p.c8)
				if ctx < p.comp[i].cm.len {
					p.pr[i] = int(p.comp[i].cm[ctx] >> 17)
				} else {
					p.pr[i] = 2048
				}
			}
			3 { // ICM
				p.pr[i] = 2048
			}
			4 { // MATCH
				p.pr[i] = 2048
			}
			5 { // AVG
				// Average of two predictions
				if p.comp[i].a < p.pr.len && p.comp[i].b < p.pr.len {
					p.pr[i] = (p.pr[p.comp[i].a] + p.pr[p.comp[i].b] + 1) >> 1
				}
			}
			6 { // MIX2
				// Weighted mix of two predictions
				if p.comp[i].a < p.pr.len && p.comp[i].b < p.pr.len {
					w := 2048 // equal weight
					p.pr[i] = (p.pr[p.comp[i].a] * w + p.pr[p.comp[i].b] * (4096 - w)) >> 12
				}
			}
			7 { // MIX
				p.pr[i] = 2048
			}
			8 { // ISSE
				p.pr[i] = 2048
			}
			9 { // SSE
				p.pr[i] = 2048
			}
			else {
				p.pr[i] = 2048
			}
		}
	}

	// Final prediction from last component
	if p.pr.len > 0 {
		pr = p.pr[p.pr.len - 1]
	}

	// Clamp to valid range
	if pr < 1 {
		pr = 1
	}
	if pr > 4095 {
		pr = 4095
	}

	return pr
}

// Update model after seeing actual bit y (0 or 1)
pub fn (mut p Predictor) update(y int) {
	// Update context
	p.c8 = (p.c8 << 1) | u32(y)
	if p.c8 >= 256 {
		// Full byte received
		p.hmap4 = (p.hmap4 << 8) | (p.c8 & 0xFF)
		p.c8 = 1
	}

	// Update each component
	for i := 0; i < p.comp.len; i++ {
		match p.comp[i].ctype {
			2 { // CM
				// Update prediction
				ctx := int(p.c8 >> 1)
				if ctx < p.comp[i].cm.len {
					mut n := p.comp[i].cm[ctx]
					// Adjust based on y
					err := (y * 4095 - p.pr[i]) * p.comp[i].limit / 4096
					n += u32(err)
					p.comp[i].cm[ctx] = n
				}
			}
			3 { // ICM
				// Update indirect context model
			}
			4 { // MATCH
				// Update match model
			}
			else {}
		}
	}
}

// Reset predictor state
pub fn (mut p Predictor) reset() {
	p.c8 = 1
	p.hmap4 = 0
	for i := 0; i < p.state.len; i++ {
		p.state[i] = 0
	}
}
