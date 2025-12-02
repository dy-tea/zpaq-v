// Tests for ZPAQ CLI functionality
module main

// Test pattern matching
fn test_matches_pattern_exact() {
	assert matches_pattern('test.txt', 'test.txt') == true
	assert matches_pattern('test.txt', 'test.doc') == false
}

fn test_matches_pattern_wildcard_star() {
	// * matches any string
	assert matches_pattern('test.txt', '*.txt') == true
	assert matches_pattern('file.txt', '*.txt') == true
	assert matches_pattern('test.doc', '*.txt') == false
	assert matches_pattern('test.txt', 'test.*') == true
	assert matches_pattern('test.doc', 'test.*') == true
	assert matches_pattern('file.txt', 'test.*') == false
	assert matches_pattern('abc', '*') == true
	assert matches_pattern('', '*') == true
}

fn test_matches_pattern_wildcard_question() {
	// ? matches any single character
	assert matches_pattern('test.txt', 'tes?.txt') == true
	assert matches_pattern('test.txt', 't?st.txt') == true
	assert matches_pattern('test.txt', '????.txt') == true
	assert matches_pattern('test.txt', '???.txt') == false
	assert matches_pattern('a', '?') == true
	assert matches_pattern('ab', '?') == false
}

fn test_matches_pattern_combined() {
	assert matches_pattern('test123.txt', 'test*.txt') == true
	assert matches_pattern('test.txt', 'test*.txt') == true
	assert matches_pattern('testa.txt', 'test?.txt') == true
	assert matches_pattern('test12.txt', 'test?.txt') == false
}

fn test_should_include_no_filters() {
	// No filters means include everything
	assert should_include('file.txt', [], []) == true
	assert should_include('anything', [], []) == true
}

fn test_should_include_only_filter() {
	// Only include specified patterns
	assert should_include('file.txt', ['*.txt'], []) == true
	assert should_include('file.doc', ['*.txt'], []) == false
	assert should_include('file.txt', ['*.txt', '*.doc'], []) == true
	assert should_include('file.doc', ['*.txt', '*.doc'], []) == true
	assert should_include('file.pdf', ['*.txt', '*.doc'], []) == false
}

fn test_should_include_not_filter() {
	// Exclude specified patterns
	assert should_include('file.txt', [], ['*.log']) == true
	assert should_include('file.log', [], ['*.log']) == false
	assert should_include('file.txt', [], ['*.log', '*.tmp']) == true
	assert should_include('file.tmp', [], ['*.log', '*.tmp']) == false
}

fn test_should_include_combined_filters() {
	// Both only and not filters
	assert should_include('file.txt', ['*.txt'], ['temp*']) == true
	assert should_include('temp.txt', ['*.txt'], ['temp*']) == false
	assert should_include('file.doc', ['*.txt'], ['temp*']) == false
}

fn test_is_numeric() {
	assert is_numeric('123') == true
	assert is_numeric('0') == true
	assert is_numeric('1234567890') == true
	assert is_numeric('') == false
	assert is_numeric('12a3') == false
	assert is_numeric('abc') == false
	assert is_numeric('-1') == false
}

fn test_preprocess_args_method() {
	// Test -mN conversion
	args := ['zpaq', 'add', 'test.zpaq', '-m2', 'file.txt']
	result := preprocess_args(args)
	assert '--method' in result
	assert '2' in result
}

fn test_preprocess_args_summary() {
	// Test -sN conversion
	args := ['zpaq', 'add', 'test.zpaq', '-s1', 'file.txt']
	result := preprocess_args(args)
	assert '--summary' in result
	assert '1' in result
}

fn test_preprocess_args_threads() {
	// Test -tN conversion
	args := ['zpaq', 'add', 'test.zpaq', '-t4', 'file.txt']
	result := preprocess_args(args)
	assert '--threads' in result
	assert '4' in result
}

fn test_preprocess_args_unchanged() {
	// Regular flags should pass through unchanged
	args := ['zpaq', 'add', 'test.zpaq', '--force', 'file.txt']
	result := preprocess_args(args)
	assert result == args
}

fn test_preprocess_args_short_flag() {
	// Short flags like -f should pass through
	args := ['zpaq', 'add', 'test.zpaq', '-f', 'file.txt']
	result := preprocess_args(args)
	assert '-f' in result
}
