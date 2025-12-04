// ZPAQL Virtual Machine implementation
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// ZPAQL virtual machine for executing ZPAQL programs
pub struct ZPAQL {
pub mut:
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

// Helper for safe M array access
fn (z &ZPAQL) m_get(i u32) u8 {
	if z.m.len == 0 {
		return 0
	}
	idx := i & u32(z.m.len - 1)
	return z.m[idx]
}

// Helper for safe M array write
fn (mut z ZPAQL) m_set(i u32, val u8) {
	if z.m.len == 0 {
		return
	}
	idx := i & u32(z.m.len - 1)
	z.m[idx] = val
}

// Helper for safe H array access
fn (z &ZPAQL) h_get(i u32) u32 {
	if z.h.len == 0 {
		return 0
	}
	idx := i & u32(z.h.len - 1)
	return z.h[idx]
}

// Helper for safe H array write
fn (mut z ZPAQL) h_set(i u32, val u32) {
	if z.h.len == 0 {
		return
	}
	idx := i & u32(z.h.len - 1)
	z.h[idx] = val
}

// Execute one instruction, return false to stop
// Matches libzpaq ZPAQL::run0() exactly
pub fn (mut z ZPAQL) execute() bool {
	if z.pc < z.hbegin || z.pc >= z.hend {
		return false
	}

	op := z.header[z.pc]
	z.pc++

	// Get operand if needed for 2-byte and 3-byte instructions
	mut operand := 0
	if oplen(op) == 2 && z.pc < z.header.len {
		operand = int(z.header[z.pc])
		z.pc++
	} else if oplen(op) == 3 && z.pc + 1 < z.header.len {
		operand = int(z.header[z.pc]) + int(z.header[z.pc + 1]) * 256
		z.pc += 2
	}

	// Execute opcode - matches libzpaq exactly
	// Reference: libzpaq.cpp run0() function
	match op {
		0 {
			// NOP
		}
		// A register operations (1-7)
		1 {
			z.a++
		} // A++
		2 {
			z.a--
		} // A--
		3 {
			z.a = ~z.a
		} // A!
		4 {
			z.a = 0
		} // A=0
		7 {
			z.a = z.r[operand & 255]
		} // A=R N
		// B register operations (8-15)
		8 {
			z.a, z.b = z.b, z.a
		} // B<>A (swap A and B)
		9 {
			z.b++
		} // B++
		10 {
			z.b--
		} // B--
		11 {
			z.b = ~z.b
		} // B!
		12 {
			z.b = 0
		} // B=0
		15 {
			z.b = z.r[operand & 255]
		} // B=R N
		// C register operations (16-23)
		16 {
			z.a, z.c = z.c, z.a
		} // C<>A (swap A and C)
		17 {
			z.c++
		} // C++
		18 {
			z.c--
		} // C--
		19 {
			z.c = ~z.c
		} // C!
		20 {
			z.c = 0
		} // C=0
		23 {
			z.c = z.r[operand & 255]
		} // C=R N
		// D register operations (24-31)
		24 {
			z.a, z.d = z.d, z.a
		} // D<>A (swap A and D)
		25 {
			z.d++
		} // D++
		26 {
			z.d--
		} // D--
		27 {
			z.d = ~z.d
		} // D!
		28 {
			z.d = 0
		} // D=0
		31 {
			z.d = z.r[operand & 255]
		} // D=R N
		// *B memory operations (32-39)
		32 {
			tmp := z.m_get(z.b)
			z.m_set(z.b, u8(z.a))
			z.a = u32(tmp)
		} // *B<>A
		33 {
			z.m_set(z.b, z.m_get(z.b) + 1)
		} // *B++
		34 {
			z.m_set(z.b, z.m_get(z.b) - 1)
		} // *B--
		35 {
			z.m_set(z.b, ~z.m_get(z.b))
		} // *B!
		36 {
			z.m_set(z.b, 0)
		} // *B=0
		39 { // JT N (jump if true)
			if z.f != 0 {
				z.pc += ((operand + 128) & 255) - 127
			}
		}
		// *C memory operations (40-47)
		40 {
			tmp := z.m_get(z.c)
			z.m_set(z.c, u8(z.a))
			z.a = u32(tmp)
		} // *C<>A
		41 {
			z.m_set(z.c, z.m_get(z.c) + 1)
		} // *C++
		42 {
			z.m_set(z.c, z.m_get(z.c) - 1)
		} // *C--
		43 {
			z.m_set(z.c, ~z.m_get(z.c))
		} // *C!
		44 {
			z.m_set(z.c, 0)
		} // *C=0
		47 { // JF N (jump if false)
			if z.f == 0 {
				z.pc += ((operand + 128) & 255) - 127
			}
		}
		// *D hash table operations (48-55)
		48 {
			tmp := z.h_get(z.d)
			z.h_set(z.d, z.a)
			z.a = tmp
		} // *D<>A
		49 {
			z.h_set(z.d, z.h_get(z.d) + 1)
		} // *D++
		50 {
			z.h_set(z.d, z.h_get(z.d) - 1)
		} // *D--
		51 {
			z.h_set(z.d, ~z.h_get(z.d))
		} // *D!
		52 {
			z.h_set(z.d, 0)
		} // *D=0
		55 {
			z.r[operand & 255] = z.a
		} // R=A N
		56 {
			return false
		} // HALT
		57 {
			z.outc(int(z.a & 255))
		} // OUT
		59 {
			z.a = (z.a + u32(z.m_get(z.b)) + 512) * 773
		} // HASH
		60 {
			z.h_set(z.d, (z.h_get(z.d) + z.a + 512) * 773)
		} // HASHD
		63 {
			z.pc += ((operand + 128) & 255) - 127
		} // JMP N
		// Assignment opcodes 64-119
		64 {
			// A=A
		}
		65 {
			z.a = z.b
		} // A=B
		66 {
			z.a = z.c
		} // A=C
		67 {
			z.a = z.d
		} // A=D
		68 {
			z.a = u32(z.m_get(z.b))
		} // A=*B
		69 {
			z.a = u32(z.m_get(z.c))
		} // A=*C
		70 {
			z.a = z.h_get(z.d)
		} // A=*D
		71 {
			z.a = u32(operand)
		} // A=N
		72 {
			z.b = z.a
		} // B=A
		73 {
			// B=B
		}
		74 {
			z.b = z.c
		} // B=C
		75 {
			z.b = z.d
		} // B=D
		76 {
			z.b = u32(z.m_get(z.b))
		} // B=*B
		77 {
			z.b = u32(z.m_get(z.c))
		} // B=*C
		78 {
			z.b = z.h_get(z.d)
		} // B=*D
		79 {
			z.b = u32(operand)
		} // B=N
		80 {
			z.c = z.a
		} // C=A
		81 {
			z.c = z.b
		} // C=B
		82 {
			// C=C
		}
		83 {
			z.c = z.d
		} // C=D
		84 {
			z.c = u32(z.m_get(z.b))
		} // C=*B
		85 {
			z.c = u32(z.m_get(z.c))
		} // C=*C
		86 {
			z.c = z.h_get(z.d)
		} // C=*D
		87 {
			z.c = u32(operand)
		} // C=N
		88 {
			z.d = z.a
		} // D=A
		89 {
			z.d = z.b
		} // D=B
		90 {
			z.d = z.c
		} // D=C
		91 {
			// D=D
		}
		92 {
			z.d = u32(z.m_get(z.b))
		} // D=*B
		93 {
			z.d = u32(z.m_get(z.c))
		} // D=*C
		94 {
			z.d = z.h_get(z.d)
		} // D=*D
		95 {
			z.d = u32(operand)
		} // D=N
		96 {
			z.m_set(z.b, u8(z.a))
		} // *B=A
		97 {
			z.m_set(z.b, u8(z.b))
		} // *B=B
		98 {
			z.m_set(z.b, u8(z.c))
		} // *B=C
		99 {
			z.m_set(z.b, u8(z.d))
		} // *B=D
		100 {
			//*B=*B
		}
		101 {
			z.m_set(z.b, z.m_get(z.c))
		} // *B=*C
		102 {
			z.m_set(z.b, u8(z.h_get(z.d)))
		} // *B=*D
		103 {
			z.m_set(z.b, u8(operand))
		} // *B=N
		104 {
			z.m_set(z.c, u8(z.a))
		} // *C=A
		105 {
			z.m_set(z.c, u8(z.b))
		} // *C=B
		106 {
			z.m_set(z.c, u8(z.c))
		} // *C=C
		107 {
			z.m_set(z.c, u8(z.d))
		} // *C=D
		108 {
			z.m_set(z.c, z.m_get(z.b))
		} // *C=*B
		109 {
			//*C=*C
		}
		110 {
			z.m_set(z.c, u8(z.h_get(z.d)))
		} // *C=*D
		111 {
			z.m_set(z.c, u8(operand))
		} // *C=N
		112 {
			z.h_set(z.d, z.a)
		} // *D=A
		113 {
			z.h_set(z.d, z.b)
		} // *D=B
		114 {
			z.h_set(z.d, z.c)
		} // *D=C
		115 {
			z.h_set(z.d, z.d)
		} // *D=D
		116 {
			z.h_set(z.d, u32(z.m_get(z.b)))
		} // *D=*B
		117 {
			z.h_set(z.d, u32(z.m_get(z.c)))
		} // *D=*C
		118 {
			//*D=*D
		}
		119 {
			z.h_set(z.d, u32(operand))
		} // *D=N
		// Arithmetic opcodes 128-167
		128 {
			z.a += z.a
		} // A+=A
		129 {
			z.a += z.b
		} // A+=B
		130 {
			z.a += z.c
		} // A+=C
		131 {
			z.a += z.d
		} // A+=D
		132 {
			z.a += u32(z.m_get(z.b))
		} // A+=*B
		133 {
			z.a += u32(z.m_get(z.c))
		} // A+=*C
		134 {
			z.a += z.h_get(z.d)
		} // A+=*D
		135 {
			z.a += u32(operand)
		} // A+=N
		136 {
			z.a -= z.a
		} // A-=A
		137 {
			z.a -= z.b
		} // A-=B
		138 {
			z.a -= z.c
		} // A-=C
		139 {
			z.a -= z.d
		} // A-=D
		140 {
			z.a -= u32(z.m_get(z.b))
		} // A-=*B
		141 {
			z.a -= u32(z.m_get(z.c))
		} // A-=*C
		142 {
			z.a -= z.h_get(z.d)
		} // A-=*D
		143 {
			z.a -= u32(operand)
		} // A-=N
		144 {
			z.a *= z.a
		} // A*=A
		145 {
			z.a *= z.b
		} // A*=B
		146 {
			z.a *= z.c
		} // A*=C
		147 {
			z.a *= z.d
		} // A*=D
		148 {
			z.a *= u32(z.m_get(z.b))
		} // A*=*B
		149 {
			z.a *= u32(z.m_get(z.c))
		} // A*=*C
		150 {
			z.a *= z.h_get(z.d)
		} // A*=*D
		151 {
			z.a *= u32(operand)
		} // A*=N
		152 {
			if z.a != 0 {
				z.a = z.a / z.a
			}
		} // A/=A
		153 {
			if z.b != 0 {
				z.a /= z.b
			}
		} // A/=B
		154 {
			if z.c != 0 {
				z.a /= z.c
			}
		} // A/=C
		155 {
			if z.d != 0 {
				z.a /= z.d
			}
		} // A/=D
		156 {
			t := u32(z.m_get(z.b))
			if t != 0 {
				z.a /= t
			}
		} // A/=*B
		157 {
			t := u32(z.m_get(z.c))
			if t != 0 {
				z.a /= t
			}
		} // A/=*C
		158 {
			t := z.h_get(z.d)
			if t != 0 {
				z.a /= t
			}
		} // A/=*D
		159 {
			if operand != 0 {
				z.a /= u32(operand)
			}
		} // A/=N
		160 {
			if z.a != 0 {
				z.a = z.a % z.a
			}
		} // A%=A
		161 {
			if z.b != 0 {
				z.a %= z.b
			}
		} // A%=B
		162 {
			if z.c != 0 {
				z.a %= z.c
			}
		} // A%=C
		163 {
			if z.d != 0 {
				z.a %= z.d
			}
		} // A%=D
		164 {
			t := u32(z.m_get(z.b))
			if t != 0 {
				z.a %= t
			}
		} // A%=*B
		165 {
			t := u32(z.m_get(z.c))
			if t != 0 {
				z.a %= t
			}
		} // A%=*C
		166 {
			t := z.h_get(z.d)
			if t != 0 {
				z.a %= t
			}
		} // A%=*D
		167 {
			if operand != 0 {
				z.a %= u32(operand)
			}
		} // A%=N
		// Bitwise opcodes 168-199
		168 {
			z.a &= z.a
		} // A&=A
		169 {
			z.a &= z.b
		} // A&=B
		170 {
			z.a &= z.c
		} // A&=C
		171 {
			z.a &= z.d
		} // A&=D
		172 {
			z.a &= u32(z.m_get(z.b))
		} // A&=*B
		173 {
			z.a &= u32(z.m_get(z.c))
		} // A&=*C
		174 {
			z.a &= z.h_get(z.d)
		} // A&=*D
		175 {
			z.a &= u32(operand)
		} // A&=N
		176 {
			z.a &= ~z.a
		} // A&~A
		177 {
			z.a &= ~z.b
		} // A&~B
		178 {
			z.a &= ~z.c
		} // A&~C
		179 {
			z.a &= ~z.d
		} // A&~D
		180 {
			z.a &= ~u32(z.m_get(z.b))
		} // A&~*B
		181 {
			z.a &= ~u32(z.m_get(z.c))
		} // A&~*C
		182 {
			z.a &= ~z.h_get(z.d)
		} // A&~*D
		183 {
			z.a &= ~u32(operand)
		} // A&~N
		184 {
			z.a |= z.a
		} // A|=A
		185 {
			z.a |= z.b
		} // A|=B
		186 {
			z.a |= z.c
		} // A|=C
		187 {
			z.a |= z.d
		} // A|=D
		188 {
			z.a |= u32(z.m_get(z.b))
		} // A|=*B
		189 {
			z.a |= u32(z.m_get(z.c))
		} // A|=*C
		190 {
			z.a |= z.h_get(z.d)
		} // A|=*D
		191 {
			z.a |= u32(operand)
		} // A|=N
		192 {
			z.a ^= z.a
		} // A^=A
		193 {
			z.a ^= z.b
		} // A^=B
		194 {
			z.a ^= z.c
		} // A^=C
		195 {
			z.a ^= z.d
		} // A^=D
		196 {
			z.a ^= u32(z.m_get(z.b))
		} // A^=*B
		197 {
			z.a ^= u32(z.m_get(z.c))
		} // A^=*C
		198 {
			z.a ^= z.h_get(z.d)
		} // A^=*D
		199 {
			z.a ^= u32(operand)
		} // A^=N
		// Shift opcodes 200-215
		200 {
			z.a <<= (z.a & 31)
		} // A<<=A
		201 {
			z.a <<= (z.b & 31)
		} // A<<=B
		202 {
			z.a <<= (z.c & 31)
		} // A<<=C
		203 {
			z.a <<= (z.d & 31)
		} // A<<=D
		204 {
			z.a <<= (u32(z.m_get(z.b)) & 31)
		} // A<<=*B
		205 {
			z.a <<= (u32(z.m_get(z.c)) & 31)
		} // A<<=*C
		206 {
			z.a <<= (z.h_get(z.d) & 31)
		} // A<<=*D
		207 {
			z.a <<= (u32(operand) & 31)
		} // A<<=N
		208 {
			z.a >>= (z.a & 31)
		} // A>>=A
		209 {
			z.a >>= (z.b & 31)
		} // A>>=B
		210 {
			z.a >>= (z.c & 31)
		} // A>>=C
		211 {
			z.a >>= (z.d & 31)
		} // A>>=D
		212 {
			z.a >>= (u32(z.m_get(z.b)) & 31)
		} // A>>=*B
		213 {
			z.a >>= (u32(z.m_get(z.c)) & 31)
		} // A>>=*C
		214 {
			z.a >>= (z.h_get(z.d) & 31)
		} // A>>=*D
		215 {
			z.a >>= (u32(operand) & 31)
		} // A>>=N
		// Comparison opcodes 216-239
		216 {
			z.f = 1
		} // A==A (always true)
		217 {
			z.f = if z.a == z.b { 1 } else { 0 }
		} // A==B
		218 {
			z.f = if z.a == z.c { 1 } else { 0 }
		} // A==C
		219 {
			z.f = if z.a == z.d { 1 } else { 0 }
		} // A==D
		220 {
			z.f = if z.a == u32(z.m_get(z.b)) { 1 } else { 0 }
		} // A==*B
		221 {
			z.f = if z.a == u32(z.m_get(z.c)) { 1 } else { 0 }
		} // A==*C
		222 {
			z.f = if z.a == z.h_get(z.d) { 1 } else { 0 }
		} // A==*D
		223 {
			z.f = if z.a == u32(operand) { 1 } else { 0 }
		} // A==N
		224 {
			z.f = 0
		} // A<A (always false)
		225 {
			z.f = if z.a < z.b { 1 } else { 0 }
		} // A<B
		226 {
			z.f = if z.a < z.c { 1 } else { 0 }
		} // A<C
		227 {
			z.f = if z.a < z.d { 1 } else { 0 }
		} // A<D
		228 {
			z.f = if z.a < u32(z.m_get(z.b)) { 1 } else { 0 }
		} // A<*B
		229 {
			z.f = if z.a < u32(z.m_get(z.c)) { 1 } else { 0 }
		} // A<*C
		230 {
			z.f = if z.a < z.h_get(z.d) { 1 } else { 0 }
		} // A<*D
		231 {
			z.f = if z.a < u32(operand) { 1 } else { 0 }
		} // A<N
		232 {
			z.f = 0
		} // A>A (always false)
		233 {
			z.f = if z.a > z.b { 1 } else { 0 }
		} // A>B
		234 {
			z.f = if z.a > z.c { 1 } else { 0 }
		} // A>C
		235 {
			z.f = if z.a > z.d { 1 } else { 0 }
		} // A>D
		236 {
			z.f = if z.a > u32(z.m_get(z.b)) { 1 } else { 0 }
		} // A>*B
		237 {
			z.f = if z.a > u32(z.m_get(z.c)) { 1 } else { 0 }
		} // A>*C
		238 {
			z.f = if z.a > z.h_get(z.d) { 1 } else { 0 }
		} // A>*D
		239 {
			z.f = if z.a > u32(operand) { 1 } else { 0 }
		} // A>N
		255 { // LJ (long jump)
			z.pc = z.hbegin + int(z.header[z.pc - 2]) + int(z.header[z.pc - 1]) * 256
			if z.pc >= z.hend {
				return false
			}
		}
		else {
			// Unknown opcode - error
			return false
		}
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
