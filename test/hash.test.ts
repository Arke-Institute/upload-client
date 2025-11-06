/**
 * Tests for CID computation
 */

import { describe, it, expect } from 'vitest';
import { computeCIDFromBuffer } from '../src/utils/hash.js';

describe('CID Computation', () => {
  it('should compute CID for empty buffer', async () => {
    const buffer = new Uint8Array(0);
    const cid = await computeCIDFromBuffer(buffer);

    expect(cid).toBeDefined();
    expect(typeof cid).toBe('string');
    expect(cid.startsWith('bafk')).toBe(true); // CIDv1 with raw codec
  });

  it('should compute CID for non-empty buffer', async () => {
    const buffer = new Uint8Array([1, 2, 3, 4, 5]);
    const cid = await computeCIDFromBuffer(buffer);

    expect(cid).toBeDefined();
    expect(typeof cid).toBe('string');
    expect(cid.startsWith('bafk')).toBe(true);
  });

  it('should produce consistent CIDs for same data', async () => {
    const buffer1 = new Uint8Array([1, 2, 3, 4, 5]);
    const buffer2 = new Uint8Array([1, 2, 3, 4, 5]);

    const cid1 = await computeCIDFromBuffer(buffer1);
    const cid2 = await computeCIDFromBuffer(buffer2);

    expect(cid1).toBe(cid2);
  });

  it('should produce different CIDs for different data', async () => {
    const buffer1 = new Uint8Array([1, 2, 3, 4, 5]);
    const buffer2 = new Uint8Array([5, 4, 3, 2, 1]);

    const cid1 = await computeCIDFromBuffer(buffer1);
    const cid2 = await computeCIDFromBuffer(buffer2);

    expect(cid1).not.toBe(cid2);
  });
});
