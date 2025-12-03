// ZPAQ compression library for V
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Component types for compression models
pub enum CompType {
	none_
	cons
	cm
	icm
	match_
	avg
	mix2
	mix
	isse
	sse
}

// ZPAQL opcodes (0-255)
pub const zpaql_nop = 0 // no operation
pub const zpaql_cons = 1 // constant
pub const zpaql_cm = 2 // context model
pub const zpaql_icm = 3 // indirect context model
pub const zpaql_match = 4 // match model
pub const zpaql_avg = 5 // average
pub const zpaql_mix2 = 6 // 2 input mixer
pub const zpaql_mix = 7 // n input mixer
pub const zpaql_isse = 8 // indirect SSE
pub const zpaql_sse = 9 // secondary symbol estimation

// Special opcodes
pub const zpaql_error = 56 // error instruction

// Arithmetic/logic opcodes - main groups
pub const zpaql_a_eq = 7 // a=
pub const zpaql_b_eq = 8 // b=
pub const zpaql_c_eq = 9 // c=
pub const zpaql_d_eq = 10 // d=

// Jump opcodes
pub const zpaql_jt = 39 // jump if true
pub const zpaql_jf = 47 // jump if false
pub const zpaql_jmp = 63 // unconditional jump
pub const zpaql_lj = 255 // long jump

// Memory opcodes
pub const zpaql_a_eq_m = 1 // a = *b
pub const zpaql_b_eq_m = 2 // b = *c

// Returns the length (in bytes) of opcode op
pub fn oplen(op u8) int {
	// LJ (255) is a 3-byte instruction
	if op == 255 {
		return 3
	}
	// All opcodes where (op & 7) == 7 have a 1-byte operand (2 bytes total)
	// This includes: 7, 15, 23, 31, 39, 47, 55, 63, 71, 79, 87, 95, 103, 111, 119, etc.
	// Exception: opcode 63 (jmp) is a jump, which also has 1-byte operand
	if (op & 7) == 7 {
		return 2
	}
	// All other opcodes are 1-byte instructions
	return 1
}

// Check if opcode is an error instruction
pub fn iserr(op u8) bool {
	return op == 56
}

// Component sizes in bytes for each component type index
// This includes the type byte itself
// Reference: libzpaq.cpp compsize[256]={0,2,3,2,3,4,6,6,3,5}
pub const compsize = [
	0, // none (0)
	2, // const (1): type + value
	3, // cm (2): type + sizebits + limit
	2, // icm (3): type + sizebits
	3, // match (4): type + sizebits + bufbits
	4, // avg (5): type + j + k + wt
	6, // mix2 (6): type + sizebits + j + k + rate + mask
	6, // mix (7): type + sizebits + j + m + rate + mask
	3, // isse (8): type + sizebits + j (j = previous component to use)
	5, // sse (9): type + sizebits + j + start + limit
]

// Get component type from byte value
pub fn get_comp_type(b u8) CompType {
	return match int(b) {
		0 { CompType.none_ }
		1 { CompType.cons }
		2 { CompType.cm }
		3 { CompType.icm }
		4 { CompType.match_ }
		5 { CompType.avg }
		6 { CompType.mix2 }
		7 { CompType.mix }
		8 { CompType.isse }
		9 { CompType.sse }
		else { CompType.none_ }
	}
}
