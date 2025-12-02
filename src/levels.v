// Predefined compression level configurations for ZPAQ
// These match libzpaq's compression levels for 1:1 compatibility
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// ZPAQ compression level configuration
// Each level defines the HCOMP header that configures the context model
pub struct CompressionLevel {
pub:
	name   string // level name
	hcomp  []u8   // HCOMP header bytes
	hh     int    // log2 H array size
	hm     int    // log2 M array size
}

// Predefined compression levels matching libzpaq
// Level 0: Store (no compression)
// Level 1: Fast compression (order-3 CM)
// Level 2: Normal compression
// Level 3: High compression
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
		5 { level_4_max() } // Same as 4
		else { level_1_fast() }
	}
}

// Level 0: Store (no compression)
// Simple pass-through with no context model
fn level_0_store() CompressionLevel {
	return CompressionLevel{
		name:  'store'
		hcomp: []u8{}
		hh:    0
		hm:    0
	}
}

// Level 1: Fast compression
// Order-1 CM with hash table
// HCOMP header: hm=4 hh=4 ph=0 pm=0 n=1 CM(16,4)
fn level_1_fast() CompressionLevel {
	return CompressionLevel{
		name: 'fast'
		// Header: hm(4) hh(4) ph(0) pm(0) n(1) [comp: CM type(2) size(16) limit(4)] end(0)
		hcomp: [
			u8(4), // hm = log2 M size (16 bytes)
			4, // hh = log2 H size (16 words)
			0, // ph = 0 (no PCOMP)
			0, // pm = 0
			1, // n = 1 component
			// Component 0: CM
			2, // type = CM
			16, // size bits
			4, // limit (learning rate)
			// End markers
			0, // end of HCOMP
			0, // end of PCOMP
		]
		hh: 4
		hm: 4
	}
}

// Level 2: Normal compression
// Order-3 ICM + ISSE chain
fn level_2_normal() CompressionLevel {
	return CompressionLevel{
		name: 'normal'
		hcomp: [
			u8(5), // hm = 32 bytes
			5, // hh = 32 words
			0, // ph = 0
			0, // pm = 0
			4, // n = 4 components
			// Component 0: ICM (order 1)
			3, // type = ICM
			16, // size bits
			// Component 1: ISSE
			8, // type = ISSE
			16, // size bits
			// Component 2: ISSE
			8, // type = ISSE
			16, // size bits
			// Component 3: ISSE
			8, // type = ISSE
			16, // size bits
			// HCOMP code
			0, // end
			0, // end
		]
		hh: 5
		hm: 5
	}
}

// Level 3: High compression
// More components and larger hash tables
fn level_3_high() CompressionLevel {
	return CompressionLevel{
		name: 'high'
		hcomp: [
			u8(6), // hm = 64 bytes
			6, // hh = 64 words
			0, // ph = 0
			0, // pm = 0
			6, // n = 6 components
			// Component 0: ICM
			3, // type = ICM
			18, // size bits
			// Component 1: ISSE
			8, // type = ISSE
			18, // size bits
			// Component 2: ISSE
			8, // type = ISSE
			18, // size bits
			// Component 3: ISSE
			8, // type = ISSE
			18, // size bits
			// Component 4: MATCH
			4, // type = MATCH
			20, // index bits
			20, // buffer bits
			// Component 5: MIX2
			6, // type = MIX2
			16, // size bits
			16, // rate
			// End
			0,
			0,
		]
		hh: 6
		hm: 6
	}
}

// Level 4: Maximum compression
// Full model with all component types
fn level_4_max() CompressionLevel {
	return CompressionLevel{
		name: 'max'
		hcomp: [
			u8(8), // hm = 256 bytes
			8, // hh = 256 words
			0, // ph = 0
			0, // pm = 0
			8, // n = 8 components
			// Component 0: ICM
			3, // type = ICM
			20, // size bits
			// Component 1: ISSE
			8, // type = ISSE
			20, // size bits
			// Component 2: ISSE
			8, // type = ISSE
			20, // size bits
			// Component 3: ISSE
			8, // type = ISSE
			20, // size bits
			// Component 4: ISSE
			8, // type = ISSE
			20, // size bits
			// Component 5: MATCH
			4, // type = MATCH
			22, // index bits
			22, // buffer bits
			// Component 6: MIX2
			6, // type = MIX2
			18, // size bits
			16, // rate
			// Component 7: SSE
			9, // type = SSE
			16, // size bits
			32, // start
			4, // limit
			// End
			0,
			0,
		]
		hh: 8
		hm: 8
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
