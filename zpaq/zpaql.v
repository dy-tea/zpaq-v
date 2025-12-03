// ZPAQL Virtual Machine implementation
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// ZPAQL virtual machine for executing ZPAQL programs
pub struct ZPAQL {
mut:
	// Registers
	a  u32 // accumulator
	b  u32 // byte pointer
	c  u32 // context
	d  u32 // data pointer
	f  int // flag (0 or 1)
	pc int // program counter

	// Memory
	m []u8  // 8-bit memory (2^hh bytes)
	h []u32 // 32-bit memory (2^hh words)
	r []u32 // 256 32-bit registers

	// Header
	header []u8
	cend   int // end of code section
	hbegin int // beginning of hash section
	hend   int // end of hash section

	// Output
	output &Writer = unsafe { nil }
	sha1   &SHA1   = unsafe { nil }
	outbuf []u8 // output buffer
}

// Create a new ZPAQL VM
pub fn ZPAQL.new() ZPAQL {
	return ZPAQL{
		a:      0
		b:      0
		c:      0
		d:      0
		f:      0
		pc:     0
		m:      []u8{}
		h:      []u32{}
		r:      []u32{len: 256}
		header: []u8{}
		cend:   0
		hbegin: 0
		hend:   0
		outbuf: []u8{}
	}
}

// Clear the VM state
pub fn (mut z ZPAQL) clear() {
	z.a = 0
	z.b = 0
	z.c = 0
	z.d = 0
	z.f = 0
	z.pc = 0
	for i := 0; i < z.m.len; i++ {
		z.m[i] = 0
	}
	for i := 0; i < z.h.len; i++ {
		z.h[i] = 0
	}
	for i := 0; i < 256; i++ {
		z.r[i] = 0
	}
}

// Initialize H array based on header
pub fn (mut z ZPAQL) inith() {
	if z.header.len < 2 {
		return
	}
	hh := int(z.header[1]) // H size
	if hh > 0 && hh < 32 {
		z.h = []u32{len: 1 << hh}
	}
}

// Initialize M array and program counter
pub fn (mut z ZPAQL) initp() {
	if z.header.len < 1 {
		return
	}
	hm := int(z.header[0]) // M size
	if hm > 0 && hm < 32 {
		z.m = []u8{len: 1 << hm}
	}
	z.pc = z.hbegin
}

// Read ZPAQL header from input
// Returns the number of bytes read, or -1 on error
pub fn (mut z ZPAQL) read(mut input Reader) int {
	z.header.clear()

	// Read first byte (hm)
	hm := input.get()
	if hm < 0 {
		return -1
	}
	z.header << u8(hm)

	// Read second byte (hh)
	hh := input.get()
	if hh < 0 {
		return -1
	}
	z.header << u8(hh)

	// Read code section until terminator
	z.cend = 2
	mut prev := 0
	for {
		c := input.get()
		if c < 0 {
			return -1
		}
		z.header << u8(c)
		z.cend++
		if c == 0 && prev == 0 {
			break
		}
		prev = c
	}

	z.hbegin = z.cend
	z.hend = z.cend

	// Initialize arrays
	z.inith()
	z.initp()

	return z.header.len
}

// Write ZPAQL header to output
pub fn (mut z ZPAQL) write(mut output Writer, pcomp bool) bool {
	for b in z.header {
		output.put(int(b))
	}
	return true
}

// Output a character
pub fn (mut z ZPAQL) outc(ch int) {
	z.outbuf << u8(ch)
	if z.output != unsafe { nil } {
		z.output.put(ch)
	}
	if z.sha1 != unsafe { nil } {
		z.sha1.put(ch)
	}
}

// Flush output buffer
pub fn (mut z ZPAQL) flush() {
	z.outbuf.clear()
}

// Run the ZPAQL program with input byte
pub fn (mut z ZPAQL) run(input u32) {
	z.a = input
	z.pc = z.hbegin
	for z.pc < z.hend && z.pc >= z.hbegin {
		if !z.execute() {
			break
		}
	}
}

// Execute one instruction, return false to stop
pub fn (mut z ZPAQL) execute() bool {
	if z.pc < 0 || z.pc >= z.header.len {
		return false
	}

	op := z.header[z.pc]
	z.pc++

	// Get operand if needed
	mut operand := 0
	if oplen(op) == 2 && z.pc < z.header.len {
		operand = int(z.header[z.pc])
		z.pc++
	} else if oplen(op) == 3 && z.pc + 1 < z.header.len {
		operand = int(z.header[z.pc]) + int(z.header[z.pc + 1]) * 256
		z.pc += 2
	}

	// Execute opcode
	match op {
		0 {
			// NOP
		}
		1 {
			// A = *B
			if z.b < u32(z.m.len) {
				z.a = u32(z.m[z.b])
			}
		}
		2 {
			// A = *C
			if z.c < u32(z.m.len) {
				z.a = u32(z.m[z.c])
			}
		}
		3 {
			// A = *D
			if z.d < u32(z.m.len) {
				z.a = u32(z.m[z.d])
			}
		}
		4 {
			// *B = A
			if z.b < u32(z.m.len) {
				z.m[z.b] = u8(z.a)
			}
		}
		5 {
			// *C = A
			if z.c < u32(z.m.len) {
				z.m[z.c] = u8(z.a)
			}
		}
		6 {
			// *D = A
			if z.d < u32(z.m.len) {
				z.m[z.d] = u8(z.a)
			}
		}
		7 {
			// A = N
			z.a = u32(operand)
		}
		8 {
			// B = N
			z.b = u32(operand)
		}
		9 {
			// C = N
			z.c = u32(operand)
		}
		10 {
			// D = N
			z.d = u32(operand)
		}
		11 {
			// A += N
			z.a += u32(operand)
		}
		12 {
			// A -= N
			z.a -= u32(operand)
		}
		13 {
			// A *= N
			z.a *= u32(operand)
		}
		14 {
			// A /= N
			if operand != 0 {
				z.a /= u32(operand)
			}
		}
		15 {
			// A %= N
			if operand != 0 {
				z.a %= u32(operand)
			}
		}
		16 {
			// A &= N
			z.a &= u32(operand)
		}
		17 {
			// A |= N
			z.a |= u32(operand)
		}
		18 {
			// A ^= N
			z.a ^= u32(operand)
		}
		19 {
			// A <<= N
			z.a <<= u32(operand)
		}
		20 {
			// A >>= N
			z.a >>= u32(operand)
		}
		21 {
			// A == N
			z.f = if z.a == u32(operand) { 1 } else { 0 }
		}
		22 {
			// A < N
			z.f = if z.a < u32(operand) { 1 } else { 0 }
		}
		23 {
			// A > N
			z.f = if z.a > u32(operand) { 1 } else { 0 }
		}
		24 {
			// A += B
			z.a += z.b
		}
		25 {
			// A -= B
			z.a -= z.b
		}
		26 {
			// A *= B
			z.a *= z.b
		}
		27 {
			// A /= B
			if z.b != 0 {
				z.a /= z.b
			}
		}
		28 {
			// A %= B
			if z.b != 0 {
				z.a %= z.b
			}
		}
		29 {
			// A &= B
			z.a &= z.b
		}
		30 {
			// A |= B
			z.a |= z.b
		}
		31 {
			// A ^= B
			z.a ^= z.b
		}
		32 {
			// A <<= B
			z.a <<= (z.b & 31)
		}
		33 {
			// A >>= B
			z.a >>= (z.b & 31)
		}
		34 {
			// A == B
			z.f = if z.a == z.b { 1 } else { 0 }
		}
		35 {
			// A < B
			z.f = if z.a < z.b { 1 } else { 0 }
		}
		36 {
			// A > B
			z.f = if z.a > z.b { 1 } else { 0 }
		}
		37 {
			// B = A
			z.b = z.a
		}
		38 {
			// SWAP A,B
			z.a, z.b = z.b, z.a
		}
		39 {
			// JT N (jump if true)
			if z.f != 0 {
				z.pc += operand
			}
		}
		40 {
			// C = A
			z.c = z.a
		}
		41 {
			// SWAP A,C
			z.a, z.c = z.c, z.a
		}
		42 {
			// D = A
			z.d = z.a
		}
		43 {
			// SWAP A,D
			z.a, z.d = z.d, z.a
		}
		44 {
			// HALT
			return false
		}
		45 {
			// OUT A
			z.outc(int(z.a & 0xFF))
		}
		46 {
			// NOT A
			z.a = ~z.a
		}
		47 {
			// JF N (jump if false)
			if z.f == 0 {
				z.pc += operand
			}
		}
		48...55 {
			// R0..R7 = A
			idx := int(op - 48)
			z.r[idx] = z.a
		}
		56 {
			// ERROR
			return false
		}
		57...63 {
			// Extended ops
			if op == 63 {
				// JMP N
				z.pc += operand
			}
		}
		64...255 {
			// A = R[N] and other register ops
			if op >= 64 && op < 128 {
				idx := int(op - 64)
				if idx < 256 {
					z.a = z.r[idx]
				}
			} else if op >= 128 && op < 192 {
				// Store to register
				idx := int(op - 128)
				if idx < 256 {
					z.r[idx] = z.a
				}
			} else if op >= 192 && op < 224 {
				// A = H[N] - read from H array
				idx := int(op - 192)
				if idx < z.h.len {
					z.a = z.h[idx]
				}
			} else if op >= 224 {
				// H[N] = A - write to H array
				idx := int(op - 224)
				if idx < z.h.len {
					z.h[idx] = z.a
				}
			}
		}
		else {}
	}

	return true
}

// Get register A value
pub fn (z &ZPAQL) get_a() u32 {
	return z.a
}

// Set register A value
pub fn (mut z ZPAQL) set_a(val u32) {
	z.a = val
}

// Get H array value
pub fn (z &ZPAQL) get_h(i int) u32 {
	if i >= 0 && i < z.h.len {
		return z.h[i]
	}
	return 0
}

// Set H array value
pub fn (mut z ZPAQL) set_h(i int, val u32) {
	if i >= 0 && i < z.h.len {
		z.h[i] = val
	}
}

// Get M array value
pub fn (z &ZPAQL) get_m(i int) u8 {
	if i >= 0 && i < z.m.len {
		return z.m[i]
	}
	return 0
}

// Set M array value
pub fn (mut z ZPAQL) set_m(i int, val u8) {
	if i >= 0 && i < z.m.len {
		z.m[i] = val
	}
}

// Set output writer
pub fn (mut z ZPAQL) set_output(w &Writer) {
	unsafe {
		z.output = w
	}
}

// Set SHA1 hasher
pub fn (mut z ZPAQL) set_sha1(s &SHA1) {
	unsafe {
		z.sha1 = s
	}
}
