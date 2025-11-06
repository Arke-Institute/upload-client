# Repository Restructure Plan: CLI → SDK

## Goal

Transform this repository from a CLI/Server tool into `@arke/upload-client` - a portable SDK for uploading files to Arke.

## Current State Analysis

### Keep (SDK-relevant code)
- ✅ `src/lib/scanner.ts` - File scanning (needs refactor for multi-platform)
- ✅ `src/lib/worker-client.ts` - Worker API client (needs updates)
- ✅ `src/lib/simple.ts` - Simple R2 upload
- ✅ `src/lib/multipart.ts` - Multipart R2 upload
- ✅ `src/types/` - Type definitions (need cleanup)
- ✅ `src/utils/errors.ts` - Error types
- ✅ `src/utils/logger.ts` - Logger (needs simplification)
- ✅ `src/utils/retry.ts` - Retry logic
- ✅ `src/utils/hash.ts` - CID computation
- ✅ `example_dirs/` - Test data

### Remove (Server/CLI-specific)
- ❌ `src/server/` - Express server (not needed)
- ❌ `src/lib/config.ts` - CLI config (not needed)
- ❌ `src/lib/preprocessor.ts` - Server-side preprocessing (Cloud Run does this)
- ❌ `src/lib/preprocessors/` - TIFF converter (Cloud Run does this)
- ❌ `src/lib/uploader.ts` - CLI orchestrator (will rewrite as SDK)
- ❌ `src/lib/progress.ts` - CLI progress bars (will simplify)
- ❌ `deployment/` - EC2 deployment (not needed)
- ❌ `dist/` - Old build artifacts
- ❌ `Dockerfile` - Server docker (not needed)
- ❌ `test-upload.sh` - Old CLI test script
- ❌ `.arke-upload.json` - CLI config file

### Update/Rewrite
- 🔄 `package.json` - Change to SDK package
- 🔄 `README.md` - SDK documentation
- 🔄 `tsconfig.json` - Multi-target builds
- 🔄 Architecture docs (consolidate into one)

## New Structure

```
@arke/upload-client/
├── src/
│   ├── index.ts                    # Main export
│   ├── uploader.ts                 # ArkeUploader class (NEW)
│   ├── worker-client.ts            # Worker API client (REFACTOR)
│   ├── r2-upload.ts                # R2 upload logic (MERGE simple + multipart)
│   ├── scanner.ts                  # File scanning (REFACTOR for multi-platform)
│   ├── types/
│   │   ├── index.ts                # Main types export
│   │   ├── config.ts               # SDK configuration types
│   │   ├── worker.ts               # Worker API types
│   │   ├── progress.ts             # Progress event types
│   │   └── file.ts                 # File metadata types
│   ├── utils/
│   │   ├── cid.ts                  # CID computation (KEEP)
│   │   ├── retry.ts                # Retry logic (KEEP)
│   │   ├── errors.ts               # Error types (KEEP)
│   │   ├── platform.ts             # Platform detection (NEW)
│   │   └── logger.ts               # Simple logger (SIMPLIFY)
│   └── platforms/
│       ├── browser.ts              # Browser-specific file handling (NEW)
│       ├── node.ts                 # Node.js-specific file handling (NEW)
│       └── common.ts               # Shared platform code (NEW)
├── examples/
│   ├── browser.html                # Browser example (NEW)
│   ├── node-basic.ts               # Node.js basic example (NEW)
│   ├── node-advanced.ts            # Node.js advanced example (NEW)
│   └── react-app.tsx               # React example (NEW)
├── test/
│   ├── uploader.test.ts            # Main tests (NEW)
│   ├── worker-client.test.ts       # API client tests (NEW)
│   ├── scanner.test.ts             # Scanner tests (NEW)
│   └── fixtures/                   # Test data (MOVE from example_dirs)
│       ├── small/                  # Small test set
│       ├── tiffs/                  # TIFF test files
│       └── pdfs/                   # PDF test files
├── dist/                           # Build output (generated)
│   ├── index.js                    # Node.js (CJS)
│   ├── index.mjs                   # Node.js (ESM)
│   ├── browser.js                  # Browser (UMD)
│   └── types/                      # TypeScript definitions
├── docs/
│   ├── README.md                   # Main documentation
│   ├── API.md                      # API reference
│   ├── PLATFORMS.md                # Platform compatibility
│   └── MIGRATION.md                # Migration from old CLI
├── package.json                    # NPM package config
├── tsconfig.json                   # TypeScript config
├── tsconfig.browser.json           # Browser build config
├── vitest.config.ts                # Test config
├── .gitignore
├── LICENSE
└── CHANGELOG.md
```

## Implementation Steps

### Phase 1: Create Branch & Backup (5 min)

```bash
# Create new branch
git checkout -b sdk-restructure

# Commit current state
git add IMPLEMENTATION_PLAN.md RESTRUCTURE_PLAN.md
git commit -m "docs: add implementation and restructure plans"
```

### Phase 2: Clean Up (15 min)

**Delete server/deployment files:**
```bash
# Server code
rm -rf src/server/

# Deployment infrastructure
rm -rf deployment/

# Old build artifacts
rm -rf dist/

# Server-side preprocessing
rm -rf src/lib/preprocessors/
rm src/lib/preprocessor.ts

# CLI-specific
rm src/lib/config.ts
rm src/lib/uploader.ts
rm src/lib/progress.ts
rm test-upload.sh
rm .arke-upload.json
rm .arke-upload.example.json
rm Dockerfile
rm .dockerignore

# Old documentation (we'll consolidate)
rm ARCHITECTURE_REDESIGN.md
rm ARCHITECTURE_CLARIFICATION.md
rm SDK_COMPATIBILITY_ANALYSIS.md
rm PREPROCESSING_FLOW_OPTIONS.md
rm INGEST_API.md
rm 2025-10-29-so-take-a-look-at-readmemd-few-questions-about-t.txt
```

**Rename example_dirs to test fixtures:**
```bash
mkdir -p test/fixtures
cp -r example_dirs/iiif_test_small test/fixtures/small
cp -r example_dirs/tiff_test test/fixtures/tiffs
cp -r example_dirs/tiffs_and_pdfs test/fixtures/mixed
rm -rf example_dirs
```

### Phase 3: Update Package Config (10 min)

**package.json** - Transform to SDK:

```json
{
  "name": "@arke/upload-client",
  "version": "1.0.0",
  "description": "Portable upload client for Arke Institute's ingest service",
  "type": "module",
  "keywords": ["arke", "upload", "client", "cloudflare", "r2", "archival"],
  "author": "Arke Institute",
  "license": "MIT",
  "repository": {
    "type": "git",
    "url": "https://github.com/Arke-Institute/upload-client.git"
  },
  "main": "./dist/index.js",
  "module": "./dist/index.mjs",
  "browser": "./dist/browser.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "browser": "./dist/browser.js",
      "import": "./dist/index.mjs",
      "require": "./dist/index.js",
      "types": "./dist/index.d.ts"
    },
    "./browser": "./dist/browser.js",
    "./node": "./dist/index.js",
    "./package.json": "./package.json"
  },
  "files": [
    "dist",
    "README.md",
    "LICENSE"
  ],
  "scripts": {
    "build": "npm run build:node && npm run build:browser",
    "build:node": "tsc",
    "build:browser": "vite build",
    "dev": "tsc --watch",
    "test": "vitest",
    "test:watch": "vitest --watch",
    "lint": "tsc --noEmit",
    "prepublishOnly": "npm run build && npm test"
  },
  "dependencies": {
    "multiformats": "^13.4.1"
  },
  "devDependencies": {
    "@types/node": "^20.10.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.0",
    "vitest": "^1.0.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
```

### Phase 4: Refactor Core Code (2-3 hours)

**1. Create new ArkeUploader class** (`src/uploader.ts`):
- Simple, clean API
- Uses worker-client internally
- Handles file scanning + upload orchestration
- Progress callbacks

**2. Refactor worker-client** (`src/worker-client.ts`):
- Remove CLI-specific code
- Pure HTTP client using fetch()
- Clean up types

**3. Merge upload logic** (`src/r2-upload.ts`):
- Combine simple.ts + multipart.ts
- Single entry point: `uploadToR2(file, presignedUrl, options)`
- Auto-detect simple vs multipart

**4. Refactor scanner** (`src/scanner.ts`):
- Platform detection
- Separate implementations for browser/Node.js
- Move to `src/platforms/`

**5. Create platform adapters** (`src/platforms/`):
- `browser.ts` - File/FileList handling
- `node.ts` - fs-based scanning
- `common.ts` - Shared logic

**6. Clean up types** (`src/types/`):
- Remove server-specific types
- Organize by domain (config, worker, progress, file)
- Export from index.ts

**7. Simplify utils**:
- Keep: cid.ts, retry.ts, errors.ts
- Simplify: logger.ts (remove chalk/ora, just console)
- Add: platform.ts (detect environment)

### Phase 5: Create Examples (1 hour)

**Browser example** (`examples/browser.html`):
```html
<!DOCTYPE html>
<html>
<head>
  <title>Arke Upload - Browser Example</title>
</head>
<body>
  <h1>Arke Upload Client</h1>
  <input type="file" id="files" multiple webkitdirectory>
  <button onclick="upload()">Upload</button>
  <div id="progress"></div>

  <script type="module">
    import { ArkeUploader } from '../dist/browser.js';

    window.upload = async function() {
      const files = document.getElementById('files').files;
      const uploader = new ArkeUploader({
        workerUrl: 'https://ingest.arke.institute',
        uploader: 'Test User',
      });

      const result = await uploader.uploadBatch(files, {
        onProgress: (p) => {
          document.getElementById('progress').textContent =
            `${p.percentComplete}% - ${p.filesUploaded}/${p.filesTotal}`;
        },
      });

      alert(`Upload complete! Batch: ${result.batchId}`);
    };
  </script>
</body>
</html>
```

**Node.js example** (`examples/node-basic.ts`):
```typescript
import { ArkeUploader } from '../dist/index.js';
import { glob } from 'glob';

const uploader = new ArkeUploader({
  workerUrl: 'https://ingest.arke.institute',
  uploader: 'CLI User',
  rootPath: '/archives/test',
});

const files = glob.sync('./test/fixtures/small/**/*', { nodir: true });

const result = await uploader.uploadBatch(files, {
  onProgress: (p) => {
    console.log(`${p.percentComplete}% - ${p.currentFile}`);
  },
});

console.log(`Success! Batch: ${result.batchId}`);
```

### Phase 6: Write Tests (2 hours)

**Vitest config** (`vitest.config.ts`):
```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    coverage: {
      reporter: ['text', 'json', 'html'],
    },
  },
});
```

**Basic tests** (`test/uploader.test.ts`):
```typescript
import { describe, it, expect } from 'vitest';
import { ArkeUploader } from '../src/uploader';

describe('ArkeUploader', () => {
  it('should initialize with config', () => {
    const uploader = new ArkeUploader({
      workerUrl: 'https://test.com',
      uploader: 'Test',
    });

    expect(uploader).toBeDefined();
  });

  // More tests...
});
```

### Phase 7: Documentation (1 hour)

**Main README** (`README.md`):
- Installation
- Quick start
- Basic usage
- API overview
- Examples

**API Reference** (`docs/API.md`):
- Full API documentation
- All classes and methods
- TypeScript types

**Platform Guide** (`docs/PLATFORMS.md`):
- Browser compatibility
- Node.js support
- Deno support
- Cloudflare Workers notes

### Phase 8: Build System (30 min)

**TypeScript config** (`tsconfig.json`):
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "lib": ["ES2022"],
    "moduleResolution": "bundler",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "test"]
}
```

**Vite config** (`vite.config.ts`) for browser build:
```typescript
import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: path.resolve(__dirname, 'src/index.ts'),
      name: 'ArkeUploadClient',
      formats: ['umd'],
      fileName: () => 'browser.js',
    },
    outDir: 'dist',
  },
});
```

### Phase 9: Test & Commit (30 min)

```bash
# Build
npm run build

# Test
npm test

# Test example
node examples/node-basic.ts

# Commit
git add -A
git commit -m "refactor: restructure as SDK package

- Remove server and deployment code
- Create ArkeUploader SDK class
- Add multi-platform support
- Add examples and tests
- Update package.json for NPM publishing"

# Push branch
git push -u origin sdk-restructure
```

## Testing Strategy

### Unit Tests
- ArkeUploader class
- WorkerClient API calls
- File scanner (mock fs)
- R2 upload logic (mock fetch)
- CID computation
- Retry logic

### Integration Tests (with test fixtures)
```bash
# Test with real worker (staging)
WORKER_URL=https://ingest.arke.institute npm run test:integration

# Tests:
# - Upload small files (test/fixtures/small)
# - Upload TIFFs (test/fixtures/tiffs)
# - Upload mixed types (test/fixtures/mixed)
# - Test multipart (large file)
# - Test progress callbacks
# - Test error handling
```

### Manual Tests
```bash
# Browser test
npm run build
open examples/browser.html
# Test file upload via UI

# Node.js test
node examples/node-basic.ts
# Should upload test/fixtures/small to worker

# Check batch in worker
curl https://ingest.arke.institute/api/batches/{batchId}/status
```

## Success Criteria

- ✅ Clean directory structure (SDK-focused)
- ✅ No server/deployment code
- ✅ ArkeUploader class works
- ✅ Can upload files to worker
- ✅ Works in Node.js
- ✅ Examples run successfully
- ✅ Tests pass
- ✅ Package builds for Node + Browser
- ✅ Documentation complete

## Timeline

| Phase | Time | Description |
|-------|------|-------------|
| 1. Branch & Backup | 5 min | Create branch, commit docs |
| 2. Clean Up | 15 min | Delete unused files |
| 3. Update Package | 10 min | New package.json |
| 4. Refactor Core | 3 hours | Rewrite SDK classes |
| 5. Examples | 1 hour | Create usage examples |
| 6. Tests | 2 hours | Write test suite |
| 7. Documentation | 1 hour | Write docs |
| 8. Build System | 30 min | Configure build |
| 9. Test & Commit | 30 min | Final testing |
| **Total** | **~8 hours** | **1 day of focused work** |

## Next Steps

1. Review this plan
2. Execute Phase 1 (create branch)
3. Execute Phase 2 (cleanup)
4. Execute remaining phases sequentially
5. Test thoroughly
6. Open PR for review
