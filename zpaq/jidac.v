// JIDAC format support for ZPAQ journaling archives
// JIDAC enables proper file size tracking and deduplication
// Ported from zpaq by Matt Mahoney, public domain
module zpaq

import time

// JIDAC block types
const jidac_type_c = `c` // Transaction header
const jidac_type_d = `d` // Data block
const jidac_type_h = `h` // Fragment table (hash + size)
const jidac_type_i = `i` // Index (file metadata)

// Fragment entry in hash table
pub struct FragmentEntry {
pub mut:
	sha1  [20]u8 // Fragment SHA1 hash
	uncsize int    // Uncompressed size, -1 if unknown
}

// File entry for index
pub struct FileEntry {
pub mut:
	date i64     // Date as YYYYMMDDHHMMSS
	size i64     // Uncompressed size, -1 if unknown
	attr i64     // File attributes (first 8 bytes)
	ptr  []u32   // Fragment ID list
}

// Get current date/time as YYYYMMDDHHMMSS integer
fn get_jidac_date() i64 {
	t := time.now()
	return i64(t.year) * 10000000000 + i64(t.month) * 100000000 + i64(t.day) * 1000000 +
		i64(t.hour) * 10000 + i64(t.minute) * 100 + i64(t.second)
}

// Format number as zero-padded string of specified width
fn itos_pad(n i64, width int) string {
	mut s := n.str()
	for s.len < width {
		s = '0' + s
	}
	return s
}

// Create JIDAC filename: jDC<date14><type><num10>
fn make_jidac_filename(date i64, block_type u8, num u32) string {
	return 'jDC' + itos_pad(date, 14) + block_type.ascii_str() + itos_pad(i64(num), 10)
}

// Write 4-byte little-endian integer to byte array
fn put_u32_le_bytes(v u32) []u8 {
	return [u8(v & 0xFF), u8((v >> 8) & 0xFF), u8((v >> 16) & 0xFF), u8((v >> 24) & 0xFF)]
}

// Write 8-byte little-endian integer to byte array
fn put_u64_le_bytes(v i64) []u8 {
	mut result := []u8{len: 8}
	for i := 0; i < 8; i++ {
		result[i] = u8((v >> (i * 8)) & 0xFF)
	}
	return result
}

// Write a JIDAC block using store mode (method "0")
// Returns the bytes of the block
fn create_jidac_block(data []u8, filename string, uncsize int) []u8 {
	// Comment format for JIDAC: "<usize> jDC\x01"
	comment := uncsize.str() + ' jDC\x01'
	
	// Use a compressor to create a proper ZPAQ block
	mut comp := Compressor.new()
	mut output := FileWriter.new()
	comp.set_output(&output)
	
	// Use store mode (level 0)
	comp.start_block(0)
	comp.start_segment(filename, comment)
	
	// Write data
	mut input := FileReader.new(data)
	comp.set_input(&input)
	for comp.compress(65536) {}
	
	comp.end_segment()
	comp.end_block()
	
	return output.bytes()
}

// Create a data block (d block) with given compression method
// Note: For JIDAC compatibility with original zpaq, we always use store mode
// because the compression models may differ between implementations
fn create_data_block(data []u8, filename string, _ int) []u8 {
	// Comment format for JIDAC: "<usize> jDC\x01"
	comment := data.len.str() + ' jDC\x01'
	
	mut comp := Compressor.new()
	mut output := FileWriter.new()
	comp.set_output(&output)
	
	// Always use store mode (level 0) for JIDAC d blocks for compatibility
	comp.start_block(0)
	comp.start_segment(filename, comment)
	
	mut input := FileReader.new(data)
	comp.set_input(&input)
	for comp.compress(65536) {}
	
	comp.end_segment()
	comp.end_block()
	
	return output.bytes()
}

// JidacArchive for creating complete JIDAC archives
pub struct JidacArchive {
pub mut:
	date        i64
	fragments   []FragmentEntry  // Fragment table
	files       map[string]FileEntry // File index
	blocks      []JidacBlock // List of data blocks
	output      &Writer = unsafe { nil }
}

// Block info for tracking
struct JidacBlock {
mut:
	start_frag   u32   // First fragment ID
	frag_count   u32   // Number of fragments
	csize        u32   // Compressed size
	data         []u8  // Compressed block data
}

// Create new JIDAC archive
pub fn JidacArchive.new() JidacArchive {
	return JidacArchive{
		date:       get_jidac_date()
		fragments:  []FragmentEntry{}
		files:      map[string]FileEntry{}
		blocks:     []JidacBlock{}
	}
}

// Set output for the archive
pub fn (mut a JidacArchive) set_output(w &Writer) {
	unsafe {
		a.output = w
	}
}

// Add a fragment to the table
fn (mut a JidacArchive) add_fragment(sha1 []u8, size int) u32 {
	mut frag := FragmentEntry{
		uncsize: size
	}
	// Copy SHA1
	for i := 0; i < 20 && i < sha1.len; i++ {
		frag.sha1[i] = sha1[i]
	}
	a.fragments << frag
	return u32(a.fragments.len)
}

// Add a file to the index
fn (mut a JidacArchive) add_file(filename string, date i64, size i64, attr i64, frags []u32) {
	a.files[filename] = FileEntry{
		date: date
		size: size
		attr: attr
		ptr:  frags
	}
}

// Create a complete JIDAC archive with files
// Archive structure:
// 1. c block (transaction header) with data_size pointing past all d blocks
// 2. d blocks (data) - compressed file data
// 3. h blocks (fragment tables) - SHA1 + sizes  
// 4. i blocks (file index) - file metadata
pub fn (mut a JidacArchive) create_archive(files map[string][]u8, method int) {
	if a.output == unsafe { nil } {
		return
	}
	
	// Phase 1: Create all data blocks and track their sizes
	mut total_data_size := i64(0)
	mut frag_id := u32(0)
	
	for filename, data in files {
		// Compute SHA1 of file data
		mut sha1 := SHA1.new()
		sha1.write_bytes(data)
		hash := sha1.result()
		
		// Add fragment entry (1-indexed)
		frag_id = a.add_fragment(hash, data.len)
		
		// Track file info
		a.add_file(filename, a.date, i64(data.len), 0, [frag_id])
		
		// Create compressed data block with JIDAC naming
		block_filename := make_jidac_filename(a.date, jidac_type_d, frag_id)
		compressed := create_data_block(data, block_filename, method)
		
		total_data_size += compressed.len
		
		// Store block info
		a.blocks << JidacBlock{
			start_frag:  frag_id
			frag_count:  1
			csize:       u32(compressed.len)
			data:        compressed
		}
	}
	
	// Phase 2: Write c block (transaction header) with total data size
	c_block_filename := make_jidac_filename(a.date, jidac_type_c, frag_id + 1)
	c_block_content := put_u64_le_bytes(total_data_size)
	c_block := create_jidac_block(c_block_content, c_block_filename, c_block_content.len)
	
	for b in c_block {
		a.output.put(int(b))
	}
	
	// Phase 3: Write all data blocks
	for blk in a.blocks {
		for b in blk.data {
			a.output.put(int(b))
		}
	}
	
	// Phase 4: Write fragment tables (h blocks)
	// Each h block contains: bsize[4] (sha1[20] usize[4])...
	for blk in a.blocks {
		mut h_content := []u8{}
		
		// Write compressed block size
		h_content << put_u32_le_bytes(blk.csize)
		
		// Write fragment SHA1 and size
		start_idx := int(blk.start_frag) - 1
		end_idx := start_idx + int(blk.frag_count)
		for i := start_idx; i < end_idx; i++ {
			if i >= 0 && i < a.fragments.len {
				frag := a.fragments[i]
				// Write 20-byte SHA1
				for b in frag.sha1 {
					h_content << b
				}
				// Write 4-byte size
				h_content << put_u32_le_bytes(u32(frag.uncsize))
			}
		}
		
		h_block_filename := make_jidac_filename(a.date, jidac_type_h, blk.start_frag)
		h_block := create_jidac_block(h_content, h_block_filename, h_content.len)
		
		for b in h_block {
			a.output.put(int(b))
		}
	}
	
	// Phase 5: Write file index (i block)
	// Format: date[8] filename 0 na[4] attr[na] ni[4] ptr[ni][4]
	mut i_content := []u8{}
	
	for filename, entry in a.files {
		// Write 8-byte date
		i_content << put_u64_le_bytes(entry.date)
		
		// Write filename (null-terminated)
		i_content << filename.bytes()
		i_content << u8(0)
		
		if entry.date != 0 {
			// Write attribute count (0 = no attributes)
			i_content << put_u32_le_bytes(0)
			
			// Write fragment pointer count and pointers
			i_content << put_u32_le_bytes(u32(entry.ptr.len))
			for ptr in entry.ptr {
				i_content << put_u32_le_bytes(ptr)
			}
		}
	}
	
	if i_content.len > 0 {
		i_block_filename := make_jidac_filename(a.date, jidac_type_i, 1)
		i_block := create_jidac_block(i_content, i_block_filename, i_content.len)
		
		for b in i_block {
			a.output.put(int(b))
		}
	}
}
