# Arke Upload CLI

Command-line tool for uploading files to the Arke Institute's ingest service.

## Features

- 📁 **Recursive directory scanning** - Upload entire directory structures
- 🚀 **Parallel uploads** - Multiple files uploaded concurrently
- 📦 **Multipart support** - Handles large files (up to 5 GB) with resumable uploads
- 🖼️ **TIFF preprocessing** - Automatic TIFF to JPEG conversion for OCR compatibility
- 📊 **Progress tracking** - Real-time progress bars and statistics
- 🔄 **Automatic retry** - Network errors handled with exponential backoff
- ✅ **File validation** - Validates file types, sizes, and paths
- 🏃 **Dry-run mode** - Preview uploads without sending data

## Installation

### Install from GitHub (Recommended)

```bash
# Install globally from GitHub
npm install -g github:Arke-Institute/cli

# Verify installation
arke-upload --version
```

### Install from Source

```bash
# Clone the repository
git clone https://github.com/Arke-Institute/cli.git
cd cli

# Install dependencies and build
npm install
npm run build

# Link globally
npm link
```

## Usage

### Quick Start (Minimal)

Worker URL defaults to `https://ingest.arke.institute`, so you only need to specify the uploader:

```bash
arke-upload upload ./my-files --uploader "Jane Doe"
```

### With Config File (Recommended)

Create `.arke-upload.json` in your project:

```json
{
  "uploader": "Jane Doe",
  "rootPath": "/series_1/box_7"
}
```

Then simply run:

```bash
arke-upload upload ./my-files
```

See [CONFIG.md](CONFIG.md) for full configuration options.

### Basic Upload

```bash
arke-upload upload <directory> \
  --uploader "Jane Doe" \
  --root-path "/series_1/box_7"
```

### With Metadata

```bash
arke-upload upload ./my-files \
  --uploader "Jane Doe" \
  --root-path "/collection/series_1" \
  --metadata '{"collection":"historical_records","year":"1923"}'
```

### TIFF Preprocessing

```bash
arke-upload upload ./my-files \
  --uploader "Jane Doe" \
  --convert-tiff convert \
  --tiff-quality 95
```

### Dry Run (Preview)

```bash
arke-upload upload ./my-files \
  --uploader "Test User" \
  --dry-run
```

### With Debug Logging

```bash
arke-upload upload ./my-files \
  --uploader "Jane Doe" \
  --debug \
  --log-file upload.log
```

## Command Options

### Required Options

- `<directory>` - Directory to upload
- `--uploader <name>` - Name of person uploading (or set in config file / `ARKE_UPLOADER` env var)

### Optional Options

- `--worker-url <url>` - Worker API URL (default: `https://ingest.arke.institute`)
- `--root-path <path>` - Logical root path (default: `/`)
- `--parent-pi <pi>` - Parent PI to attach collection to (default: origin block)
- `--metadata <json>` - Batch metadata as JSON string
- `--parallel <n>` - Number of concurrent file uploads (default: `5`)
- `--parallel-parts <n>` - Concurrent parts per multipart upload (default: `3`)
- `--convert-tiff <mode>` - TIFF conversion mode: `convert`, `preserve`, `both`, or `none` (default: `convert`)
- `--tiff-quality <n>` - JPEG quality for TIFF conversion, 1-100 (default: `95`)
- `--preprocess-dir <path>` - Directory for preprocessed files (default: temp directory)
- `--dry-run` - Scan files but don't upload
- `--resume` - Resume interrupted upload (future feature)
- `--debug` - Enable debug logging
- `--log-file <path>` - Write logs to file

### Configuration Priority

Settings are loaded in this order (highest to lowest priority):
1. **CLI arguments** (e.g., `--uploader "Jane"`)
2. **Environment variables** (e.g., `ARKE_UPLOADER="Jane"`)
3. **Config file** (`.arke-upload.json`)
4. **Defaults**

See [CONFIG.md](CONFIG.md) for details.

## File Type Support

The CLI accepts **all file types** without restrictions. There are no extension whitelists or filtering - you can upload any file format.

**Processing Behavior:**

- **Text files** (`.txt`, `.md`, `.json`, `.csv`, `.xml`, etc.) are stored directly in IPFS as content
- **Binary files** (images, PDFs, videos, etc.) are stored in R2 and referenced via `.ref.json` files
- **Manual refs** can be uploaded as `.ref.json` files to reference external resources

**Special Handling:**

- **TIFF images** can be automatically converted to JPEG for OCR compatibility (see TIFF Preprocessing section below)
- **Ref files** (`.ref.json`) must include a `url` field pointing to the external resource

See [FILE_PROCESSING_GUIDE.md](FILE_PROCESSING_GUIDE.md) for detailed information on how different file types are processed.

## Size Limits

- **Maximum file size:** 5 GB
- **Maximum batch size:** 100 GB
- **Multipart threshold:** Files ≥ 5 MB use multipart upload

## TIFF Preprocessing

The CLI includes automatic TIFF to JPEG conversion to enable OCR processing on archival TIFF files. This feature provides significant file size reduction (90-95%) while maintaining high visual quality.

### Conversion Modes

Use `--convert-tiff <mode>` to control conversion behavior:

#### `convert` (default)
Convert TIFFs to JPEG, upload JPEG only.

- **Benefits:** 90-95% file size reduction, enables OCR processing
- **Quality:** High quality preservation (95% JPEG quality by default)
- **Use case:** When OCR is needed and original TIFF not required in archive
- **Result:** Only JPEG uploaded, original TIFF not stored

```bash
arke-upload upload ./tiff-files --uploader "User" --convert-tiff convert
```

#### `preserve`
Keep original TIFFs only, no conversion.

- **Benefits:** Original archival quality maintained
- **Drawback:** No OCR processing available, larger file sizes
- **Use case:** When archival TIFF quality is required and OCR not needed
- **Result:** Only TIFF uploaded, no JPEG created

```bash
arke-upload upload ./tiff-files --uploader "User" --convert-tiff preserve
```

#### `both`
Upload both TIFF and JPEG versions.

- **Benefits:** Archival TIFF preserved, OCR-enabled JPEG also available
- **Drawback:** Doubles storage usage
- **Use case:** When both archival quality and OCR are required
- **Result:** Both TIFF and JPEG uploaded to archive

```bash
arke-upload upload ./tiff-files --uploader "User" --convert-tiff both
```

#### `none`
Skip TIFF files entirely.

- **Use case:** Validation, dry-run testing, or when TIFF files should be excluded
- **Result:** TIFF files not processed or uploaded

```bash
arke-upload upload ./mixed-files --uploader "User" --convert-tiff none
```

### Quality Control

Use `--tiff-quality <n>` to adjust JPEG quality (1-100):

```bash
# Maximum quality (larger files)
arke-upload upload ./files --uploader "User" --tiff-quality 100

# Balanced quality/size (default)
arke-upload upload ./files --uploader "User" --tiff-quality 95

# Smaller files (lower quality)
arke-upload upload ./files --uploader "User" --tiff-quality 85
```

### Configuration

**Via Environment Variables:**
```bash
export ARKE_TIFF_MODE=convert
export ARKE_TIFF_QUALITY=95
```

**Via Config File (`.arke-upload.json`):**
```json
{
  "uploader": "Your Name",
  "preprocessor": {
    "tiff": {
      "mode": "convert",
      "quality": 95,
      "outputDir": "/tmp/preprocessed"
    }
  }
}
```

### Technical Details

- **Library:** Uses Sharp for high-performance image conversion
- **Cleanup:** Automatic cleanup of temporary files
- **Error handling:** Graceful handling of corrupted TIFF files
- **Progress:** Real-time progress tracking during preprocessing
- **Memory:** Efficient streaming processing for large files

## Architecture

### Upload Flow

1. **Scan** - Recursively scan directory for valid files
2. **Preprocess** - Convert TIFF files to JPEG (if enabled)
3. **Initialize** - Create batch with worker API
4. **Upload** - For each file:
   - Request presigned URLs from worker
   - Upload directly to R2 (simple or multipart)
   - Notify worker of completion
5. **Finalize** - Mark batch complete and enqueue for processing

### Direct R2 Upload

Files are uploaded directly to Cloudflare R2 using presigned URLs. The worker never handles file bytes, making the system highly scalable.

```
Client → Worker (get URLs) → Client uploads → R2
                               ↓
                          Worker (track state)
```

## Development

### Build

```bash
npm run build
```

### Run in Development

```bash
npm run dev upload ./example_dirs/iiif_test_small \
  --worker-url http://localhost:8787 \
  --uploader "Dev User" \
  --debug
```

### Test with Example Data

Example commands for testing various features:

```bash
# Test basic upload
npm run dev upload ./example_dirs/sample_archive_deep \
  --worker-url http://localhost:8787 \
  --uploader "Test User" \
  --root-path "/archive_test"

# Test TIFF preprocessing (convert mode)
npm run dev upload ./tiff-files \
  --worker-url http://localhost:8787 \
  --uploader "Test User" \
  --convert-tiff convert \
  --tiff-quality 95 \
  --debug

# Test with parent PI (attach to specific archive location)
npm run dev upload ./files \
  --worker-url http://localhost:8787 \
  --uploader "Test User" \
  --parent-pi "01K8ABCDEFGHIJKLMNOPQRSTUV" \
  --root-path "/new_collection"

# Test with processing configuration
npm run dev upload ./files \
  --worker-url http://localhost:8787 \
  --uploader "Test User" \
  --debug
```

## Error Handling

The CLI includes comprehensive error handling:

- **Network errors** - Automatic retry with exponential backoff
- **Validation errors** - Clear messages for invalid input
- **Upload failures** - Per-file error tracking with summary
- **Worker errors** - API errors displayed with details

## Progress Display

The CLI shows real-time progress during uploads:

```
████████████████░░░░ | 80% | 15/20 files | 3.2 GB/4.0 GB | Speed: 12.5 MB/s | ETA: 1m

→ page_042.tiff
✓ page_001.tiff
✓ page_002.tiff
✗ page_003.tiff: Upload failed

Upload Summary:
✓ Completed: 18 files
✗ Failed: 2 files
Total uploaded: 3.6 GB
Average speed: 11.2 MB/s
Total time: 5m 32s
```

## Troubleshooting

### "Directory not found"

Ensure the directory path is correct. Use absolute paths or relative to current working directory.

### "Invalid worker URL"

The worker URL must be a valid HTTP/HTTPS URL. For local development, use `http://localhost:8787`.

### "File size exceeds maximum"

Individual files cannot exceed 5 GB. The total batch cannot exceed 100 GB.

### "Invalid ref file"

`.ref.json` files must include a `url` field. Check the file format and ensure it's valid JSON with the required fields.

### "Network error"

Check your internet connection and ensure the worker URL is accessible. The CLI will automatically retry network errors.

## License

MIT

## Support

For issues or questions, please open an issue on GitHub.
