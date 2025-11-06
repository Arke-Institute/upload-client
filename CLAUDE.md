# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Arke Upload Server is a REST API server for uploading files and directories to the Arke Institute's ingest service. It provides a web-accessible upload gateway that accepts HTTP uploads, preprocesses files (TIFF→JPEG conversion), and transfers them to Cloudflare R2 using presigned URLs. The worker coordinates state but never handles file bytes directly.

**Key Architecture:**
- Express.js REST API server
- Session-based upload management
- Direct R2 upload via presigned URLs
- TIFF preprocessing with Sharp
- Shared upload library (Uploader, Scanner, WorkerClient)

## Development Commands

### Build and Run
```bash
# Build TypeScript to JavaScript
npm run build

# Run in development mode (with tsx, hot reload)
npm run dev

# Run production build
npm start

# Type checking only (no compilation)
npm run type-check
```

### Testing
```bash
# Run tests with Vitest
npm test

# Test upload with script
./test-upload.sh example_dirs/iiif_test_small

# Test with local worker
export WORKER_URL=http://localhost:8787
npm run dev
```

### Docker
```bash
# Build image
docker build -t arke-upload-server .

# Run container
docker run -d -p 3000:3000 \
  -e WORKER_URL=https://ingest.arke.institute \
  -v /data/uploads:/tmp/arke-uploads \
  arke-upload-server

# Run with docker-compose
docker-compose up -d
```

### Deployment
```bash
# Deploy to EC2 (see deployment/README.md)
cd deployment/scripts
./01-create-ec2.sh
./02-deploy-server.sh

# Check status
./check-status.sh
```

## Architecture

### System Components

```
Client (Browser/Script)
    ↓ HTTP multipart upload
Express Server
    ↓ Temp storage
TIFF Preprocessor (Sharp)
    ↓ Scanning & CID computation
Uploader Library
    ↓ Presigned URLs
R2 Storage ← Worker API
```

### Core Upload Flow

**Server-side workflow** (orchestrated by `src/server/routes/upload.ts`):

1. **Initialize** - Client calls `POST /api/v1/upload/init`, server creates session
2. **Upload** - Client sends files via `POST /api/v1/upload/:id/files`, stored in temp dir
3. **Process** - Client triggers `POST /api/v1/upload/:id/process`
   - Scanner scans uploaded files, computes CIDs
   - Preprocessor converts TIFFs to JPEG
   - Uploader uploads files to R2 via presigned URLs
   - Finalizes batch with worker API
4. **Monitor** - Client polls `GET /api/v1/upload/:id/status` for progress
5. **Cleanup** - Server deletes temp files 5 minutes after completion

### Key Components

**Express Server** (src/server/index.ts)
- Entry point for REST API
- Mounts upload and health routes
- Graceful shutdown with session cleanup
- Error handling middleware

**SessionManager** (src/server/services/upload-session.ts:24-206)
- In-memory session storage (TODO: Redis for multi-server)
- 24-hour session TTL with auto-cleanup
- Manages upload directories in `/tmp/arke-uploads/{sessionId}`
- Tracks status, progress, errors per session

**Upload Routes** (src/server/routes/upload.ts)
- POST `/api/v1/upload/init` - Create session
- POST `/api/v1/upload/:id/files` - Upload files (Multer)
- POST `/api/v1/upload/:id/process` - Trigger processing
- GET `/api/v1/upload/:id/status` - Get progress
- DELETE `/api/v1/upload/:id` - Cancel upload

**Uploader** (src/lib/uploader.ts:29-293)
- Main orchestrator coordinating upload workflow
- Manages worker pool for parallel file uploads
- Integrates Scanner, Preprocessor, WorkerClient
- Handles both simple and multipart uploads based on file size
- Progress callbacks for real-time status updates

**Scanner** (src/lib/scanner.ts:34-216)
- Recursively walks directory tree
- Validates extensions, paths, and file sizes
- Computes CID (Content Identifier) using multiformats library
- Returns FileInfo[] sorted by size (smallest first)

**PreprocessorOrchestrator** (src/lib/preprocessor.ts:11-150)
- Coordinates preprocessing operations
- Registers preprocessors (TIFF converter, etc.)
- Runs applicable preprocessors in sequence
- Supports dry-run mode

**TiffConverter** (src/lib/preprocessors/tiff-converter.ts)
- Converts TIFF files to JPEG using Sharp
- Configurable quality (default: 95%)
- Modes: convert, preserve, both, none
- Reduces file size significantly (95% typical)

**WorkerClient** (src/lib/worker-client.ts:27-209)
- HTTP API client for communicating with ingest worker
- Endpoints: `/api/batches/init`, `/api/batches/{id}/files/start`, `/api/batches/{id}/files/complete`, `/api/batches/{id}/finalize`
- Automatic retry with exponential backoff for all requests
- See API.md for complete endpoint documentation

**Simple Upload** (src/lib/simple.ts:26-81)
- For files < 5 MB
- Single PUT request to presigned URL
- Entire file loaded into memory

**Multipart Upload** (src/lib/multipart.ts:39-228)
- For files ≥ 5 MB
- Splits file into 10 MB parts
- Uploads parts concurrently (default: 3 parallel)
- Returns PartInfo[] with ETags for R2 multipart completion
- Uses file handles to avoid loading entire file into memory

### Direct R2 Upload Pattern

Neither the server nor worker handles file bytes. Instead:
1. Server triggers Uploader with local directory path
2. Uploader requests presigned URL(s) from worker
3. Worker generates URL(s) using R2 bucket API
4. Uploader uploads directly to R2 using presigned URL(s)
5. Uploader notifies worker of completion

This pattern keeps the worker stateless and enables efficient uploads even with Cloudflare Workers' memory limits.

### Session Management

**Storage:** In-memory Map (src/server/services/upload-session.ts:25)
- Session ID: ULID format (e.g., `01K9BEZ521NSBNCRZ0SFYXCF24`)
- Temp directory: `/tmp/arke-uploads/{sessionId}` (or `UPLOAD_DIR` env var)
- TTL: 24 hours with auto-cleanup timer
- States: `initialized` → `receiving` → `ready` → `processing` → `completed`/`failed`

**Lifecycle:**
1. Created on `/init` endpoint
2. Files accumulated via `/files` endpoint (Multer storage)
3. Processing triggered via `/process` endpoint
4. Temp files deleted 5 minutes after completion
5. Session removed from memory on expiration or cleanup

**Production TODO:** Replace Map with Redis for multi-server deployments

### Configuration System

**Environment Variables:**
- `PORT` - Server port (default: 3000)
- `WORKER_URL` - Worker API URL (default: https://ingest.arke.institute)
- `UPLOAD_DIR` - Temp upload directory (default: /tmp/arke-uploads)
- `NODE_ENV` - Environment (development/production)
- `DEBUG` - Enable debug logging (true/false)

**Upload Configuration:**
Session-specific config built from init request (src/server/services/upload-session.ts:47-61):
- `uploader` (required): Name of person uploading
- `rootPath`: Archive path prefix (default: `/`)
- `parentPi`: Parent persistent identifier (default: root)
- `metadata`: Custom metadata object
- `processing`: OCR, IIIF options
- `preprocessor`: TIFF conversion settings
- `parallelUploads`: File-level concurrency (default: 5)
- `parallelParts`: Part-level concurrency (default: 3)

### Error Handling

Custom error types (src/utils/errors.ts):
- `ValidationError` - Invalid input (paths, extensions, sizes)
- `ScanError` - Directory scanning issues
- `WorkerAPIError` - API errors from worker (includes status code)
- `NetworkError` - Network/connection failures
- `UploadError` - R2 upload failures

All network operations use retry logic (src/utils/retry.ts) with exponential backoff (default: 3 retries).

## Important Implementation Details

### File Upload with Directory Structure

Multer storage (src/server/routes/upload.ts:23-50):
- Extracts directory path from `filename` parameter in multipart form
- Creates nested directories in temp storage
- Preserves relative path for archive structure
- Example: `files=@doc.pdf;filename=box_1/folder_a/doc.pdf`

### Progress Tracking

Two mechanisms:
1. **Uploader progress callbacks** (src/lib/uploader.ts:18-27)
   - Passed to Uploader constructor
   - Reports: phase, file counts, bytes uploaded, current file
   - Used by server to update session progress

2. **Session progress object** (src/types/server.ts)
   - Stored in session, returned by `/status` endpoint
   - Includes: percentComplete, filesTotal, filesUploaded, currentFile

### TIFF Preprocessing

**Sharp library** used for conversion:
- Input: TIFF files from temp directory
- Output: JPEG files (quality configurable, default 95%)
- Modes:
  - `convert` - Replace TIFF with JPEG in file list
  - `preserve` - Keep only TIFF
  - `both` - Upload both TIFF and JPEG
  - `none` - Skip TIFF processing

**Benefits:**
- 95% file size reduction typical
- Faster OCR processing
- Better web compatibility
- Original quality preserved at 95% JPEG

### CID Computation

Files are hashed using SHA-256 and encoded as CIDv1 with multiformats library (src/utils/hash.ts). The CID is computed during scanning and sent to the worker for content-addressable storage tracking.

### Concurrency Control

Two levels of concurrency:
1. **File-level**: `parallelUploads` (default: 5) - How many files upload simultaneously
2. **Part-level**: `parallelParts` (default: 3) - How many parts per multipart upload

Both use worker pool pattern with shared queue.

### Logical vs Physical Paths

- **Local path**: Physical filesystem path (e.g., `/tmp/arke-uploads/01ABC/box_1/doc.pdf`)
- **Logical path**: Virtual archive path (e.g., `/archives/collection/box_1/doc.pdf`)

The `rootPath` option sets the logical root, and relative paths are preserved. This allows maintaining archive structure independent of local filesystem layout.

## API Integration

### Worker API

The worker API expects specific request/response formats. Key points:

- **Batch ID**: ULID format (e.g., `01K8ABCDEFGHIJKLMNOPQRSTUV`)
- **R2 Keys**: Format is `staging/{batch_id}/{logical_path}`
- **ETags**: Must be cleaned (quotes removed) before sending to complete endpoint
- **Part Numbers**: 1-indexed (not 0-indexed)

See API.md for complete endpoint documentation and payload formats.

### Server API

See API.md for complete REST API documentation including:
- Request/response formats
- Error codes
- Complete workflow examples
- Client integration patterns (JavaScript, Python, Bash)

## Code Style and Patterns

### TypeScript Configuration

- Target: ES2022
- Module: ES2022 (native ESM)
- Strict mode enabled
- All imports must use `.js` extension (ESM requirement)

### Logging

Use the logger from `src/utils/logger.ts` instead of `console.log`:
```typescript
import { getLogger } from '../utils/logger.js';
const logger = getLogger();

logger.debug('Details only shown with --debug');
logger.info('Important operational info');
logger.warn('Non-fatal issues');
logger.error('Fatal errors');
```

User-facing output uses `chalk` and `ora` for colored/styled terminal output.

### Async Patterns

All I/O operations are async. Use worker pools (see uploadFiles and uploadPartsWithConcurrency) for controlled concurrency rather than Promise.all() on large arrays.

### Error Propagation

Throw custom error types from utilities and handle them at route/handler level. Return JSON error responses to clients, detailed traces only with `--debug`.

## Common Workflows

### Adding a New Preprocessing Step

1. Create preprocessor class implementing `Preprocessor` interface (src/types/preprocessor.ts)
2. Implement `shouldRun()`, `process()`, `cleanup()` methods
3. Register in `src/lib/preprocessor.ts` or upload route handler
4. Add configuration options to `PreprocessorConfig` type
5. Test with dry-run mode

### Adding a New API Endpoint

1. Add route handler in `src/server/routes/upload.ts` (or new route file)
2. Add request/response types to `src/types/server.ts`
3. Update session state if needed in SessionManager
4. Add endpoint to root endpoint listing (src/server/index.ts:50-67)
5. Document in API.md

### Adding a New Session Status

1. Add status to `SessionStatus` type (src/types/server.ts)
2. Update state transitions in route handlers
3. Update status polling logic if needed
4. Document status in API.md

### Debugging Upload Failures

1. Check health endpoint: `curl http://localhost:3000/api/v1/health`
2. View server logs in console or `journalctl -u arke-upload -f` (production)
3. Check session status endpoint for errors
4. Verify worker is accessible from server
5. Check temp directory disk space
6. Enable DEBUG=true for detailed logs

### Testing Locally

```bash
# Start local server
npm run dev

# Initialize session
INIT=$(curl -s -X POST http://localhost:3000/api/v1/upload/init \
  -H "Content-Type: application/json" \
  -d '{"uploader": "Test User"}')

SESSION_ID=$(echo "$INIT" | jq -r .sessionId)
UPLOAD_URL=$(echo "$INIT" | jq -r .uploadUrl)

# Upload files
curl -X POST "$UPLOAD_URL" \
  -F "files=@test.pdf" \
  -F "files=@folder/doc.txt;filename=folder/doc.txt"

# Process
curl -X POST "http://localhost:3000/api/v1/upload/$SESSION_ID/process" \
  -H "Content-Type: application/json" \
  -d '{"dryRun": false}'

# Check status
curl "http://localhost:3000/api/v1/upload/$SESSION_ID/status" | jq .
```

## Dependencies

**Core:**
- `express` - Web server framework
- `multer` - File upload handling
- `axios` - HTTP client for API and R2 uploads
- `multiformats` - CID computation
- `sharp` - TIFF to JPEG conversion
- `ulid` - Session ID generation

**UI:**
- `chalk` - Terminal colors
- `ora` - Spinners
- `cli-progress` - Progress bars

**Utilities:**
- `mime-types` - Content-Type detection
- `dotenv` - Environment variable loading
- `tsx` - Development TypeScript execution

## Repository Structure

```
cli/
├── src/
│   ├── server/
│   │   ├── index.ts                 # Express app entry point
│   │   ├── routes/
│   │   │   ├── health.ts            # Health check endpoint
│   │   │   └── upload.ts            # Upload API routes
│   │   └── services/
│   │       └── upload-session.ts    # Session management
│   ├── lib/
│   │   ├── uploader.ts              # Main upload orchestrator
│   │   ├── scanner.ts               # Directory scanning
│   │   ├── preprocessor.ts          # Preprocessor orchestrator
│   │   ├── preprocessors/
│   │   │   ├── index.ts             # Preprocessor exports
│   │   │   └── tiff-converter.ts    # TIFF→JPEG converter
│   │   ├── worker-client.ts         # Worker API client
│   │   ├── simple.ts                # Simple uploads (<5MB)
│   │   ├── multipart.ts             # Multipart uploads (≥5MB)
│   │   ├── progress.ts              # Progress tracking
│   │   ├── config.ts                # Configuration loading
│   │   └── validation.ts            # Input validation
│   ├── types/
│   │   ├── api.ts                   # Worker API types
│   │   ├── batch.ts                 # Batch config types
│   │   ├── file.ts                  # File metadata types
│   │   ├── server.ts                # Server API types
│   │   ├── preprocessor.ts          # Preprocessor types
│   │   └── processing.ts            # Processing options
│   └── utils/
│       ├── errors.ts                # Custom error types
│       ├── logger.ts                # Logging utilities
│       ├── retry.ts                 # Retry logic
│       └── hash.ts                  # CID computation
├── deployment/                      # EC2 deployment scripts
│   ├── README.md                    # Deployment guide
│   └── scripts/
│       ├── 01-create-ec2.sh         # Create instance
│       ├── 02-deploy-server.sh      # Deploy application
│       ├── check-status.sh          # Check health
│       └── 99-cleanup.sh            # Destroy resources
├── example_dirs/                    # Test upload directories
├── dist/                            # Build output (generated)
├── API.md                           # Server API documentation
├── Dockerfile                       # Container image
├── docker-compose.yml               # Local Docker setup
└── test-upload.sh                   # Upload test script
```

## Production Deployment

See `deployment/README.md` for complete deployment guide.

**Quick deploy:**
```bash
cd deployment/scripts
./01-create-ec2.sh           # Create EC2 instance
./02-deploy-server.sh        # Deploy application
./check-status.sh            # Verify deployment
```

**Production setup:**
- AWS EC2 t3.small (2 vCPU, 2 GB RAM)
- Docker with systemd auto-restart
- Nginx reverse proxy (port 80 → 3000)
- 30 GB storage for temp uploads
- Cost: ~$26/month

**Monitoring:**
```bash
# Health check
curl http://upload.arke.institute/api/v1/health

# Server logs
ssh -i key.pem ec2-user@IP 'sudo journalctl -u arke-upload -f'

# Docker logs
sudo docker logs arke-upload -f
```
