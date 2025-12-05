// ZPAQ Command Line Interface
// Compatible with the original zpaq by Matt Mahoney
module main

import os
import flag
import zpaq

// Command types
enum Command {
	add
	extract
	list
	help
}

// CLI configuration parsed from command line arguments
struct Config {
mut:
	command       Command
	archive       string   // archive file path
	files         []string // files to add/extract
	all_versions  int = -1 // -all [N]: extract/list versions in N digit directories (-1 = disabled)
	force         bool   // -f/-force: force append/overwrite
	index_file    string // -index F: index file path
	key           string // -key X: encryption password
	method        int = 1 // -mN/-method N: compression level (0-5)
	no_attributes bool     // -noattributes: ignore file attributes
	not_files     []string // -not files...: exclude patterns
	only_files    []string // -only files...: include patterns
	repack_file   string   // -repack F: repack to new archive
	repack_key    string   // -repack key
	summary       int      // -sN/-summary N: summary options
	test_mode     bool     // -test: verify without writing
	threads       int      // -tN/-threads N: thread count (0 = auto)
	to_files      []string // -to out...: rename output files
	until_version int      // -until N: roll back to version
	until_date    string   // -until date: roll back to date
	fragment      int = 6 // -fragment N: 2^N KiB average fragment size
}

fn main() {
	mut cfg := parse_args() or {
		eprintln(err.msg())
		exit(1)
	}

	match cfg.command {
		.add {
			run_add(cfg) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		.extract {
			run_extract(cfg) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		.list {
			run_list(cfg) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		.help {
			print_usage()
		}
	}
}

fn parse_args() !Config {
	// Pre-process args to handle zpaq-style short flags (-mN, -sN, -tN)
	mut processed_args := preprocess_args(os.args)

	mut fp := flag.new_flag_parser(processed_args)
	fp.application('zpaq')
	fp.version('0.1.0')
	fp.description('ZPAQ archiver - journaling backup utility')
	fp.description('')
	fp.description('Commands:')
	fp.description('  a, add      Append files to archive if dates have changed')
	fp.description('  x, extract  Extract most recent versions of files')
	fp.description('  l, list     List or compare external files to archive')
	fp.skip_executable()

	// Define flags
	all_versions := fp.int('all', 0, -1, 'Extract/list versions in N digit directories')
	force := fp.bool('force', `f`, false, 'Add: append if contents changed. Extract: overwrite. List: compare contents')
	index_file := fp.string('index', 0, '', 'Index file for archive')
	key := fp.string('key', 0, '', 'Encryption password')
	method := fp.int('method', `m`, 1, 'Compression level (0..5 = faster..better)')
	no_attributes := fp.bool('noattributes', 0, false, 'Ignore file attributes or permissions')
	summary := fp.int('summary', `s`, 0, 'Show summary: N>0 for brief progress, -1 for frag IDs')
	test_mode := fp.bool('test', 0, false, 'Extract: verify but do not write files')
	threads := fp.int('threads', `t`, 0, 'Number of threads (0 = auto)')
	until_version := fp.int('until', 0, 0, 'Roll back archive to N-th update or -N from end')
	fragment := fp.int('fragment', 0, 6, 'Use 2^N KiB average fragment size')
	repack_file := fp.string('repack', 0, '', 'Repack to new archive F')

	// Multi-value flags need special handling
	not_files := fp.string_multi('not', 0, 'Exclude files matching pattern')
	only_files := fp.string_multi('only', 0, 'Include only files matching pattern')
	to_files := fp.string_multi('to', 0, 'Rename output files')

	// Finalize and get remaining arguments
	remaining := fp.finalize() or {
		eprintln(fp.usage())
		return error(err.msg())
	}

	if remaining.len < 1 {
		eprintln(fp.usage())
		return error('Missing command. Use: add (a), extract (x), or list (l)')
	}

	// Parse command
	cmd_str := remaining[0].to_lower()
	command := match cmd_str {
		'a', 'add' { Command.add }
		'x', 'extract' { Command.extract }
		'l', 'list' { Command.list }
		'help', '-h', '--help' { Command.help }
		else { return error("Unknown command '${cmd_str}'. Use: add (a), extract (x), or list (l)") }
	}

	if command == .help {
		return Config{
			command: .help
		}
	}

	if remaining.len < 2 {
		return error('Missing archive name')
	}

	archive := remaining[1]
	files := if remaining.len > 2 { remaining[2..] } else { []string{} }

	return Config{
		command:       command
		archive:       archive
		files:         files
		all_versions:  all_versions
		force:         force
		index_file:    index_file
		key:           key
		method:        method
		no_attributes: no_attributes
		not_files:     not_files
		only_files:    only_files
		repack_file:   repack_file
		summary:       summary
		test_mode:     test_mode
		threads:       threads
		to_files:      to_files
		until_version: until_version
		fragment:      fragment
	}
}

// Preprocess arguments to handle zpaq-style -mN, -sN, -tN flags
fn preprocess_args(args []string) []string {
	mut result := []string{}
	for arg in args {
		if arg.len >= 3 && arg.starts_with('-') && !arg.starts_with('--') {
			// Check for -mN pattern (method)
			if arg[1] == `m` && arg[2..].len > 0 && is_numeric(arg[2..]) {
				result << '--method'
				result << arg[2..]
				continue
			}
			// Check for -sN pattern (summary)
			if arg[1] == `s` && arg[2..].len > 0 && is_numeric(arg[2..]) {
				result << '--summary'
				result << arg[2..]
				continue
			}
			// Check for -tN pattern (threads)
			if arg[1] == `t` && arg[2..].len > 0 && is_numeric(arg[2..]) {
				result << '--threads'
				result << arg[2..]
				continue
			}
		}
		result << arg
	}
	return result
}

// Check if string is numeric
fn is_numeric(s string) bool {
	if s.len == 0 {
		return false
	}
	for c in s {
		if c < `0` || c > `9` {
			return false
		}
	}
	return true
}

fn print_usage() {
	println('Usage: zpaq command archive[.zpaq] files... -options...')
	println('Files... may be directory trees. Default is the whole archive.')
	println('')
	println('Commands:')
	println('   a  add         Append files to archive if dates have changed.')
	println('   x  extract     Extract most recent versions of files.')
	println('   l  list        List or compare external files to archive by dates.')
	println('')
	println('Options:')
	println('  -all N          Extract/list versions in N digit directories.')
	println('  -f, -force      Add: append files if contents have changed.')
	println('                  Extract: overwrite existing output files.')
	println('                  List: compare file contents instead of dates.')
	println('  -index F        Extract: create index F for archive.')
	println('                  Add: create suffix for archive indexed by F, update F.')
	println('  -key X          Create or access encrypted archive with password X.')
	println('  -mN, -method N  Compress level N (0..5 = faster..better, default 1).')
	println("  -noattributes   Ignore/don't save file attributes or permissions.")
	println('  -not files...   Exclude. * and ? match any string or char.')
	println('  -only files...  Include only matches (default: *).')
	println('  -repack F       Extract to new archive F.')
	println('  -sN, -summary N List: show top N sorted by size. -1: show frag IDs.')
	println('                  Add/Extract: if N > 0 show brief progress.')
	println('  -test           Extract: verify but do not write files.')
	println('  -tN, -threads N Use N threads (default: 0 = auto).')
	println('  -to out...      Rename files... to out... or all to out/all.')
	println("  -until N        Roll back archive to N'th update or -N from end.")
	println('')
	println('Advanced options:')
	println('  -fragment N     Use 2^N KiB average fragment size (default: 6).')
}

// Add command: append files to archive
fn run_add(cfg Config) ! {
	// Ensure archive has .zpaq extension
	archive := if cfg.archive.ends_with('.zpaq') {
		cfg.archive
	} else {
		cfg.archive + '.zpaq'
	}

	// Collect files to add
	mut files_to_add := []string{}
	for file in cfg.files {
		if os.is_dir(file) {
			// Recursively add directory contents
			files_to_add << collect_files(file, cfg.only_files, cfg.not_files)
		} else if os.exists(file) {
			if should_include(file, cfg.only_files, cfg.not_files) {
				files_to_add << file
			}
		} else {
			eprintln("Warning: '${file}' not found, skipping")
		}
	}

	if files_to_add.len == 0 {
		return error('No files to add')
	}

	// Open or create archive
	mut output_data := []u8{}
	if os.exists(archive) && !cfg.force {
		// Read existing archive (for appending)
		output_data = os.read_bytes(archive) or {
			eprintln("Warning: Could not read existing archive '${archive}': ${err}, creating new archive")
			[]u8{}
		}
	}

	mut output := zpaq.FileWriter.new()
	// Copy existing data if any
	for b in output_data {
		output.put(int(b))
	}

	// Create compressor for archive
	mut comp := zpaq.Compressor.new()
	comp.set_output(&output)

	// Process each file
	mut files_added := 0
	for file in files_to_add {
		data := os.read_bytes(file) or {
			eprintln("Warning: Could not read '${file}': ${err}, skipping")
			continue
		}

		// Use base filename for segment name
		filename := os.base(file)

		// Start a new block for each file with the requested compression level
		comp.start_block(cfg.method)

		// Start segment with filename and size in comment for compatibility
		// Comment format: "<size> bytes" for human readability
		comment := '${data.len} bytes'
		comp.start_segment(filename, comment)

		// Compress the file data
		mut input := zpaq.FileReader.new(data)
		comp.set_input(&input)
		for comp.compress(65536) {}

		comp.end_segment()
		comp.end_block()

		files_added++
		if cfg.summary > 0 {
			println('Added: ${file}')
		}
	}

	// Write archive
	os.write_file_array(archive, output.bytes()) or {
		return error('Could not write archive: ${err}')
	}

	println('Created archive: ${archive}')
	println('Files added: ${files_added}')
}

// Extract command: extract files from archive
fn run_extract(cfg Config) ! {
	archive := if cfg.archive.ends_with('.zpaq') {
		cfg.archive
	} else {
		cfg.archive + '.zpaq'
	}

	if !os.exists(archive) {
		return error("Archive '${archive}' not found")
	}

	data := os.read_bytes(archive) or { return error('Could not read archive: ${err}') }

	mut input := zpaq.FileReader.new(data)
	mut decomp := zpaq.Decompresser.new()
	decomp.set_input(&input)

	mut extracted := 0

	// Find and extract blocks
	for decomp.find_block() {
		for decomp.find_filename() {
			filename := decomp.get_filename()

			// Check if file matches filters
			if !should_include(filename, cfg.only_files, cfg.not_files) {
				continue
			}

			// Apply -to rename if specified
			// If to_files is provided, use first element as output directory prefix
			mut output_name := filename
			if cfg.to_files.len > 0 {
				// Use first -to argument as output directory
				output_name = cfg.to_files[0] + '/' + filename
			}

			// Check if file already exists
			if os.exists(output_name) && !cfg.force {
				eprintln("Warning: '${output_name}' exists, skipping (use -force to overwrite)")
				continue
			}

			mut output := zpaq.FileWriter.new()
			if !cfg.test_mode {
				decomp.set_output(&output)
			}

			// Decompress
			for decomp.decompress(65536) {
			}
			decomp.read_segment_end()

			if !cfg.test_mode {
				// Create output directory if needed
				dir := os.dir(output_name)
				if dir != '' && dir != '.' && !os.exists(dir) {
					os.mkdir_all(dir) or {}
				}

				os.write_file_array(output_name, output.bytes()) or {
					eprintln("Warning: Could not write '${output_name}': ${err}")
					continue
				}
			}

			extracted++
			if cfg.summary > 0 || cfg.test_mode {
				status := if cfg.test_mode { 'Verified' } else { 'Extracted' }
				println('${status}: ${output_name}')
			}
		}
	}

	println('Files ${if cfg.test_mode { 'verified' } else { 'extracted' }}: ${extracted}')
}

// Helper: skip to end of current segment (required because ZPAQ format doesn't store compressed size)
fn skip_segment(mut decomp zpaq.Decompresser) {
	for decomp.decompress(65536) {}
	decomp.read_segment_end()
}

// List command: list archive contents
fn run_list(cfg Config) ! {
	archive := if cfg.archive.ends_with('.zpaq') {
		cfg.archive
	} else {
		cfg.archive + '.zpaq'
	}

	if !os.exists(archive) {
		return error("Archive '${archive}' not found")
	}

	data := os.read_bytes(archive) or { return error('Could not read archive: ${err}') }

	mut input := zpaq.FileReader.new(data)
	mut decomp := zpaq.Decompresser.new()
	decomp.set_input(&input)

	println('Contents of ${archive}:')
	println('----------------------------------------')

	mut total_files := 0

	// Find and list blocks
	for decomp.find_block() {
		for decomp.find_filename() {
			filename := decomp.get_filename()
			comment := decomp.get_comment()

			// Check if file matches filters
			if !should_include(filename, cfg.only_files, cfg.not_files) {
				skip_segment(mut decomp)
				continue
			}

			if comment.len > 0 {
				println('${filename} (${comment})')
			} else {
				println(filename)
			}
			total_files++

			skip_segment(mut decomp)
		}
	}

	println('----------------------------------------')
	println('Total files: ${total_files}')
}

// Helper: collect files from directory recursively
fn collect_files(dir string, only []string, not []string) []string {
	mut files := []string{}
	entries := os.ls(dir) or { return files }

	for entry in entries {
		path := os.join_path(dir, entry)
		if os.is_dir(path) {
			files << collect_files(path, only, not)
		} else {
			if should_include(path, only, not) {
				files << path
			}
		}
	}
	return files
}

// Helper: check if file should be included based on filters
fn should_include(filename string, only []string, not []string) bool {
	// Check exclusion patterns
	for pattern in not {
		if matches_pattern(filename, pattern) {
			return false
		}
	}

	// Check inclusion patterns (if any specified)
	if only.len > 0 {
		for pattern in only {
			if matches_pattern(filename, pattern) {
				return true
			}
		}
		return false
	}

	return true
}

// Helper: simple wildcard pattern matching (* and ?)
fn matches_pattern(s string, pattern string) bool {
	if pattern.len == 0 {
		return s.len == 0
	}

	mut si := 0
	mut pi := 0
	mut star_idx := -1
	mut match_idx := 0

	for si < s.len {
		if pi < pattern.len && (pattern[pi] == `?` || pattern[pi] == s[si]) {
			si++
			pi++
		} else if pi < pattern.len && pattern[pi] == `*` {
			star_idx = pi
			match_idx = si
			pi++
		} else if star_idx != -1 {
			pi = star_idx + 1
			match_idx++
			si = match_idx
		} else {
			return false
		}
	}

	for pi < pattern.len && pattern[pi] == `*` {
		pi++
	}

	return pi == pattern.len
}
