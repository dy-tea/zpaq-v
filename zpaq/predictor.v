// Context model predictor for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Initial CM probability - 50% probability (16384 out of 32767)
// Stored in upper 16 bits for CM table format
const initial_cm_probability = u32(16384) << 16

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

// Decay table (dt) for CM model from libzpaq (exactly 1024 entries)
// dt[i] = (1<<17)/(i*2+3)*2, from libzpaq sdt table
// Used for adaptive learning rate in CM: error*dt[count]
const dt_table = [int(87380), 52428, 37448, 29126, 23830, 20164, 17476, 15420, 13796, 12482, 11396,
	10484, 9708, 9038, 8456, 7942, 7488, 7084, 6720, 6392, 6096, 5824, 5576, 5348, 5140, 4946,
	4766, 4598, 4442, 4296, 4160, 4032, 3912, 3798, 3692, 3590, 3494, 3404, 3318, 3236, 3158, 3084,
	3012, 2944, 2880, 2818, 2758, 2702, 2646, 2594, 2544, 2496, 2448, 2404, 2360, 2318, 2278, 2240,
	2202, 2166, 2130, 2096, 2064, 2032, 2000, 1970, 1940, 1912, 1884, 1858, 1832, 1806, 1782, 1758,
	1736, 1712, 1690, 1668, 1648, 1628, 1608, 1588, 1568, 1550, 1532, 1514, 1496, 1480, 1464, 1448,
	1432, 1416, 1400, 1386, 1372, 1358, 1344, 1330, 1316, 1304, 1290, 1278, 1266, 1254, 1242, 1230,
	1218, 1208, 1196, 1186, 1174, 1164, 1154, 1144, 1134, 1124, 1114, 1106, 1096, 1086, 1078, 1068,
	1060, 1052, 1044, 1036, 1028, 1020, 1012, 1004, 996, 988, 980, 974, 966, 960, 952, 946, 938,
	932, 926, 918, 912, 906, 900, 894, 888, 882, 876, 870, 864, 858, 852, 848, 842, 836, 832, 826,
	820, 816, 810, 806, 800, 796, 790, 786, 782, 776, 772, 768, 764, 758, 754, 750, 746, 742, 738,
	734, 730, 726, 722, 718, 714, 710, 706, 702, 698, 694, 690, 688, 684, 680, 676, 672, 670, 666,
	662, 660, 656, 652, 650, 646, 644, 640, 636, 634, 630, 628, 624, 622, 618, 616, 612, 610, 608,
	604, 602, 598, 596, 594, 590, 588, 586, 582, 580, 578, 576, 572, 570, 568, 566, 562, 560, 558,
	556, 554, 550, 548, 546, 544, 542, 540, 538, 536, 532, 530, 528, 526, 524, 522, 520, 518, 516,
	514, 512, 510, 508, 506, 504, 502, 500, 498, 496, 494, 492, 490, 488, 488, 486, 484, 482, 480,
	478, 476, 474, 474, 472, 470, 468, 466, 464, 462, 462, 460, 458, 456, 454, 454, 452, 450, 448,
	448, 446, 444, 442, 442, 440, 438, 436, 436, 434, 432, 430, 430, 428, 426, 426, 424, 422, 422,
	420, 418, 418, 416, 414, 414, 412, 410, 410, 408, 406, 406, 404, 402, 402, 400, 400, 398, 396,
	396, 394, 394, 392, 390, 390, 388, 388, 386, 386, 384, 382, 382, 380, 380, 378, 378, 376, 376,
	374, 372, 372, 370, 370, 368, 368, 366, 366, 364, 364, 362, 362, 360, 360, 358, 358, 356, 356,
	354, 354, 352, 352, 350, 350, 348, 348, 348, 346, 346, 344, 344, 342, 342, 340, 340, 340, 338,
	338, 336, 336, 334, 334, 332, 332, 332, 330, 330, 328, 328, 328, 326, 326, 324, 324, 324, 322,
	322, 320, 320, 320, 318, 318, 316, 316, 316, 314, 314, 312, 312, 312, 310, 310, 310, 308, 308,
	308, 306, 306, 304, 304, 304, 302, 302, 302, 300, 300, 300, 298, 298, 298, 296, 296, 296, 294,
	294, 294, 292, 292, 292, 290, 290, 290, 288, 288, 288, 286, 286, 286, 284, 284, 284, 284, 282,
	282, 282, 280, 280, 280, 278, 278, 278, 276, 276, 276, 276, 274, 274, 274, 272, 272, 272, 272,
	270, 270, 270, 268, 268, 268, 268, 266, 266, 266, 266, 264, 264, 264, 262, 262, 262, 262, 260,
	260, 260, 260, 258, 258, 258, 258, 256, 256, 256, 256, 254, 254, 254, 254, 252, 252, 252, 252,
	250, 250, 250, 250, 248, 248, 248, 248, 248, 246, 246, 246, 246, 244, 244, 244, 244, 242, 242,
	242, 242, 242, 240, 240, 240, 240, 238, 238, 238, 238, 238, 236, 236, 236, 236, 234, 234, 234,
	234, 234, 232, 232, 232, 232, 232, 230, 230, 230, 230, 230, 228, 228, 228, 228, 228, 226, 226,
	226, 226, 226, 224, 224, 224, 224, 224, 222, 222, 222, 222, 222, 220, 220, 220, 220, 220, 220,
	218, 218, 218, 218, 218, 216, 216, 216, 216, 216, 216, 214, 214, 214, 214, 214, 212, 212, 212,
	212, 212, 212, 210, 210, 210, 210, 210, 210, 208, 208, 208, 208, 208, 208, 206, 206, 206, 206,
	206, 206, 204, 204, 204, 204, 204, 204, 204, 202, 202, 202, 202, 202, 202, 200, 200, 200, 200,
	200, 200, 198, 198, 198, 198, 198, 198, 198, 196, 196, 196, 196, 196, 196, 196, 194, 194, 194,
	194, 194, 194, 194, 192, 192, 192, 192, 192, 192, 192, 190, 190, 190, 190, 190, 190, 190, 188,
	188, 188, 188, 188, 188, 188, 186, 186, 186, 186, 186, 186, 186, 186, 184, 184, 184, 184, 184,
	184, 184, 182, 182, 182, 182, 182, 182, 182, 182, 180, 180, 180, 180, 180, 180, 180, 180, 178,
	178, 178, 178, 178, 178, 178, 178, 176, 176, 176, 176, 176, 176, 176, 176, 176, 174, 174, 174,
	174, 174, 174, 174, 174, 172, 172, 172, 172, 172, 172, 172, 172, 172, 170, 170, 170, 170, 170,
	170, 170, 170, 170, 168, 168, 168, 168, 168, 168, 168, 168, 168, 166, 166, 166, 166, 166, 166,
	166, 166, 166, 166, 164, 164, 164, 164, 164, 164, 164, 164, 164, 162, 162, 162, 162, 162, 162,
	162, 162, 162, 162, 160, 160, 160, 160, 160, 160, 160, 160, 160, 160, 158, 158, 158, 158, 158,
	158, 158, 158, 158, 158, 158, 156, 156, 156, 156, 156, 156, 156, 156, 156, 156, 154, 154, 154,
	154, 154, 154, 154, 154, 154, 154, 154, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152,
	150, 150, 150, 150, 150, 150, 150, 150, 150, 150, 150, 150, 148, 148, 148, 148, 148, 148, 148,
	148, 148, 148, 148, 148, 146, 146, 146, 146, 146, 146, 146, 146, 146, 146, 146, 146, 144, 144,
	144, 144, 144, 144, 144, 144, 144, 144, 144, 144, 142, 142, 142, 142, 142, 142, 142, 142, 142,
	142, 142, 142, 142, 140, 140, 140, 140, 140, 140, 140, 140, 140, 140, 140, 140, 140, 138, 138,
	138, 138, 138, 138, 138, 138, 138, 138, 138, 138, 138, 138, 136, 136, 136, 136, 136, 136, 136,
	136, 136, 136, 136, 136, 136, 136, 134, 134, 134, 134, 134, 134, 134, 134, 134, 134, 134, 134,
	134, 134, 132, 132, 132, 132, 132, 132, 132, 132, 132, 132, 132, 132, 132, 132, 132, 130, 130,
	130, 130, 130, 130, 130, 130, 130, 130, 130, 130, 130, 130, 130, 128, 128, 128, 128, 128, 128,
	128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 126]!

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
pub fn (mut pred Predictor) init(z &ZPAQL) {
	unsafe {
		pred.z = z
	}
	pred.c8 = 1
	pred.hmap4 = 1

	// Parse header for components
	if z.header.len < 5 {
		// No components defined - this is store mode, don't create any components
		pred.comp = []Component{}
		pred.p = []int{}
		pred.h = []u32{}
		return
	}

	// Header format: hm hh ph pm n [comp1] [comp2] ... [compN] 0
	// hm = log2 size of M array (byte 0)
	// hh = log2 size of H array (byte 1)
	// ph = log2 size of P array (PCOMP) (byte 2)
	// pm = log2 size of M array (PCOMP) (byte 3)
	// n = number of components (byte 4)
	// components start at byte 5

	n := int(z.header[4])
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
	mut cp := 5 // current position in header (components start at byte 5)
	for i := 0; i < n && cp < z.cend; i++ {
		ctype := int(z.header[cp])
		pred.comp[i] = Component.new()
		pred.comp[i].ctype = ctype

		// Read component parameters based on type
		// Reference: libzpaq compsize[256]={0,2,3,2,3,4,6,6,3,5}
		match ctype {
			1 { // CONST - just outputs a constant probability
				pred.comp[i].a = int(z.header[cp + 1])
				cp += compsize[1]
			}
			2 { // CM - context model
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				// libzpaq: cr.limit = cp[2] * 4
				pred.comp[i].limit = int(z.header[cp + 2]) * 4
				size := 1 << pred.comp[i].a
				pred.comp[i].cm = []u32{len: size}
				// Initialize with 50% probability (0x80000000)
				// CM format: upper 22 bits = probability (>>17 to get p), lower 10 bits = count
				// libzpaq: p[i]=stretch(cr.cm(cr.cxt)>>17)
				for j := 0; j < size; j++ {
					pred.comp[i].cm[j] = 0x80000000
				}
				cp += compsize[2]
			}
			3 { // ICM - indirect context model
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				// ICM ht size is 16 * 2^(sizebits+2) = 64 * 2^sizebits
				size := 16 << (pred.comp[i].a + 2)
				pred.comp[i].cm = []u32{len: 256}
				pred.comp[i].ht = []u8{len: size}
				// Initialize CM with state-based probabilities
				// libzpaq: cr.cm[j]=st.cminit(j) (23-bit scaled probability)
				// libzpaq: p[i]=stretch(cr.cm(cr.cxt)>>8) (reads as 15-bit probability)
				for j := 0; j < 256; j++ {
					pred.comp[i].cm[j] = u32(pred.st.cminit(j))
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
				// Format: type j k wt
				pred.comp[i].a = int(z.header[cp + 1]) // j = first component
				pred.comp[i].b = int(z.header[cp + 2]) // k = second component
				pred.comp[i].c = int(z.header[cp + 3]) // weight (0-256)
				cp += compsize[5]
			}
			6 { // MIX2 - weighted mix of 2 components
				// Format: type sizebits j k rate mask
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				size := 1 << pred.comp[i].a
				pred.comp[i].b = int(z.header[cp + 2]) // j = first input component
				pred.comp[i].c = size // c = size (number of contexts)
				// Read j, k, rate, mask
				// j = cp[2], k = cp[3], rate = cp[4], mask = cp[5]
				pred.comp[i].a16 = []u16{len: size, init: 32768}
				// Store additional parameters for MIX2
				// a = sizebits, b = j, c = size
				// We need to store j, k, rate, mask - use Component fields creatively
				// Store in cm array temporarily
				pred.comp[i].cm = []u32{len: 4}
				pred.comp[i].cm[0] = u32(z.header[cp + 2]) // j
				pred.comp[i].cm[1] = u32(z.header[cp + 3]) // k
				pred.comp[i].cm[2] = u32(z.header[cp + 4]) // rate
				pred.comp[i].cm[3] = u32(z.header[cp + 5]) // mask
				cp += compsize[6]
			}
			7 { // MIX - weighted mix of multiple components
				// Format: type sizebits j m rate mask
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				size := 1 << pred.comp[i].a
				j := int(z.header[cp + 2]) // j = start component
				m := int(z.header[cp + 3]) // m = number of inputs
				rate := int(z.header[cp + 4]) // rate
				mask := int(z.header[cp + 5]) // mask
				pred.comp[i].b = j // first input component
				pred.comp[i].c = size
				pred.comp[i].limit = m // number of inputs
				// Store rate and mask
				pred.comp[i].ht = []u8{len: 2}
				pred.comp[i].ht[0] = u8(rate)
				pred.comp[i].ht[1] = u8(mask)
				pred.comp[i].cm = []u32{len: size * m}
				// Initialize weights
				for k := 0; k < size * m; k++ {
					pred.comp[i].cm[k] = u32(65536 / m) << 8
				}
				cp += compsize[7]
			}
			8 { // ISSE - indirect SSE chain
				// Format: type sizebits j
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				pred.comp[i].b = int(z.header[cp + 2]) // j = input component
				// ISSE ht size is 16 * 2^(sizebits+2) = 64 * 2^sizebits
				size := 16 << (pred.comp[i].a + 2)
				pred.comp[i].ht = []u8{len: size}
				pred.comp[i].cm = []u32{len: 512}
				// Initialize weights (wt[0], wt[1] pairs for each state)
				// libzpaq: int *wt=(int*)&cr.cm[cr.cxt*2]
				// p[i]=clamp2k((wt[0]*p[cp[2]]+wt[1]*64)>>16)
				// libzpaq init: cr.cm[j*2]=1<<15; cr.cm[j*2+1]=clamp512k(stretch(st.cminit(j)>>8)*1024)
				for k := 0; k < 256; k++ {
					pred.comp[i].cm[k * 2] = u32(1 << 15) // wt[0] = 32768 (0.5 weight)
					st_init := pred.st.cminit(k)
					pred.comp[i].cm[k * 2 + 1] = u32(clamp512k(stretch(st_init >> 8) * 1024))
				}
				cp += compsize[8]
			}
			9 { // SSE - secondary symbol estimation
				// Format: type sizebits j start limit
				pred.comp[i].a = int(z.header[cp + 1]) // sizebits
				pred.comp[i].b = int(z.header[cp + 2]) // j = input component
				size := 1 << pred.comp[i].a
				pred.comp[i].cm = []u32{len: size * 32}
				pred.comp[i].limit = int(z.header[cp + 4]) * 4 // limit (scaled)
				// Initialize with linear stretch
				// libzpaq: p[i]=stretch(((cr.cm(cr.cxt)>>10)*(64-wt)+(cr.cm(cr.cxt+1)>>10)*wt)>>13)
				start := int(z.header[cp + 3])
				for k := 0; k < size * 32; k++ {
					q := (k & 31) * 64 - 992
					pred.comp[i].cm[k] = u32(squash(q) << 17) | u32(start)
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
// Reference: libzpaq Predictor::predict0()
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
			2 { // CM - context model
				// libzpaq: cr.cxt=h[i]^hmap4; p[i]=stretch(cr.cm(cr.cxt)>>17)
				cr.cxt = u32(pred.h[i]) ^ pred.hmap4
				idx := int(cr.cxt) & (cr.cm.len - 1)
				pred.p[i] = stretch(int(cr.cm[idx] >> 17))
			}
			3 { // ICM - indirect context model
				// libzpaq: if (c8==1 || (c8&0xf0)==16) cr.c=find(cr.ht, cp[1]+2, h[i]+16*c8)
				// cr.cxt=cr.ht[cr.c+(hmap4&15)]; p[i]=stretch(cr.cm(cr.cxt)>>8)
				if pred.c8 == 1 || (pred.c8 & 0xf0) == 16 {
					cr.c = pred.find_ht(mut cr.ht, cr.a + 2, u32(pred.h[i]) + 16 * pred.c8)
				}
				cr.cxt = u32(cr.ht[cr.c + int(pred.hmap4 & 15)])
				pred.p[i] = stretch(int(cr.cm[int(cr.cxt)] >> 8))
			}
			4 { // MATCH
				// libzpaq: p[i]=stretch(dt2k[cr.a]*(cr.c*-2+1)&32767)
				if cr.a == 0 {
					pred.p[i] = 0
				} else {
					idx := (cr.limit - cr.b) & (cr.ht.len - 1)
					cr.c = int((cr.ht[idx] >> (7 - int(cr.cxt))) & 1)
					weight := dt2k_table[cr.a & 255]
					pred.p[i] = stretch((weight * (cr.c * -2 + 1)) & 32767)
				}
			}
			5 { // AVG - average of two predictions
				// libzpaq: p[i]=(p[cp[1]]*cp[3]+p[cp[2]]*(256-cp[3]))>>8
				j := cr.a // first component index
				k := cr.b // second component index
				wt := cr.c // weight
				if j < n && k < n {
					pred.p[i] = (pred.p[j] * wt + pred.p[k] * (256 - wt)) >> 8
				} else {
					pred.p[i] = 0
				}
			}
			6 { // MIX2 - weighted mix of 2 components
				// libzpaq: cr.cxt=((h[i]+(c8&cp[5]))&(cr.c-1))
				// int w=cr.a16[cr.cxt]; p[i]=(w*p[cp[2]]+(65536-w)*p[cp[3]])>>16
				j := int(cr.cm[0]) // first input component
				k := int(cr.cm[1]) // second input component
				mask := int(cr.cm[3]) // mask
				cr.cxt = (u32(pred.h[i]) + (pred.c8 & u32(mask))) & u32(cr.c - 1)
				w := int(cr.a16[int(cr.cxt)])
				if j < n && k < n {
					pred.p[i] = clamp2k((w * pred.p[j] + (65536 - w) * pred.p[k]) >> 16)
				} else {
					pred.p[i] = 0
				}
			}
			7 { // MIX - weighted mix of m components
				// libzpaq: cr.cxt=h[i]+(c8&cp[5]); cr.cxt=(cr.cxt&(cr.c-1))*m
				// p[i]=0; for j=0..m-1: p[i]+=(wt[j]>>8)*p[cp[2]+j]; p[i]=clamp2k(p[i]>>8)
				j := cr.b // first input component
				m := cr.limit // number of inputs
				mask := int(cr.ht[1]) // mask
				cr.cxt = u32((int(pred.h[i]) + (int(pred.c8) & mask)) & (cr.c - 1))
				idx := int(cr.cxt) * m
				mut sum := 0
				for l := 0; l < m && (j + l) < n; l++ {
					wt := int(cr.cm[idx + l]) >> 8
					sum += wt * pred.p[j + l]
				}
				pred.p[i] = clamp2k(sum >> 8)
			}
			8 { // ISSE - indirect SSE chain
				// libzpaq: if (c8==1 || (c8&0xf0)==16) cr.c=find(cr.ht, cp[1]+2, h[i]+16*c8)
				// cr.cxt=cr.ht[cr.c+(hmap4&15)]; int *wt=&cr.cm[cr.cxt*2]
				// p[i]=clamp2k((wt[0]*p[cp[2]]+wt[1]*64)>>16)
				if pred.c8 == 1 || (pred.c8 & 0xf0) == 16 {
					cr.c = pred.find_ht(mut cr.ht, cr.a + 2, u32(pred.h[i]) + 16 * pred.c8)
				}
				cr.cxt = u32(cr.ht[cr.c + int(pred.hmap4 & 15)])
				wt0 := int(cr.cm[int(cr.cxt) * 2])
				wt1 := int(cr.cm[int(cr.cxt) * 2 + 1])
				j := cr.b // input component
				if j < n {
					pred.p[i] = clamp2k((wt0 * pred.p[j] + wt1 * 64) >> 16)
				} else {
					pred.p[i] = clamp2k(wt1 >> 10)
				}
			}
			9 { // SSE - secondary symbol estimation
				// libzpaq: cr.cxt=(h[i]+c8)*32; pq=p[cp[2]]+992; clamp to 0..1983
				// wt=pq&63; pq>>=6; p[i]=stretch((cm[cr.cxt+pq]>>10*(64-wt)+cm[cr.cxt+pq+1]>>10*wt)>>13)
				j := cr.b // input component
				cr.cxt = (u32(pred.h[i]) + pred.c8) * 32
				mut pq := 992
				if j < n {
					pq = pred.p[j] + 992
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
// Reference: libzpaq Predictor::update0()
pub fn (mut pred Predictor) update(y int) {
	n := pred.comp.len

	// Update each component
	for i := 0; i < n; i++ {
		mut cr := &pred.comp[i]
		match cr.ctype {
			1 { // CONST - no update
			}
			2 { // CM - context model
				// libzpaq train(cr, y):
				// void train(Component& cr, int y) {
				//   U32& pn=cr.cm(cr.cxt);
				//   U32 count=pn&0x3ff;
				//   int error=y*32767-(cr.cm(cr.cxt)>>17);
				//   pn+=(error*dt[count]&-1024)+(count<cr.limit);
				// }
				idx := int(cr.cxt) & (cr.cm.len - 1)
				mut pn := cr.cm[idx]
				count := int(pn & 0x3ff) // lower 10 bits
				err := y * 32767 - int(pn >> 17)
				// Get dt value (decay table)
				dt_val := if count < 1024 { dt_table[count] } else { dt_table[1023] }
				// Update: add (error*dt[count] & -1024) + (count < limit)
				update := (err * dt_val) & -1024
				count_inc := if count < cr.limit { 1 } else { 0 }
				pn = u32(int(pn) + update + count_inc)
				cr.cm[idx] = pn
			}
			3 { // ICM - indirect context model
				// libzpaq: cr.ht[cr.c+(hmap4&15)]=st.next(cr.ht[cr.c+(hmap4&15)], y)
				// pn += (y*32767-(pn>>8))>>2
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
					cr.limit++
					cr.limit &= (cr.ht.len - 1)
					if cr.a == 0 {
						// Look for match
						h := pred.h[i]
						cr.b = cr.limit - int(cr.cm[int(h) & (cr.cm.len - 1)])
						if cr.b & (cr.ht.len - 1) != 0 {
							// Count match length
							for cr.a < 255 {
								idx1 := (cr.limit - cr.a - 1) & (cr.ht.len - 1)
								idx2 := (cr.limit - cr.a - cr.b - 1) & (cr.ht.len - 1)
								if cr.ht[idx1] != cr.ht[idx2] {
									break
								}
								cr.a++
							}
						}
					} else if cr.a < 255 {
						cr.a++
					}
					cr.cm[int(pred.h[i]) & (cr.cm.len - 1)] = u32(cr.limit)
				}
			}
			5 { // AVG - no update
			}
			6 { // MIX2
				// libzpaq: err=(y*32767-squash(p[i]))*cp[4]>>5
				// w += err*(p[cp[2]]-p[cp[3]]) rounded
				j := int(cr.cm[0]) // first input component
				k := int(cr.cm[1]) // second input component
				rate := int(cr.cm[2]) // rate
				err := (y * 32767 - squash(pred.p[i])) * rate >> 5
				if j < n && k < n {
					mut w := int(cr.a16[int(cr.cxt)])
					w += (err * (pred.p[j] - pred.p[k]) + (1 << 12)) >> 13
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
				// libzpaq: err=(y*32767-squash(p[i]))*cp[4]>>4
				// wt[j]=clamp512k(wt[j]+(err*p[cp[2]+j] rounded))
				jj := cr.b // first input component
				m := cr.limit // number of inputs
				rate := int(cr.ht[0])
				err := (y * 32767 - squash(pred.p[i])) * rate >> 4
				idx := int(cr.cxt) * m
				for l := 0; l < m && (jj + l) < n; l++ {
					wt := clamp512k(int(cr.cm[idx + l]) + ((err * pred.p[jj + l] + (1 << 12)) >> 13))
					cr.cm[idx + l] = u32(wt)
				}
			}
			8 { // ISSE
				// libzpaq: err=y*32767-squash(p[i])
				// wt[0]=clamp512k(wt[0]+(err*p[cp[2]] rounded))
				// wt[1]=clamp512k(wt[1]+(err+16)>>5)
				// cr.ht[cr.c+(hmap4&15)]=st.next(cr.cxt, y)
				j := cr.b // input component
				err := y * 32767 - squash(pred.p[i])
				if j < n {
					wt0 := clamp512k(int(cr.cm[int(cr.cxt) * 2]) + ((err * pred.p[j] +
						(1 << 12)) >> 13))
					wt1 := clamp512k(int(cr.cm[int(cr.cxt) * 2 + 1]) + ((err + 16) >> 5))
					cr.cm[int(cr.cxt) * 2] = u32(wt0)
					cr.cm[int(cr.cxt) * 2 + 1] = u32(wt1)
				}
				cr.ht[cr.c + int(pred.hmap4 & 15)] = u8(pred.st.next(int(cr.cxt), y))
			}
			9 { // SSE
				// libzpaq: train(cr, y)
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
