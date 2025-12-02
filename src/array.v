// Dynamic array implementation for ZPAQ
// Ported from libzpaq by Matt Mahoney, public domain
module zpaq

// Generic dynamic array matching libzpaq's Array template
pub struct Array[T] {
mut:
	data []T
	size int
}

// Create a new array with given size
pub fn Array.new[T](size int) Array[T] {
	mut a := Array[T]{}
	a.resize(size)
	return a
}

// Resize the array
pub fn (mut a Array[T]) resize(size int) {
	if size < 0 {
		return
	}
	if size > a.data.len {
		// Grow array
		for _ in a.data.len .. size {
			a.data << T{}
		}
	} else if size < a.data.len {
		// Shrink array
		a.data = a.data[..size]
	}
	a.size = size
}

// Get length
pub fn (a &Array[T]) len() int {
	return a.size
}

// Get element at index
pub fn (a &Array[T]) get(i int) T {
	if i < 0 || i >= a.size {
		return T{}
	}
	return a.data[i]
}

// Set element at index
pub fn (mut a Array[T]) set(i int, val T) {
	if i >= 0 && i < a.size {
		a.data[i] = val
	}
}

// Get element with modulo addressing
pub fn (a &Array[T]) get_mod(i int) T {
	if a.size == 0 {
		return T{}
	}
	idx := i & (a.size - 1)
	if idx < 0 || idx >= a.size {
		return T{}
	}
	return a.data[idx]
}

// Set element with modulo addressing
pub fn (mut a Array[T]) set_mod(i int, val T) {
	if a.size == 0 {
		return
	}
	idx := i & (a.size - 1)
	if idx >= 0 && idx < a.size {
		a.data[idx] = val
	}
}

// Clear all elements to default value
pub fn (mut a Array[T]) clear() {
	for i := 0; i < a.size; i++ {
		a.data[i] = T{}
	}
}

// Direct access to underlying slice for performance
pub fn (a &Array[T]) slice() []T {
	return a.data
}

// Direct mutable access
pub fn (mut a Array[T]) slice_mut() []T {
	return a.data
}
