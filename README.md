<mark> NOTE: You probably shouldn't use this - it's fully written by copilot done as a test, don't expect anything to work. </mark>

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
- **Command-line interface** compatible with original zpaq

## Command-Line Interface

### Building

```bash
v cmd/main.v -o zpaq-cli
```

### Usage

```
zpaq-cli command archive[.zpaq] files... -options...
```

Files... may be directory trees. Default is the whole archive.

### Commands

| Command | Description |
|---------|-------------|
| `a`, `add` | Append files to archive if dates have changed |
| `x`, `extract` | Extract most recent versions of files |
| `l`, `list` | List or compare external files to archive by dates |

### Options

| Option | Description |
|--------|-------------|
| `-all N` | Extract/list versions in N digit directories |
| `-f`, `-force` | Add: append if contents changed. Extract: overwrite. List: compare contents |
| `-index F` | Extract: create index F. Add: create suffix indexed by F |
| `-key X` | Create or access encrypted archive with password X |
| `-mN`, `-method N` | Compress level N (0..5 = faster..better, default 1) |
| `-noattributes` | Ignore/don't save file attributes or permissions |
| `-not files...` | Exclude files matching pattern. `*` and `?` wildcards supported |
| `-only files...` | Include only files matching pattern (default: `*`) |
| `-repack F` | Extract to new archive F |
| `-sN`, `-summary N` | List: show top N by size. Add/Extract: show brief progress if N > 0 |
| `-test` | Extract: verify but do not write files |
| `-tN`, `-threads N` | Use N threads (default: 0 = auto) |
| `-to out...` | Rename files... to out... or all to out/all |
| `-until N` | Roll back archive to N'th update or -N from end |
| `-fragment N` | Use 2^N KiB average fragment size (default: 6) |

### Examples

```bash
# Add files to archive
zpaq-cli add backup.zpaq file1.txt file2.txt

# Add with compression level 0 (store)
zpaq-cli add backup.zpaq data/ -m0

# Add with compression level 1 (fast) and progress
zpaq-cli add backup.zpaq data/ -m1 -s1

# List archive contents
zpaq-cli list backup.zpaq

# Extract all files
zpaq-cli extract backup.zpaq

# Extract to specific directory
zpaq-cli extract backup.zpaq -to output/

# Extract and overwrite existing files
zpaq-cli extract backup.zpaq -force

# Test archive (verify without extracting)
zpaq-cli extract backup.zpaq -test

# Extract only .txt files
zpaq-cli extract backup.zpaq -only "*.txt"

# Extract excluding .log files
zpaq-cli extract backup.zpaq -not "*.log"
```

## Library Usage

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

- `cmd/main.v` - Command-line interface
- `zpaq/types.v` - Type definitions and constants
- `zpaq/io.v` - I/O interfaces (Reader, Writer, FileReader, FileWriter, StringBuffer)
- `zpaq/sha1.v` - SHA1 and SHA256 hash implementations
- `zpaq/array.v` - Generic dynamic array with modulo addressing
- `zpaq/statetable.v` - State table for bit history (libzpaq data)
- `zpaq/zpaql.v` - ZPAQL Virtual Machine
- `zpaq/predictor.v` - Context mixing predictor (all 9 component types)
- `zpaq/encoder.v` - Arithmetic encoder (libzpaq compatible)
- `zpaq/decoder.v` - Arithmetic decoder (libzpaq compatible)
- `zpaq/compressor.v` - High-level compression API
- `zpaq/decompressor.v` - High-level decompression API
- `zpaq/levels.v` - Predefined compression levels (0-5)
- `zpaq/zpaq_test.v` - Unit tests

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

## References

- [Original C++ source (zpaq)](https://github.com/zpaq/zpaq)
- [ZPAQ specification](http://mattmahoney.net/dc/zpaq.html)
- [Matt Mahoney's Data Compression Page](http://mattmahoney.net/dc/)

## License

Public Domain - This is a port of Matt Mahoney's public domain libzpaq library.
