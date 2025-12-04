// Predefined compression level configurations for ZPAQ
// These match libzpaq's compression levels for 1:1 compatibility
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// ZPAQ compression level configuration
// Each level defines the HCOMP header that configures the context model
pub struct CompressionLevel {
pub:
	name  string // level name
	hcomp []u8   // HCOMP header bytes
	hh    int    // log2 H array size
	hm    int    // log2 M array size
}

// Predefined compression levels matching libzpaq
// Level 0: Store (no compression)
// Level 1: Fast compression (order-1 CM with HASH)
// Level 2: Normal compression (order-3 ICM+ISSE with HASH)
// Level 3: High compression (order-5 ICM+ISSE chain)
// Level 4: Very high compression
// Level 5: Maximum compression

// Get compression level configuration
// Returns HCOMP header for the given level (0-5)
pub fn get_compression_level(level int) CompressionLevel {
	return match level {
		0 { level_0_store() }
		1 { level_1_fast() }
		2 { level_2_normal() }
		3 { level_3_high() }
		4 { level_4_max() }
		5 { level_5_max() }
		else { level_1_fast() }
	}
}

// Level 0: Store (no compression)
// Matches libzpaq's "comp 0 0 0 0 0 hcomp end" format
fn level_0_store() CompressionLevel {
	return CompressionLevel{
		name: 'store'
		// Header: hm=0 hh=0 ph=0 pm=0 n=0 0 0
		// This is the minimal header with no components and no HCOMP code
		hcomp: [u8(0), 0, 0, 0, 0, 0, 0]
		hh:   0
		hm:   0
	}
}

// Level 1: Fast compression - matches libzpaq model 1 (min.cfg)
// ICM + ISSE with order-2 context model
fn level_1_fast() CompressionLevel {
	return CompressionLevel{
		name: 'fast'
		// This matches libzpaq's model 1 exactly for compatibility
		// Header format: hm hh ph pm n [components] 0 [HCOMP code] 0
		hcomp: [
			u8(2), // hm = 4 bytes M array
			1, // hh = 2 words H array
			0, // ph = 0 (no PCOMP)
			0, // pm = 0
			2, // n = 2 components (ICM + ISSE)
			// Component 0: ICM (indirect context model)
			3, // type = ICM
			16, // size bits
			// Component 1: ISSE (improves ICM predictions)
			8, // type = ISSE
			19, // size bits
			0, // j = uses component 0's prediction
			0, // end of component definitions
			// HCOMP code: *b=a a=0 d=0 hash b-- hash *d=a d++ b-- hash b-- hash *d=a halt
			96, // *b=a
			4, // a=0
			28, // d=0
			59, // hash
			10, // b--
			59, // hash
			112, // *d=a
			25, // d++
			10, // b--
			59, // hash
			10, // b--
			59, // hash
			112, // *d=a
			56, // halt
			0, // end of HCOMP
		]
		hh: 1
		hm: 2
	}
}

// Level 2: Normal compression
// Order-1,2,3 context chain using ICM + ISSE with proper history tracking
fn level_2_normal() CompressionLevel {
	return CompressionLevel{
		name:  'normal'
		hcomp: [
			u8(16), // hm = 64KB M array
			9, // hh = 512 words H array
			0, // ph = 0
			0, // pm = 0
			3, // n = 3 components (ICM + 2 ISSE)
			// Component 0: ICM (order 1)
			// Format: type sizebits
			3, // type = ICM
			16, // size bits
			// Component 1: ISSE (order 2, uses component 0)
			// Format: type sizebits j
			8, // type = ISSE
			16, // size bits
			0, // j = input from component 0
			// Component 2: ISSE (order 3, uses component 1)
			// Format: type sizebits j
			8, // type = ISSE
			16, // size bits
			1, // j = input from component 1
			0, // end of component definitions
			// HCOMP code: b=c c-- *c=a d=0 hash *d=a d++ hash *d=a d++ hash *d=a halt
			// b=c : B points to previous bytes in M
			// c-- : move write position backward in circular buffer
			// *c=a : store current byte in M[C]
			// Then build context chain with repeated HASH operations
			74, // b=c
			18, // c--
			104, // *c=a
			95,
			0, // d=0
			59, // hash (order 1)
			112, // *d=a
			25, // d++
			59, // hash (order 2)
			112, // *d=a
			25, // d++
			59, // hash (order 3)
			112, // *d=a
			56, // halt
			0, // end of HCOMP
			0, // end of PCOMP
		]
		hh:    9
		hm:    16
	}
}

// Level 3: High compression
// Longer ISSE chain with order-1 through order-5 contexts
fn level_3_high() CompressionLevel {
	return CompressionLevel{
		name:  'high'
		hcomp: [
			u8(18), // hm = 256KB M array
			10, // hh = 1024 words H array
			0, // ph = 0
			0, // pm = 0
			5, // n = 5 components
			// Component 0: ICM
			// Format: type sizebits
			3, // type = ICM
			18, // size bits
			// Component 1: ISSE (uses component 0)
			// Format: type sizebits j
			8, // type = ISSE
			18, // size bits
			0, // j = input from component 0
			// Component 2: ISSE (uses component 1)
			8, // type = ISSE
			18, // size bits
			1, // j = input from component 1
			// Component 3: ISSE (uses component 2)
			8, // type = ISSE
			18, // size bits
			2, // j = input from component 2
			// Component 4: ISSE (uses component 3)
			8, // type = ISSE
			18, // size bits
			3, // j = input from component 3
			0, // end of components
			// HCOMP: b=c c-- *c=a d=0 hash *d=a d++ hash *d=a ...
			74, // b=c
			18, // c--
			104, // *c=a
			95,
			0, // d=0
			59, // hash (order 1)
			112, // *d=a
			25, // d++
			59, // hash (order 2)
			112, // *d=a
			25, // d++
			59, // hash (order 3)
			112, // *d=a
			25, // d++
			59, // hash (order 4)
			112, // *d=a
			25, // d++
			59, // hash (order 5)
			112, // *d=a
			56, // halt
			0, // end of HCOMP
			0, // end of PCOMP
		]
		hh:    10
		hm:    18
	}
}

// Level 4: Maximum compression
// Deeper ICM+ISSE chain with MIX2 combination
fn level_4_max() CompressionLevel {
	return CompressionLevel{
		name:  'max'
		hcomp: [
			u8(20), // hm = 1MB M array
			12, // hh = 4K words H array
			0, // ph = 0
			0, // pm = 0
			7, // n = 7 components
			// Component 0: ICM
			// Format: type sizebits
			3, // type = ICM
			20, // size bits
			// Component 1-5: ISSE chain
			// Format: type sizebits j
			8,
			20,
			0, // ISSE uses component 0
			8,
			20,
			1, // ISSE uses component 1
			8,
			20,
			2, // ISSE uses component 2
			8,
			20,
			3, // ISSE uses component 3
			8,
			20,
			4, // ISSE uses component 4
			// Component 6: MIX2
			// Format: type sizebits j k rate mask
			6, // type = MIX2
			16, // size bits
			4, // j = component 4
			5, // k = component 5
			24, // rate
			255, // mask
			0, // end of components
			// HCOMP: b=c c-- *c=a d=0 hash *d=a d++ hash *d=a ...
			74, // b=c
			18, // c--
			104, // *c=a
			95,
			0, // d=0
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112, // hash, *d=a
			56, // halt
			0, // end of HCOMP
			0, // end of PCOMP
		]
		hh:    12
		hm:    20
	}
}

// Level 5: Ultra compression
// Largest context chain for best compression
fn level_5_max() CompressionLevel {
	return CompressionLevel{
		name:  'ultra'
		hcomp: [
			u8(22), // hm = 4MB M array
			14, // hh = 16K words H array
			0, // ph = 0
			0, // pm = 0
			9, // n = 9 components
			// Component 0: ICM
			// Format: type sizebits
			3, // type = ICM
			22, // size bits
			// Components 1-7: ISSE chain
			// Format: type sizebits j
			8,
			22,
			0, // ISSE uses component 0
			8,
			22,
			1, // ISSE uses component 1
			8,
			22,
			2, // ISSE uses component 2
			8,
			22,
			3, // ISSE uses component 3
			8,
			22,
			4, // ISSE uses component 4
			8,
			22,
			5, // ISSE uses component 5
			8,
			22,
			6, // ISSE uses component 6
			// Component 8: MIX2
			// Format: type sizebits j k rate mask
			6, // type = MIX2
			18, // size bits
			6, // j = component 6
			7, // k = component 7
			24, // rate
			255, // mask
			0, // end of components
			// HCOMP: b=c c-- *c=a d=0 hash *d=a d++ hash *d=a ...
			74, // b=c
			18, // c--
			104, // *c=a
			95,
			0, // d=0
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112,
			25, // hash, *d=a, d++
			59,
			112, // hash, *d=a
			56, // halt
			0, // end of HCOMP
			0, // end of PCOMP
		]
		hh:    14
		hm:    22
	}
}

// Build HCOMP header for a given component configuration
// This allows custom configurations beyond predefined levels
pub fn build_hcomp_header(hm int, hh int, components []ComponentConfig) []u8 {
	mut header := []u8{}

	// Header: hm hh ph pm n [components] end(0) end(0)
	header << u8(hm)
	header << u8(hh)
	header << u8(0) // ph (no PCOMP)
	header << u8(0) // pm
	header << u8(components.len)

	// Add each component's configuration
	for comp in components {
		header << u8(comp.ctype)
		match comp.ctype {
			1 { // CONST
				header << u8(comp.p1)
			}
			2 { // CM
				header << u8(comp.p1) // size bits
				header << u8(comp.p2) // limit
			}
			3 { // ICM
				header << u8(comp.p1) // size bits
			}
			4 { // MATCH
				header << u8(comp.p1) // index bits
				header << u8(comp.p2) // buffer bits
			}
			5 { // AVG
				header << u8(comp.p1) // first component
				header << u8(comp.p2) // second component
				header << u8(comp.p3) // weight
			}
			6 { // MIX2
				header << u8(comp.p1) // size bits
				header << u8(comp.p2) // rate
			}
			7 { // MIX
				header << u8(comp.p1) // size bits
				header << u8(comp.p2) // n inputs
			}
			8 { // ISSE
				header << u8(comp.p1) // size bits
			}
			9 { // SSE
				header << u8(comp.p1) // size bits
				header << u8(comp.p2) // start
				header << u8(comp.p3) // limit
			}
			else {}
		}
	}

	// End markers
	header << u8(0)
	header << u8(0)

	return header
}

// Component configuration for building custom headers
pub struct ComponentConfig {
pub:
	ctype int // component type (1-9)
	p1    int // first parameter
	p2    int // second parameter
	p3    int // third parameter
}
