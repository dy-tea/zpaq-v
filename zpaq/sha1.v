// SHA1 and SHA256 hash implementations
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// SHA1 hash implementation
pub struct SHA1 {
mut:
	len0  u64 // message length in bits
	h     [5]u32
	w     [80]u32
	buf   [64]u8
	bufn  int // number of bytes in buf
	final bool
}

// SHA1 initial hash values
const sha1_h0 = [u32(0x67452301), 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]

// Create a new SHA1 hasher
pub fn SHA1.new() SHA1 {
	mut s := SHA1{}
	s.init()
	return s
}

// Initialize SHA1
pub fn (mut s SHA1) init() {
	s.len0 = 0
	s.bufn = 0
	s.final = false
	for i := 0; i < 5; i++ {
		s.h[i] = sha1_h0[i]
	}
}

// Left rotate
fn sha1_rotl(x u32, n u32) u32 {
	return (x << n) | (x >> (32 - n))
}

// Process a 64-byte block
fn (mut s SHA1) process_block() {
	// Extend 16 words to 80
	for i := 0; i < 16; i++ {
		s.w[i] = u32(s.buf[i * 4]) << 24 | u32(s.buf[i * 4 + 1]) << 16 | u32(s.buf[i * 4 + 2]) << 8 | u32(s.buf[
			i * 4 + 3])
	}
	for i := 16; i < 80; i++ {
		s.w[i] = sha1_rotl(s.w[i - 3] ^ s.w[i - 8] ^ s.w[i - 14] ^ s.w[i - 16], 1)
	}

	mut a := s.h[0]
	mut b := s.h[1]
	mut c := s.h[2]
	mut d := s.h[3]
	mut e := s.h[4]

	for i := 0; i < 80; i++ {
		mut f := u32(0)
		mut k := u32(0)
		if i < 20 {
			f = (b & c) | ((~b) & d)
			k = 0x5A827999
		} else if i < 40 {
			f = b ^ c ^ d
			k = 0x6ED9EBA1
		} else if i < 60 {
			f = (b & c) | (b & d) | (c & d)
			k = 0x8F1BBCDC
		} else {
			f = b ^ c ^ d
			k = 0xCA62C1D6
		}

		temp := sha1_rotl(a, 5) + f + e + k + s.w[i]
		e = d
		d = c
		c = sha1_rotl(b, 30)
		b = a
		a = temp
	}

	s.h[0] += a
	s.h[1] += b
	s.h[2] += c
	s.h[3] += d
	s.h[4] += e
}

// Add one byte
pub fn (mut s SHA1) put(c int) {
	if s.final {
		return
	}
	s.buf[s.bufn] = u8(c)
	s.bufn++
	s.len0 += 8
	if s.bufn == 64 {
		s.process_block()
		s.bufn = 0
	}
}

// Add multiple bytes
pub fn (mut s SHA1) write_bytes(buf []u8) {
	for b in buf {
		s.put(int(b))
	}
}

// Get the final hash (20 bytes)
pub fn (mut s SHA1) result() []u8 {
	if !s.final {
		// Padding
		s.buf[s.bufn] = 0x80
		s.bufn++
		if s.bufn > 56 {
			for s.bufn < 64 {
				s.buf[s.bufn] = 0
				s.bufn++
			}
			s.process_block()
			s.bufn = 0
		}
		for s.bufn < 56 {
			s.buf[s.bufn] = 0
			s.bufn++
		}
		// Append length in bits (big-endian)
		for i := 7; i >= 0; i-- {
			s.buf[s.bufn] = u8(s.len0 >> (i * 8))
			s.bufn++
		}
		s.process_block()
		s.final = true
	}

	mut out := []u8{len: 20}
	for i := 0; i < 5; i++ {
		out[i * 4] = u8(s.h[i] >> 24)
		out[i * 4 + 1] = u8(s.h[i] >> 16)
		out[i * 4 + 2] = u8(s.h[i] >> 8)
		out[i * 4 + 3] = u8(s.h[i])
	}
	return out
}

// SHA256 hash implementation
pub struct SHA256 {
mut:
	len0  u64 // message length in bits
	h     [8]u32
	w     [64]u32
	buf   [64]u8
	bufn  int
	final bool
}

// SHA256 initial hash values
const sha256_h0 = [
	u32(0x6a09e667),
	0xbb67ae85,
	0x3c6ef372,
	0xa54ff53a,
	0x510e527f,
	0x9b05688c,
	0x1f83d9ab,
	0x5be0cd19,
]

// SHA256 round constants
const sha256_k = [
	u32(0x428a2f98),
	0x71374491,
	0xb5c0fbcf,
	0xe9b5dba5,
	0x3956c25b,
	0x59f111f1,
	0x923f82a4,
	0xab1c5ed5,
	0xd807aa98,
	0x12835b01,
	0x243185be,
	0x550c7dc3,
	0x72be5d74,
	0x80deb1fe,
	0x9bdc06a7,
	0xc19bf174,
	0xe49b69c1,
	0xefbe4786,
	0x0fc19dc6,
	0x240ca1cc,
	0x2de92c6f,
	0x4a7484aa,
	0x5cb0a9dc,
	0x76f988da,
	0x983e5152,
	0xa831c66d,
	0xb00327c8,
	0xbf597fc7,
	0xc6e00bf3,
	0xd5a79147,
	0x06ca6351,
	0x14292967,
	0x27b70a85,
	0x2e1b2138,
	0x4d2c6dfc,
	0x53380d13,
	0x650a7354,
	0x766a0abb,
	0x81c2c92e,
	0x92722c85,
	0xa2bfe8a1,
	0xa81a664b,
	0xc24b8b70,
	0xc76c51a3,
	0xd192e819,
	0xd6990624,
	0xf40e3585,
	0x106aa070,
	0x19a4c116,
	0x1e376c08,
	0x2748774c,
	0x34b0bcb5,
	0x391c0cb3,
	0x4ed8aa4a,
	0x5b9cca4f,
	0x682e6ff3,
	0x748f82ee,
	0x78a5636f,
	0x84c87814,
	0x8cc70208,
	0x90befffa,
	0xa4506ceb,
	0xbef9a3f7,
	0xc67178f2,
]

// Create a new SHA256 hasher
pub fn SHA256.new() SHA256 {
	mut s := SHA256{}
	s.init()
	return s
}

// Initialize SHA256
pub fn (mut s SHA256) init() {
	s.len0 = 0
	s.bufn = 0
	s.final = false
	for i := 0; i < 8; i++ {
		s.h[i] = sha256_h0[i]
	}
}

// Right rotate
fn sha256_rotr(x u32, n u32) u32 {
	return (x >> n) | (x << (32 - n))
}

// Process a 64-byte block
fn (mut s SHA256) process_block() {
	// Extend 16 words to 64
	for i := 0; i < 16; i++ {
		s.w[i] = u32(s.buf[i * 4]) << 24 | u32(s.buf[i * 4 + 1]) << 16 | u32(s.buf[i * 4 + 2]) << 8 | u32(s.buf[
			i * 4 + 3])
	}
	for i := 16; i < 64; i++ {
		s1 := sha256_rotr(s.w[i - 2], 17) ^ sha256_rotr(s.w[i - 2], 19) ^ (s.w[i - 2] >> 10)
		s0 := sha256_rotr(s.w[i - 15], 7) ^ sha256_rotr(s.w[i - 15], 18) ^ (s.w[i - 15] >> 3)
		s.w[i] = s.w[i - 16] + s0 + s.w[i - 7] + s1
	}

	mut a := s.h[0]
	mut b := s.h[1]
	mut c := s.h[2]
	mut d := s.h[3]
	mut e := s.h[4]
	mut f := s.h[5]
	mut g := s.h[6]
	mut h := s.h[7]

	for i := 0; i < 64; i++ {
		s1 := sha256_rotr(e, 6) ^ sha256_rotr(e, 11) ^ sha256_rotr(e, 25)
		ch := (e & f) ^ ((~e) & g)
		temp1 := h + s1 + ch + sha256_k[i] + s.w[i]
		s0 := sha256_rotr(a, 2) ^ sha256_rotr(a, 13) ^ sha256_rotr(a, 22)
		maj := (a & b) ^ (a & c) ^ (b & c)
		temp2 := s0 + maj

		h = g
		g = f
		f = e
		e = d + temp1
		d = c
		c = b
		b = a
		a = temp1 + temp2
	}

	s.h[0] += a
	s.h[1] += b
	s.h[2] += c
	s.h[3] += d
	s.h[4] += e
	s.h[5] += f
	s.h[6] += g
	s.h[7] += h
}

// Add one byte
pub fn (mut s SHA256) put(c int) {
	if s.final {
		return
	}
	s.buf[s.bufn] = u8(c)
	s.bufn++
	s.len0 += 8
	if s.bufn == 64 {
		s.process_block()
		s.bufn = 0
	}
}

// Add multiple bytes
pub fn (mut s SHA256) write_bytes(buf []u8) {
	for b in buf {
		s.put(int(b))
	}
}

// Get the final hash (32 bytes)
pub fn (mut s SHA256) result() []u8 {
	if !s.final {
		// Padding
		s.buf[s.bufn] = 0x80
		s.bufn++
		if s.bufn > 56 {
			for s.bufn < 64 {
				s.buf[s.bufn] = 0
				s.bufn++
			}
			s.process_block()
			s.bufn = 0
		}
		for s.bufn < 56 {
			s.buf[s.bufn] = 0
			s.bufn++
		}
		// Append length in bits (big-endian)
		for i := 7; i >= 0; i-- {
			s.buf[s.bufn] = u8(s.len0 >> (i * 8))
			s.bufn++
		}
		s.process_block()
		s.final = true
	}

	mut out := []u8{len: 32}
	for i := 0; i < 8; i++ {
		out[i * 4] = u8(s.h[i] >> 24)
		out[i * 4 + 1] = u8(s.h[i] >> 16)
		out[i * 4 + 2] = u8(s.h[i] >> 8)
		out[i * 4 + 3] = u8(s.h[i])
	}
	return out
}
