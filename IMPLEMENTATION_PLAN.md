# Arke Upload - Implementation Plan

**Version:** 3.0 Final
**Date:** 2025-01-06

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ CLIENT (Browser, Node.js, Deno, Bun)                        │
│                                                              │
│  @arke/upload-client SDK                                    │
│   - Scan files                                              │
│   - Call worker API                                         │
│   - Upload directly to R2                                   │
└─────────────────────────────────────────────────────────────┘
         │                              │
         │ (API calls)                  │ (File bytes)
         ▼                              ▼
┌──────────────────────┐       ┌────────────────────┐
│ Cloudflare Worker    │       │ Cloudflare R2      │
│ (ingest-worker)      │       │                    │
│                      │       │ staging/           │
│ - Init batch         │       │   {batchId}/       │
│ - Presigned URLs     │◄──────│     file1.jpg      │
│ - Complete files     │       │     file2.pdf      │
│ - Finalize           │       │     ...            │
│   ├─ Check needs     │       │                    │
│   │  preprocessing   │       └────────────────────┘
│   ├─ YES → PREPROCESS_QUEUE
│   └─ NO  → BATCH_QUEUE
└──────────────────────┘
         │
         │ (if needs preprocessing)
         ▼
┌──────────────────────┐
│ Cloudflare Queue     │
│ PREPROCESS_QUEUE     │
└──────────────────────┘
         │
         ▼
┌──────────────────────┐
│ Cloudflare Worker    │
│ (preprocess-bridge)  │ ← Lightweight consumer
│                      │
│ - Forwards to        │
│   Cloud Run          │
└──────────────────────┘
         │
         ▼
┌──────────────────────┐
│ Cloud Run Service    │
│ (preprocessor)       │
│                      │
│ - Download from R2   │
│ - TIFF → JPEG        │
│ - PDF → Pages        │
│ - Compute CIDs       │
│ - Upload to R2       │
│ - Callback worker    │
└──────────────────────┘
         │
         │ POST /api/batches/{id}/enqueue-processed
         ▼
┌──────────────────────┐
│ Cloudflare Worker    │
│ (ingest-worker)      │
│                      │
│ - Update batch       │
│ - Send BATCH_QUEUE   │
└──────────────────────┘
         │
         ▼
┌──────────────────────┐
│ Cloudflare Queue     │
│ BATCH_QUEUE          │
└──────────────────────┘
         │
         ▼
┌──────────────────────┐
│ Orchestrator         │
│ (existing)           │
└──────────────────────┘
```

---

## Component 1: Upload Client SDK

### Package: @arke/upload-client

**Location**: `/cli/sdk/`

**Structure**:
```
sdk/
├── src/
│   ├── index.ts              # Main export
│   ├── uploader.ts           # ArkeUploader class
│   ├── worker-client.ts      # Worker API calls
│   ├── r2-client.ts          # R2 direct upload
│   ├── scanner.ts            # File scanning (platform-specific)
│   ├── types.ts              # TypeScript types
│   └── utils/
│       ├── cid.ts            # CID computation
│       ├── retry.ts          # Retry logic
│       ├── progress.ts       # Progress tracking
│       └── queue.ts          # Concurrency control
├── dist/                     # Build output
├── package.json
├── tsconfig.json
└── README.md
```

**Core API**:

```typescript
export class ArkeUploader {
  constructor(config: {
    workerUrl: string;        // https://ingest.arke.institute
    uploader: string;         // User name
    rootPath?: string;        // Archive path (default: /)
    parentPi?: string;        // Parent identifier
    metadata?: Record<string, any>;
    processing?: {            // Processing config
      ocr?: boolean;
      describe?: boolean;
      pinax?: boolean;
    };
    concurrency?: number;     // Parallel uploads (default: 10)
    retries?: number;         // Retry attempts (default: 3)
  });

  // Main upload method
  async uploadBatch(
    files: File[] | FileList | string[],
    options?: {
      onProgress?: (progress: ProgressEvent) => void;
      waitForCompletion?: boolean;
    }
  ): Promise<{
    batchId: string;
    sessionId: string;
    filesUploaded: number;
    bytesUploaded: number;
    status: string;
  }>;
}
```

**Implementation Steps**:

1. **Project setup** (1 hour)
   ```bash
   mkdir -p cli/sdk
   cd cli/sdk
   npm init -y
   npm install multiformats
   npm install -D typescript @types/node vitest
   ```

2. **Worker client** (2 hours)
   ```typescript
   // src/worker-client.ts
   export class WorkerClient {
     async initBatch(params: InitBatchRequest): Promise<InitBatchResponse>;
     async startFileUpload(batchId: string, file: FileInfo): Promise<PresignedUrlResponse>;
     async completeFileUpload(batchId: string, r2Key: string, parts?: Part[]): Promise<void>;
     async finalizeBatch(batchId: string): Promise<void>;
     async getStatus(batchId: string): Promise<BatchStatus>;
   }
   ```

3. **R2 uploader** (3 hours)
   ```typescript
   // src/r2-client.ts
   export class R2Client {
     // Simple upload (<5MB)
     async uploadSimple(url: string, file: File | Buffer): Promise<void>;

     // Multipart upload (≥5MB)
     async uploadMultipart(
       urls: string[],
       file: File | Buffer,
       partSize: number,
       onProgress?: (bytes: number) => void
     ): Promise<Part[]>;
   }
   ```

4. **File scanner** (2 hours)
   ```typescript
   // src/scanner.ts
   export async function scanFiles(
     input: File[] | FileList | string[]
   ): Promise<FileInfo[]> {
     // Platform detection
     if (input[0] instanceof File) {
       return scanBrowserFiles(input as File[]);
     } else {
       return scanNodeFiles(input as string[]);
     }
   }
   ```

5. **Main uploader** (3 hours)
   ```typescript
   // src/uploader.ts
   export class ArkeUploader {
     async uploadBatch(files, options) {
       // 1. Scan files → FileInfo[]
       const fileInfos = await scanFiles(files);

       // 2. Init batch
       const { batch_id, session_id } = await this.client.initBatch({
         uploader: this.config.uploader,
         root_path: this.config.rootPath,
         file_count: fileInfos.length,
         total_size: fileInfos.reduce((sum, f) => sum + f.size, 0),
         metadata: this.config.metadata,
       });

       // 3. For each file: get URL → upload → complete
       await this.uploadFiles(batch_id, fileInfos, options?.onProgress);

       // 4. Finalize
       await this.client.finalizeBatch(batch_id);

       return { batchId: batch_id, sessionId: session_id, ... };
     }
   }
   ```

6. **Build configuration** (1 hour)
   ```json
   // package.json
   {
     "name": "@arke/upload-client",
     "version": "1.0.0",
     "type": "module",
     "exports": {
       ".": {
         "browser": "./dist/browser.js",
         "node": "./dist/index.js",
         "default": "./dist/index.js"
       }
     },
     "dependencies": {
       "multiformats": "^13.4.1"
     }
   }
   ```

**Total: ~12 hours (1.5 days)**

---

## Component 2: Worker Changes (ingest-worker)

### Changes Needed

**1. Add preprocessing queue** (wrangler.toml)
```toml
[[queues.producers]]
queue = "preprocess-queue"
binding = "PREPROCESS_QUEUE"

[[queues.producers]]
queue = "batch-queue"
binding = "BATCH_QUEUE"
```

**2. Add preprocessing status** (src/types.ts)
```typescript
export type BatchStatus =
  | 'uploading'
  | 'preprocessing'  // NEW
  | 'enqueued'
  | 'processing'
  | 'completed'
  | 'failed';
```

**3. Update finalize handler** (src/handlers/finalize.ts)
```typescript
export async function handleFinalizeBatch(c: Context<{ Bindings: Env }>) {
  // ... existing validation code ...

  // Build queue message
  const queueMessage: QueueMessage = {
    batch_id: batchId,
    r2_prefix: `staging/${batchId}/`,
    uploader: state.uploader,
    root_path: state.root_path,
    parent_pi: state.parent_pi,
    total_files: state.files.length,
    total_bytes: totalBytes,
    uploaded_at: state.created_at,
    finalized_at: new Date().toISOString(),
    metadata: state.metadata,
    directories: directories,
  };

  // CHECK: Does this batch need preprocessing?
  const needsPreprocessing = state.files.some(f => {
    // TIFF files need conversion
    if (f.file_name.match(/\.tiff?$/i)) return true;

    // PDF files might need splitting
    if (f.file_name.match(/\.pdf$/i)) return true;

    // Missing CID needs computation
    if (!f.cid) return true;

    return false;
  });

  if (needsPreprocessing) {
    // Send to preprocessing queue
    await c.env.PREPROCESS_QUEUE.send(queueMessage);
    await stub.updateStatus('preprocessing', new Date().toISOString());

    return c.json({
      batch_id: batchId,
      status: 'preprocessing',
      files_uploaded: state.files.length,
      total_bytes: totalBytes,
      message: 'Batch queued for preprocessing',
    });
  } else {
    // No preprocessing needed - direct to batch queue
    await c.env.BATCH_QUEUE.send(queueMessage);
    await stub.updateStatus('enqueued', new Date().toISOString());

    return c.json({
      batch_id: batchId,
      status: 'enqueued',
      files_uploaded: state.files.length,
      total_bytes: totalBytes,
    });
  }
}
```

**4. Add enqueue-processed endpoint** (src/handlers/enqueue-processed.ts)
```typescript
/**
 * POST /api/batches/:batchId/enqueue-processed
 * Called by Cloud Run after preprocessing completes
 */
export async function handleEnqueueProcessed(c: Context<{ Bindings: Env }>) {
  const batchId = c.req.param('batchId');
  const { processedFiles } = await c.req.json();

  // Get batch state
  const stub = getBatchStateStub(c.env.BATCH_STATE_DO, batchId);
  const state = await stub.getState();

  if (!state) {
    return c.json({ error: 'Batch not found' }, 404);
  }

  if (state.status !== 'preprocessing') {
    return c.json({ error: `Invalid batch state: ${state.status}` }, 400);
  }

  // Update batch with processed files
  await stub.updateProcessedFiles(processedFiles);

  // Build updated queue message
  const queueMessage: QueueMessage = {
    batch_id: batchId,
    r2_prefix: `staging/${batchId}/`,
    uploader: state.uploader,
    root_path: state.root_path,
    parent_pi: state.parent_pi,
    total_files: processedFiles.length,
    total_bytes: processedFiles.reduce((sum, f) => sum + f.file_size, 0),
    uploaded_at: state.created_at,
    finalized_at: new Date().toISOString(),
    metadata: state.metadata,
    directories: groupFilesByDirectory(processedFiles),
  };

  // NOW send to batch queue
  await c.env.BATCH_QUEUE.send(queueMessage);
  await stub.updateStatus('enqueued', new Date().toISOString());

  return c.json({
    success: true,
    batch_id: batchId,
    status: 'enqueued',
  });
}
```

**5. Update Durable Object** (src/durable-objects/BatchState.ts)
```typescript
export class BatchStateObject {
  // ... existing methods ...

  async updateProcessedFiles(processedFiles: ProcessedFileInfo[]) {
    const state = await this.state.get<BatchState>('state');
    if (!state) throw new Error('Batch not found');

    // Merge processed files with original files
    // Replace/add files based on r2_key
    const fileMap = new Map(state.files.map(f => [f.r2_key, f]));

    for (const pf of processedFiles) {
      fileMap.set(pf.r2_key, {
        ...fileMap.get(pf.r2_key),
        ...pf,
        status: 'completed',
      });
    }

    state.files = Array.from(fileMap.values());
    await this.state.put('state', state);
  }
}
```

**6. Register new endpoint** (src/index.ts)
```typescript
import { handleEnqueueProcessed } from './handlers/enqueue-processed';

app.post('/api/batches/:batchId/enqueue-processed', handleEnqueueProcessed);
```

**Total: ~4 hours**

---

## Component 3: Preprocessing Bridge Worker

### New Worker: preprocess-bridge

**Location**: `/arke-ingest-worker/preprocess-bridge/`

**wrangler.toml**:
```toml
name = "preprocess-bridge"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[[queues.consumers]]
queue = "preprocess-queue"
max_batch_size = 1
max_retries = 3
dead_letter_queue = "preprocess-dlq"

[vars]
CLOUD_RUN_URL = "https://arke-preprocessor-xxx.run.app"
```

**src/index.ts**:
```typescript
export interface Env {
  CLOUD_RUN_URL: string;
}

export default {
  async queue(
    batch: MessageBatch<QueueMessage>,
    env: Env,
    ctx: ExecutionContext
  ): Promise<void> {
    for (const message of batch.messages) {
      try {
        console.log(`Forwarding batch ${message.body.batch_id} to Cloud Run`);

        // Forward to Cloud Run
        const response = await fetch(env.CLOUD_RUN_URL + '/preprocess', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(message.body),
        });

        if (!response.ok) {
          const error = await response.text();
          throw new Error(`Cloud Run error: ${response.status} - ${error}`);
        }

        console.log(`Successfully forwarded batch ${message.body.batch_id}`);

        // Ack message (tells Cloudflare we're done)
        message.ack();
      } catch (error) {
        console.error(`Failed to forward batch ${message.body.batch_id}:`, error);

        // Retry the message (Cloudflare will retry up to max_retries)
        message.retry();
      }
    }
  }
};

export interface QueueMessage {
  batch_id: string;
  r2_prefix: string;
  uploader: string;
  root_path: string;
  parent_pi: string;
  total_files: number;
  total_bytes: number;
  uploaded_at: string;
  finalized_at: string;
  metadata: Record<string, any>;
  directories: DirectoryGroup[];
}

export interface DirectoryGroup {
  directory_path: string;
  processing_config: ProcessingConfig;
  file_count: number;
  total_bytes: number;
  files: QueueFileInfo[];
}

export interface QueueFileInfo {
  r2_key: string;
  logical_path: string;
  file_name: string;
  file_size: number;
  content_type: string;
  cid?: string;
}

export interface ProcessingConfig {
  ocr: boolean;
  describe: boolean;
  pinax: boolean;
}
```

**Deploy**:
```bash
cd arke-ingest-worker/preprocess-bridge
npm install
npx wrangler deploy
```

**Total: ~2 hours**

---

## Component 4: Cloud Run Preprocessor

### Service: arke-preprocessor

**Location**: `/preprocessor/`

**Structure**:
```
preprocessor/
├── src/
│   ├── index.ts              # Express server
│   ├── processor.ts          # Main processing logic
│   ├── tiff-converter.ts     # TIFF → JPEG
│   ├── pdf-splitter.ts       # PDF → Pages
│   ├── cid-computer.ts       # CID computation
│   └── r2-client.ts          # R2 download/upload
├── Dockerfile
├── package.json
└── .env.example
```

**Dockerfile**:
```dockerfile
FROM node:20-slim

# Install Sharp dependencies
RUN apt-get update && apt-get install -y \
    libvips-dev \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY src/ ./src/
COPY tsconfig.json ./
RUN npm run build

ENV NODE_ENV=production
ENV PORT=8080

CMD ["node", "dist/index.js"]
```

**package.json**:
```json
{
  "name": "arke-preprocessor",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx src/index.ts"
  },
  "dependencies": {
    "express": "^4.18.2",
    "@aws-sdk/client-s3": "^3.450.0",
    "sharp": "^0.33.0",
    "pdf-lib": "^1.17.1",
    "multiformats": "^13.0.0"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.0",
    "tsx": "^4.7.0",
    "typescript": "^5.3.0"
  }
}
```

**src/index.ts**:
```typescript
import express from 'express';
import { processBatch } from './processor.js';

const app = express();
app.use(express.json({ limit: '10mb' }));

const PORT = process.env.PORT || 8080;

// Health check
app.get('/', (req, res) => {
  res.json({ service: 'arke-preprocessor', status: 'healthy' });
});

// Main preprocessing endpoint
app.post('/preprocess', async (req, res) => {
  const queueMessage = req.body;
  const { batch_id } = queueMessage;

  console.log(`Received preprocessing request for batch: ${batch_id}`);

  // Respond immediately (don't block)
  res.json({ status: 'processing', batch_id });

  // Process in background
  processInBackground(queueMessage);
});

async function processInBackground(message: any) {
  try {
    console.log(`Starting preprocessing for batch: ${message.batch_id}`);

    const processedFiles = await processBatch(message);

    console.log(`Preprocessing complete for batch: ${message.batch_id}`);
    console.log(`Processed ${processedFiles.length} files`);

    // Callback to worker
    const response = await fetch(
      `${process.env.WORKER_URL}/api/batches/${message.batch_id}/enqueue-processed`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ processedFiles }),
      }
    );

    if (!response.ok) {
      throw new Error(`Worker callback failed: ${response.status}`);
    }

    console.log(`Successfully enqueued batch: ${message.batch_id}`);
  } catch (error) {
    console.error(`Preprocessing failed for batch ${message.batch_id}:`, error);
    // Error logged, worker bridge will retry
  }
}

app.listen(PORT, () => {
  console.log(`Preprocessor listening on port ${PORT}`);
});
```

**src/processor.ts**:
```typescript
import { S3Client } from '@aws-sdk/client-s3';
import { convertTiff } from './tiff-converter.js';
import { splitPdf } from './pdf-splitter.js';
import { computeCID } from './cid-computer.js';

const r2 = new S3Client({
  region: 'auto',
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID!,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
  },
});

export async function processBatch(message: QueueMessage): Promise<ProcessedFile[]> {
  const { batch_id, directories } = message;

  const allProcessedFiles: ProcessedFile[] = [];

  // Process each directory
  for (const dir of directories) {
    for (const file of dir.files) {
      console.log(`Processing file: ${file.file_name}`);

      // Check if file needs processing
      if (file.file_name.match(/\.tiff?$/i)) {
        const jpegFile = await convertTiff(r2, batch_id, file);
        allProcessedFiles.push(jpegFile);
      } else if (file.file_name.match(/\.pdf$/i)) {
        const pageFiles = await splitPdf(r2, batch_id, file);
        allProcessedFiles.push(...pageFiles);
      } else {
        // Just compute CID if missing
        if (!file.cid) {
          file.cid = await computeCID(r2, file.r2_key);
        }
        allProcessedFiles.push(file);
      }
    }
  }

  return allProcessedFiles;
}
```

**src/tiff-converter.ts**:
```typescript
import sharp from 'sharp';
import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { streamToBuffer } from './utils.js';

export async function convertTiff(
  r2: S3Client,
  batchId: string,
  file: QueueFileInfo
): Promise<ProcessedFile> {
  console.log(`Converting TIFF: ${file.file_name}`);

  // Download TIFF from R2
  const getResponse = await r2.send(
    new GetObjectCommand({
      Bucket: 'arke-staging',
      Key: file.r2_key,
    })
  );

  const tiffBuffer = await streamToBuffer(getResponse.Body);

  // Convert to JPEG
  const jpegBuffer = await sharp(tiffBuffer)
    .jpeg({ quality: 95, mozjpeg: true })
    .toBuffer();

  // Upload JPEG to R2
  const jpegKey = file.r2_key.replace(/\.tiff?$/i, '.jpg');
  const jpegLogicalPath = file.logical_path.replace(/\.tiff?$/i, '.jpg');

  await r2.send(
    new PutObjectCommand({
      Bucket: 'arke-staging',
      Key: jpegKey,
      Body: jpegBuffer,
      ContentType: 'image/jpeg',
    })
  );

  // Compute CID for JPEG
  const cid = await computeCIDFromBuffer(jpegBuffer);

  console.log(`TIFF converted: ${file.file_name} → ${jpegKey}`);
  console.log(`Size: ${tiffBuffer.length} → ${jpegBuffer.length} bytes`);

  return {
    r2_key: jpegKey,
    logical_path: jpegLogicalPath,
    file_name: file.file_name.replace(/\.tiff?$/i, '.jpg'),
    file_size: jpegBuffer.length,
    content_type: 'image/jpeg',
    cid,
  };
}
```

**src/pdf-splitter.ts**:
```typescript
import { PDFDocument } from 'pdf-lib';
import sharp from 'sharp';
import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';

export async function splitPdf(
  r2: S3Client,
  batchId: string,
  file: QueueFileInfo
): Promise<ProcessedFile[]> {
  console.log(`Splitting PDF: ${file.file_name}`);

  // Download PDF
  const getResponse = await r2.send(
    new GetObjectCommand({
      Bucket: 'arke-staging',
      Key: file.r2_key,
    })
  );

  const pdfBuffer = await streamToBuffer(getResponse.Body);

  // Load PDF
  const pdfDoc = await PDFDocument.load(pdfBuffer);
  const pageCount = pdfDoc.getPageCount();

  console.log(`PDF has ${pageCount} pages`);

  const pageFiles: ProcessedFile[] = [];

  // Process each page
  for (let i = 0; i < pageCount; i++) {
    // Extract page
    const pagePdf = await PDFDocument.create();
    const [copiedPage] = await pagePdf.copyPages(pdfDoc, [i]);
    pagePdf.addPage(copiedPage);

    // Render to PNG
    const pngBuffer = await renderPdfPageToPng(pagePdf);

    // Convert to JPEG
    const jpegBuffer = await sharp(pngBuffer)
      .jpeg({ quality: 95 })
      .toBuffer();

    // Upload to R2
    const pageNum = String(i + 1).padStart(4, '0');
    const pageKey = file.r2_key.replace(/\.pdf$/i, `_page_${pageNum}.jpg`);
    const pageLogicalPath = file.logical_path.replace(/\.pdf$/i, `_page_${pageNum}.jpg`);

    await r2.send(
      new PutObjectCommand({
        Bucket: 'arke-staging',
        Key: pageKey,
        Body: jpegBuffer,
        ContentType: 'image/jpeg',
      })
    );

    // Compute CID
    const cid = await computeCIDFromBuffer(jpegBuffer);

    pageFiles.push({
      r2_key: pageKey,
      logical_path: pageLogicalPath,
      file_name: `${file.file_name}_page_${pageNum}.jpg`,
      file_size: jpegBuffer.length,
      content_type: 'image/jpeg',
      cid,
    });
  }

  console.log(`PDF split into ${pageCount} pages`);

  return pageFiles;
}

async function renderPdfPageToPng(pdfDoc: PDFDocument): Promise<Buffer> {
  // TODO: Use pdf-to-png library or similar
  // This is a placeholder
  throw new Error('PDF rendering not implemented');
}
```

**src/cid-computer.ts**:
```typescript
import { GetObjectCommand } from '@aws-sdk/client-s3';
import { CID } from 'multiformats/cid';
import * as raw from 'multiformats/codecs/raw';
import { sha256 } from 'multiformats/hashes/sha2';
import crypto from 'crypto';

export async function computeCID(r2: S3Client, r2Key: string): Promise<string> {
  // Stream file from R2 and hash
  const response = await r2.send(
    new GetObjectCommand({
      Bucket: 'arke-staging',
      Key: r2Key,
    })
  );

  const hash = crypto.createHash('sha256');
  for await (const chunk of response.Body) {
    hash.update(chunk);
  }

  const digest = hash.digest();

  // Create CIDv1
  const multihash = await sha256.digest(digest);
  const cid = CID.create(1, raw.code, multihash);

  return cid.toString();
}

export async function computeCIDFromBuffer(buffer: Buffer): Promise<string> {
  const hash = await sha256.digest(buffer);
  const cid = CID.create(1, raw.code, hash);
  return cid.toString();
}
```

**Deploy**:
```bash
cd preprocessor

# Build and push image
docker build -t gcr.io/arke-institute/preprocessor:latest .
docker push gcr.io/arke-institute/preprocessor:latest

# Deploy to Cloud Run
gcloud run deploy arke-preprocessor \
  --image gcr.io/arke-institute/preprocessor:latest \
  --region us-central1 \
  --platform managed \
  --memory 4Gi \
  --cpu 4 \
  --min-instances 0 \
  --max-instances 10 \
  --timeout 3600s \
  --set-env-vars WORKER_URL=https://ingest.arke.institute \
  --set-secrets R2_ACCOUNT_ID=r2-account-id:latest,R2_ACCESS_KEY_ID=r2-access-key:latest,R2_SECRET_ACCESS_KEY=r2-secret-key:latest
```

**Total: ~16 hours (2 days)**

---

## Implementation Timeline

### Week 1: SDK + Worker Changes

**Day 1-2: SDK Core (12 hours)**
- Project setup
- Worker client implementation
- R2 upload (simple + multipart)
- File scanner (Node.js + Browser)

**Day 3: SDK Integration (8 hours)**
- Main ArkeUploader class
- Progress tracking
- Retry logic
- Unit tests

**Day 4: Worker Changes (4 hours)**
- Add PREPROCESS_QUEUE
- Update finalize handler
- Add enqueue-processed endpoint
- Test with SDK

**Day 5: Testing & Polish (8 hours)**
- Integration tests (SDK + Worker)
- Test multipart uploads
- Test preprocessing routing
- Documentation

### Week 2: Preprocessing

**Day 6: Bridge Worker (2 hours)**
- Create preprocess-bridge worker
- Test queue forwarding
- Deploy

**Day 7-8: Cloud Run Service (16 hours)**
- Project setup
- Express server
- TIFF converter
- PDF splitter
- CID computer
- R2 client

**Day 9: Integration (8 hours)**
- Connect all pieces
- End-to-end testing
- Deploy to GCP

**Day 10: Testing & Documentation (8 hours)**
- Test large batches
- Test TIFF/PDF processing
- Performance testing
- Write deployment guide

---

## Deployment Steps

### 1. Deploy SDK

```bash
cd cli/sdk
npm run build
npm publish --access public
```

### 2. Deploy Worker Changes

```bash
cd arke-ingest-worker
npx wrangler deploy
```

### 3. Deploy Bridge Worker

```bash
cd arke-ingest-worker/preprocess-bridge
npx wrangler deploy
```

### 4. Deploy Cloud Run

```bash
cd preprocessor
docker build -t gcr.io/arke-institute/preprocessor:latest .
docker push gcr.io/arke-institute/preprocessor:latest
gcloud run deploy arke-preprocessor \
  --image gcr.io/arke-institute/preprocessor:latest \
  --region us-central1 \
  --memory 4Gi \
  --cpu 4 \
  --min-instances 0 \
  --max-instances 10 \
  --timeout 3600s
```

### 5. Update Clients

```bash
# CLI tool
cd cli
npm install @arke/upload-client
# Update src/index.ts to use SDK

# Frontend
cd arke-upload-frontend
npm install @arke/upload-client
# Update components to use SDK
```

---

## Environment Variables

### Worker (ingest-worker)
```bash
# Already set
R2_ACCOUNT_ID=xxx
R2_ACCESS_KEY_ID=xxx
R2_SECRET_ACCESS_KEY=xxx
MAX_FILE_SIZE=5368709120
MAX_BATCH_SIZE=107374182400
PRESIGNED_URL_EXPIRY=3600
```

### Bridge Worker (preprocess-bridge)
```bash
CLOUD_RUN_URL=https://arke-preprocessor-xxx.run.app
```

### Cloud Run (preprocessor)
```bash
PORT=8080
NODE_ENV=production
WORKER_URL=https://ingest.arke.institute
R2_ACCOUNT_ID=xxx
R2_ACCESS_KEY_ID=xxx
R2_SECRET_ACCESS_KEY=xxx
```

---

## Usage Examples

### Browser

```html
<script type="module">
import { ArkeUploader } from 'https://unpkg.com/@arke/upload-client/dist/browser.js';

const uploader = new ArkeUploader({
  workerUrl: 'https://ingest.arke.institute',
  uploader: 'Jane Doe',
});

document.getElementById('fileInput').addEventListener('change', async (e) => {
  const files = e.target.files;

  const result = await uploader.uploadBatch(files, {
    onProgress: (p) => {
      console.log(`${p.percentComplete}% - ${p.currentFile}`);
    },
  });

  console.log(`Upload complete! Batch: ${result.batchId}`);
});
</script>
```

### Node.js CLI

```typescript
import { ArkeUploader } from '@arke/upload-client';
import { glob } from 'glob';

const uploader = new ArkeUploader({
  workerUrl: 'https://ingest.arke.institute',
  uploader: 'CLI User',
  rootPath: '/archives/collection_1',
  processing: { ocr: true, describe: true },
});

const files = glob.sync('/path/to/archive/**/*', { nodir: true });

await uploader.uploadBatch(files, {
  onProgress: (p) => {
    process.stdout.write(`\r${p.percentComplete}%`);
  },
});

console.log('\nUpload complete!');
```

---

## Testing Checklist

- [ ] SDK can upload to worker
- [ ] Simple uploads work (<5MB)
- [ ] Multipart uploads work (≥5MB)
- [ ] Progress tracking works
- [ ] Retry logic works
- [ ] Worker routes to PREPROCESS_QUEUE correctly
- [ ] Worker routes to BATCH_QUEUE correctly
- [ ] Bridge worker forwards messages
- [ ] Cloud Run receives messages
- [ ] TIFF conversion works
- [ ] PDF splitting works
- [ ] CID computation works
- [ ] Cloud Run callbacks to worker
- [ ] Batch gets enqueued after preprocessing
- [ ] Orchestrator receives final batch

---

## Done!

This is the complete implementation plan. No backwards compatibility, no migration, just build it fresh.

**Total Effort**: ~80 hours (2 weeks for 1 developer)

**Components**:
1. ✅ Upload Client SDK (portable)
2. ✅ Worker changes (minimal)
3. ✅ Bridge worker (lightweight)
4. ✅ Cloud Run preprocessor (heavy lifting)

**Flow**:
Client SDK → Worker → PREPROCESS_QUEUE → Bridge → Cloud Run → Worker → BATCH_QUEUE → Orchestrator

Ready to build! 🚀
