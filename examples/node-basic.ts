/**
 * Basic Node.js example - Upload test fixtures to Arke
 */

import { ArkeUploader } from '../dist/uploader.js';

async function main() {
  // Create uploader instance
  const uploader = new ArkeUploader({
    workerUrl: process.env.WORKER_URL || 'https://ingest.arke.institute',
    uploader: 'SDK Test User',
    rootPath: '/test/sdk-upload',
    parallelUploads: 3,
  });

  console.log('🚀 Starting upload...\n');

  try {
    // Upload test fixtures
    const result = await uploader.uploadBatch(
      './test/fixtures/small',
      {
        onProgress: (progress) => {
          const pct = progress.percentComplete.toFixed(1);
          const current = progress.currentFile || '...';
          console.log(
            `[${progress.phase.toUpperCase()}] ${pct}% - ${progress.filesUploaded}/${progress.filesTotal} files - ${current}`
          );
        },
      }
    );

    console.log('\n✅ Upload complete!');
    console.log(`   Batch ID: ${result.batchId}`);
    console.log(`   Files uploaded: ${result.filesUploaded}`);
    console.log(`   Bytes uploaded: ${(result.bytesUploaded / 1024 / 1024).toFixed(2)} MB`);
    console.log(`   Duration: ${(result.durationMs / 1000).toFixed(2)}s`);
  } catch (error: any) {
    console.error('\n❌ Upload failed:', error.message);
    if (error.details) {
      console.error('   Details:', error.details);
    }
    process.exit(1);
  }
}

main();
