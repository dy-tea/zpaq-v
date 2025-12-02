# ZPAQ Compression Library for V

A V programming language port of the ZPAQ compression library, originally written by Matt Mahoney (public domain).

ZPAQ is a journaling archiver optimized for incremental backups with strong compression using context mixing and a custom virtual machine (ZPAQL).

## Features

- **SHA1 and SHA256** hash implementations
- **ZPAQL Virtual Machine** for executing ZPAQL programs
- **Arithmetic coding** encoder and decoder
- **Context mixing predictor** with multiple component types
- **High-level compressor and decompressor** APIs
- **Dynamic arrays** with modulo addressing
- **State tables** for bit history tracking

## Installation

Add `zpaq` to your V project:

```bash
v install dy-tea.zpaq
```

Or clone directly:

```bash
git clone https://github.com/dy-tea/zpaq-v.git
cd zpaq-v
v test src/
```

## Usage

### Basic Compression

```v
import zpaq

// Create compressor
mut comp := zpaq.Compressor.new()

// Set up input and output
mut input := zpaq.FileReader.new(data)
mut output := zpaq.FileWriter.new()

comp.set_input(&input)
comp.set_output(&output)

// Compress at level 2 (normal)
comp.start_block(2)
comp.start_segment('file.txt', 'comment')
for comp.compress(1024) {}
comp.end_segment()
comp.end_block()

// Get compressed data
compressed := output.bytes()
```

### Basic Decompression

```v
import zpaq

// Create decompressor
mut decomp := zpaq.Decompresser.new()

// Set up input and output
mut input := zpaq.FileReader.new(compressed_data)
mut output := zpaq.FileWriter.new()

decomp.set_input(&input)
decomp.set_output(&output)

// Find and decompress
if decomp.find_block() {
    for decomp.find_filename() {
        filename := decomp.get_filename()
        for decomp.decompress(1024) {}
        decomp.read_segment_end()
    }
}

// Get decompressed data
decompressed := output.bytes()
```

### SHA1/SHA256 Hashing

```v
import zpaq

// SHA1
mut sha1 := zpaq.SHA1.new()
sha1.write_bytes('Hello, World!'.bytes())
hash := sha1.result() // 20 bytes

// SHA256
mut sha256 := zpaq.SHA256.new()
sha256.write_bytes('Hello, World!'.bytes())
hash256 := sha256.result() // 32 bytes
```

### Using StringBuffer

```v
import zpaq

mut buf := zpaq.StringBuffer.new()

// Write data
buf.put(0x41) // 'A'
buf.write([u8(0x42), 0x43]) // 'BC'

// Read data
c := buf.get() // 0x41
buf.reset_read()
```

## Module Structure

- `src/types.v` - Type definitions and constants
- `src/io.v` - I/O interfaces (Reader, Writer, FileReader, FileWriter, StringBuffer)
- `src/sha1.v` - SHA1 and SHA256 hash implementations
- `src/array.v` - Generic dynamic array with modulo addressing
- `src/statetable.v` - State table for bit history (libzpaq data)
- `src/zpaql.v` - ZPAQL Virtual Machine
- `src/predictor.v` - Context mixing predictor (all 9 component types)
- `src/encoder.v` - Arithmetic encoder (libzpaq compatible)
- `src/decoder.v` - Arithmetic decoder (libzpaq compatible)
- `src/compressor.v` - High-level compression API
- `src/decompressor.v` - High-level decompression API
- `src/levels.v` - Predefined compression levels (0-5)
- `src/zpaq_test.v` - Unit tests

## Compression Levels

| Level | Name   | Description |
|-------|--------|-------------|
| 0     | Store  | No compression, just store |
| 1     | Fast   | Order-1 context model, fastest |
| 2     | Normal | ICM + ISSE chain |
| 3     | High   | More components, larger tables |
| 4-5   | Max    | Full model with all component types |

## API Reference

### Types

- `CompType` - Enum for component types (none, cons, cm, icm, match_, avg, mix2, mix, isse, sse)

### Functions

- `oplen(op u8) int` - Get instruction length for ZPAQL opcode
- `iserr(op u8) bool` - Check if opcode is an error instruction
- `to_u16(p []u8) int` - Convert 2 bytes to u16 (little-endian)
- `to_u32(p []u8) u32` - Convert 4 bytes to u32 (little-endian)
- `squash(d int) int` - Convert log odds to probability (0..4095)
- `stretch(p int) int` - Convert probability to log odds

### Interfaces

- `Reader` - Input stream interface with `get()` and `read()`
- `Writer` - Output stream interface with `put()` and `write()`

### Structs

- `FileReader` - Read from byte buffer
- `FileWriter` - Write to byte buffer
- `StringBuffer` - Read/write buffer implementing both Reader and Writer
- `Array[T]` - Generic dynamic array with modulo addressing
- `SHA1`, `SHA256` - Hash implementations
- `StateTable` - Bit history state machine
- `ZPAQL` - ZPAQL virtual machine
- `Predictor` - Context mixing predictor
- `Encoder` - Arithmetic encoder
- `Decoder` - Arithmetic decoder
- `Compressor` - High-level compression
- `Decompresser` - High-level decompression

## Building

```bash
# Run tests
v test src/

# Build shared library
v -shared src/

# Format code
v fmt -w src/

# Lint code
v vet src/
```

## References

- [Original C++ source (zpaq)](https://github.com/zpaq/zpaq)
- [ZPAQ specification](http://mattmahoney.net/dc/zpaq.html)
- [Matt Mahoney's Data Compression Page](http://mattmahoney.net/dc/)

## License

Public Domain - This is a port of Matt Mahoney's public domain libzpaq library.
