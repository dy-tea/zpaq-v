// State table for bit history in ZPAQ context models
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// StateTable maps bit history states to probabilities
pub struct StateTable {
mut:
	ns [1024]u8 // next state table: ns[state*4+y*2+n0/n1]
}

// Create a new initialized state table
pub fn StateTable.new() StateTable {
	mut st := StateTable{}
	st.init()
	return st
}

// Initialize the state table
pub fn (mut st StateTable) init() {
	// State table: ns[state*4+y*2+which] = next state
	// States 0-254 represent bit history (n0,n1) counts
	// where n0 = number of 0 bits and n1 = number of 1 bits
	// State encoding: lower bits = n1 count, upper bits for state type

	// Initialize with default state transitions
	// This is a simplified version of the full libzpaq state table

	// State 0: initial state
	// Format for each state i: ns[i*4+0..3] = next states for (y=0,c=0), (y=0,c=1), (y=1,c=0), (y=1,c=1)

	// Build the state table based on (n0, n1) pairs
	// Total bits = n0 + n1
	// Each state encodes how many 0s and 1s we've seen

	// Simple state machine:
	// State = n0 * 16 + n1 (approximately)
	// Transitions increment the appropriate counter

	for i := 0; i < 256; i++ {
		// Extract n0, n1 from state
		n0 := (i >> 4) & 15
		n1 := i & 15

		// Next state for seeing a 0
		mut next0 := i
		if n0 < 15 {
			next0 = ((n0 + 1) << 4) | n1
		}

		// Next state for seeing a 1
		mut next1 := i
		if n1 < 15 {
			next1 = (n0 << 4) | (n1 + 1)
		}

		// Store transitions
		st.ns[i * 4 + 0] = u8(next0)
		st.ns[i * 4 + 1] = u8(next0)
		st.ns[i * 4 + 2] = u8(next1)
		st.ns[i * 4 + 3] = u8(next1)
	}
}

// Get next state after seeing bit y (0 or 1)
pub fn (st &StateTable) next(state int, y int) int {
	if state < 0 || state >= 256 {
		return 0
	}
	idx := state * 4 + y * 2
	if idx < 0 || idx >= 1024 {
		return 0
	}
	return int(st.ns[idx])
}

// Get initial probability estimate for a state
// Returns value from 0 (all 0s) to 4095 (all 1s)
pub fn (st &StateTable) cminit(state int) int {
	// Extract counts
	n0 := (state >> 4) & 15
	n1 := state & 15

	// Probability = n1 / (n0 + n1) * 4096
	total := n0 + n1
	if total == 0 {
		return 2048 // 50% probability
	}
	return (n1 * 4096 + total / 2) / total
}

// Get count of 0 bits in state
pub fn (st &StateTable) n0(state int) int {
	return (state >> 4) & 15
}

// Get count of 1 bits in state
pub fn (st &StateTable) n1(state int) int {
	return state & 15
}
