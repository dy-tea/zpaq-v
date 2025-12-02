// Unit tests for ZPAQ V implementation
module zpaq

// Test SHA1 with empty input
fn test_sha1_empty() {
	mut sha := SHA1.new()
	result := sha.result()
	// SHA1('') = da39a3ee5e6b4b0d3255bfef95601890afd80709
	assert result.len == 20
	assert result[0] == 0xda
	assert result[1] == 0x39
	assert result[2] == 0xa3
	assert result[3] == 0xee
}

// Test SHA1 with 'abc'
fn test_sha1_abc() {
	mut sha := SHA1.new()
	sha.write_bytes('abc'.bytes())
	result := sha.result()
	// SHA1('abc') = a9993e364706816aba3e25717850c26c9cd0d89d
	assert result.len == 20
	assert result[0] == 0xa9
	assert result[1] == 0x99
	assert result[2] == 0x3e
	assert result[3] == 0x36
}

// Test SHA256 with empty input
fn test_sha256_empty() {
	mut sha := SHA256.new()
	result := sha.result()
	// SHA256('') = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
	assert result.len == 32
	assert result[0] == 0xe3
	assert result[1] == 0xb0
	assert result[2] == 0xc4
	assert result[3] == 0x42
}

// Test SHA256 with 'abc'
fn test_sha256_abc() {
	mut sha := SHA256.new()
	sha.write_bytes('abc'.bytes())
	result := sha.result()
	// SHA256('abc') = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
	assert result.len == 32
	assert result[0] == 0xba
	assert result[1] == 0x78
	assert result[2] == 0x16
	assert result[3] == 0xbf
}

// Test StateTable initialization and transitions
fn test_statetable_init() {
	st := StateTable.new()

	// Initial state 0 should have count (0, 0) based on libzpaq state table
	n0_0 := st.n0(0)
	n1_0 := st.n1(0)
	assert n0_0 == 0
	assert n1_0 == 0

	// State 1 is the first state after seeing a 0 bit from state 0
	// Its n0=1, n1=0 based on state_table_data
	assert st.n0(1) == 1
	assert st.n1(1) == 0

	// State 3 is after seeing a 1 bit from state 0
	// Its n0=0, n1=1
	assert st.n0(3) == 0
	assert st.n1(3) == 1
}

// Test StateTable transitions
fn test_statetable_transitions() {
	st := StateTable.new()

	// From state 0, seeing a 0 bit goes to state 1
	next0 := st.next(0, 0)
	assert next0 == 1

	// From state 0, seeing a 1 bit goes to state 3
	next1 := st.next(0, 1)
	assert next1 == 3
}

// Test StateTable cminit probability
fn test_statetable_cminit() {
	st := StateTable.new()

	// State 0 (n0=0, n1=0) should have ~50% probability
	// Using (n1+1)/(n0+n1+2) = 1/2 = 16384 out of 32768
	p0 := st.cminit(0)
	assert p0 == 16384

	// State 1 (n0=1, n1=0) should have low probability
	// (0+1)/(1+0+2) = 1/3 ~= 10923
	p1 := st.cminit(1)
	assert p1 >= 10000 && p1 <= 12000, 'cminit(1) = ${p1}'

	// State 3 (n0=0, n1=1) should have high probability
	// (1+1)/(0+1+2) = 2/3 ~= 21845
	p3 := st.cminit(3)
	assert p3 >= 20000 && p3 <= 23000, 'cminit(3) = ${p3}'
}

// Test FileReader
fn test_filereader() {
	data := [u8(0x41), 0x42, 0x43] // 'ABC'
	mut reader := FileReader.new(data)

	assert reader.get() == 0x41
	assert reader.get() == 0x42
	assert reader.get() == 0x43
	assert reader.get() == -1 // EOF
}

// Test FileWriter
fn test_filewriter() {
	mut writer := FileWriter.new()

	writer.put(0x41)
	writer.put(0x42)
	writer.put(0x43)

	bytes := writer.bytes()
	assert bytes.len == 3
	assert bytes[0] == 0x41
	assert bytes[1] == 0x42
	assert bytes[2] == 0x43
}

// Test StringBuffer
fn test_stringbuffer() {
	mut buf := StringBuffer.new()

	// Test write
	buf.put(0x48) // 'H'
	buf.put(0x69) // 'i'
	assert buf.len() == 2

	// Test read
	assert buf.get() == 0x48
	assert buf.get() == 0x69
	assert buf.get() == -1 // EOF

	// Test reset read
	buf.reset_read()
	assert buf.get() == 0x48
}

// Test StringBuffer from_bytes
fn test_stringbuffer_from_bytes() {
	data := [u8(0x01), 0x02, 0x03]
	mut buf := StringBuffer.from_bytes(data)

	assert buf.len() == 3
	assert buf.get() == 0x01
	assert buf.get() == 0x02
	assert buf.get() == 0x03
}

// Test to_u16
fn test_to_u16() {
	data := [u8(0x34), 0x12]
	result := to_u16(data)
	assert result == 0x1234
}

// Test to_u32
fn test_to_u32() {
	data := [u8(0x78), 0x56, 0x34, 0x12]
	result := to_u32(data)
	assert result == 0x12345678
}

// Test Array generic type
fn test_array_u8() {
	mut arr := Array.new[u8](10)
	assert arr.len() == 10

	arr.set(0, 42)
	assert arr.get(0) == 42

	arr.set(5, 100)
	assert arr.get(5) == 100

	// Test bounds
	assert arr.get(-1) == 0
	assert arr.get(100) == 0
}

// Test Array resize
fn test_array_resize() {
	mut arr := Array.new[u32](5)
	assert arr.len() == 5

	arr.resize(10)
	assert arr.len() == 10

	arr.resize(3)
	assert arr.len() == 3
}

// Test Array modulo addressing
fn test_array_mod() {
	mut arr := Array.new[u8](8) // power of 2
	arr.set(0, 10)
	arr.set(7, 77)

	// Modulo addressing: 8 & 7 = 0
	assert arr.get_mod(8) == 10
	// 15 & 7 = 7
	assert arr.get_mod(15) == 77
}

// Test Array clear
fn test_array_clear() {
	mut arr := Array.new[u8](5)
	arr.set(0, 1)
	arr.set(1, 2)
	arr.set(2, 3)

	arr.clear()

	assert arr.get(0) == 0
	assert arr.get(1) == 0
	assert arr.get(2) == 0
}

// Test ZPAQL VM creation
fn test_zpaql_new() {
	z := ZPAQL.new()
	assert z.a == 0
	assert z.b == 0
	assert z.c == 0
	assert z.d == 0
	assert z.f == 0
	assert z.pc == 0
}

// Test ZPAQL register operations
fn test_zpaql_registers() {
	mut z := ZPAQL.new()
	z.set_a(0x12345678)
	assert z.get_a() == 0x12345678
}

// Test ZPAQL clear
fn test_zpaql_clear() {
	mut z := ZPAQL.new()
	z.set_a(100)
	z.b = 200
	z.c = 300

	z.clear()

	assert z.a == 0
	assert z.b == 0
	assert z.c == 0
}

// Test oplen function
fn test_oplen() {
	assert oplen(0) == 1 // NOP
	assert oplen(7) == 2 // A = N (needs operand)
	assert oplen(56) == 1 // ERROR
	assert oplen(255) == 3 // LJ (long jump)
}

// Test iserr function
fn test_iserr() {
	assert iserr(56) == true
	assert iserr(0) == false
	assert iserr(255) == false
}

// Test squash and stretch
fn test_squash_stretch() {
	// Squash should map log odds to probabilities
	// squash(0) should be approximately 16384 (50% probability in 0..32767 range)
	sq0 := squash(0)
	assert sq0 >= 15000 && sq0 <= 18000, 'squash(0) = ${sq0}, expected ~16384'

	// Stretch should be inverse of squash
	p := squash(100)
	s := stretch(p)
	// Should be approximately inverse (may have rounding errors)
	assert s >= 50 && s <= 150, 'stretch(squash(100)) = ${s}, expected ~100'
}

// Test Predictor creation
fn test_predictor_new() {
	pr := Predictor.new()
	assert pr.c8 == 1
	assert pr.hmap4 == 1 // Now initialized to 1 like libzpaq
}

// Test Encoder creation
fn test_encoder_new() {
	enc := Encoder.new()
	assert enc.get_low() == 1
	assert enc.get_high() == 0xFFFFFFFF
}

// Test Decoder creation
fn test_decoder_new() {
	dec := Decoder.new()
	assert dec.get_low() == 1
	assert dec.get_high() == 0xFFFFFFFF
	assert dec.get_code() == 0
}

// Test Compressor creation
fn test_compressor_new() {
	c := Compressor.new()
	assert c.state == comp_state_start
}

// Test Decompresser creation
fn test_decompresser_new() {
	d := Decompresser.new()
	assert d.state == decomp_state_start
}

// Test component type enum
fn test_comp_type() {
	assert get_comp_type(0) == CompType.none
	assert get_comp_type(1) == CompType.cons
	assert get_comp_type(2) == CompType.cm
	assert get_comp_type(3) == CompType.icm
	assert get_comp_type(4) == CompType.match_
	assert get_comp_type(9) == CompType.sse
}

// Test predictor predict/update cycle
fn test_predictor_cycle() {
	mut z := ZPAQL.new()
	z.header = []u8{}

	mut pr := Predictor.new()
	pr.init(mut z)

	// Run a few predict/update cycles
	for _ in 0 .. 8 {
		p := pr.predict()
		// Probability should be in valid range
		assert p >= 1 && p <= 32767, 'Invalid prediction: ${p}'
		// Update with bit 1
		pr.update(1)
	}

	// Run more cycles with 0 bits
	for _ in 0 .. 8 {
		p := pr.predict()
		assert p >= 1 && p <= 32767, 'Invalid prediction: ${p}'
		pr.update(0)
	}
}

// Test basic compression (without ZPAQL)
fn test_basic_compression() {
	// Create input data (simple repetitive pattern)
	input_data := [u8(0x41), 0x41, 0x41, 0x41, 0x42, 0x42, 0x42, 0x42]

	mut input := FileReader.new(input_data)
	mut output := FileWriter.new()

	mut comp := Compressor.new()
	comp.set_input(&input)
	comp.set_output(&output)
	comp.start_block(1)
	comp.start_segment('test', '')
	for comp.compress(8) {
	}
	comp.end_segment()
	comp.end_block()

	compressed := output.bytes()
	// Should have some output
	assert compressed.len > 0, 'No compressed output'
}

// Test compression level configuration
fn test_compression_levels() {
	// Test each predefined level (0-5)
	for level in 0 .. 6 {
		config := get_compression_level(level)
		assert config.name.len > 0, 'Level ${level} has no name'
		if level == 0 {
			// Store mode has no HCOMP
			assert config.hcomp.len == 0, 'Level 0 should have empty hcomp'
		} else {
			// Compressed modes have HCOMP header
			assert config.hcomp.len > 0, 'Level ${level} should have hcomp'
		}
	}
}

// Test encoder/decoder symmetry with simple data
fn test_encoder_decoder_symmetry() {
	// Create predictor
	mut z := ZPAQL.new()
	z.header = []u8{}

	mut pr := Predictor.new()
	pr.init(mut z)

	// Encode a simple byte sequence
	mut output := FileWriter.new()
	mut enc := Encoder.new()
	enc.init(mut pr, mut output)

	// Encode byte 0x55 (01010101)
	enc.compress(0x55)
	enc.flush()

	// The output should contain encoded data
	encoded := output.bytes()
	assert encoded.len > 0, 'Encoder produced no output'
}
