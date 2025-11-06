/**
 * Tests for validation utilities
 */

import { describe, it, expect } from 'vitest';
import {
  validateFileSize,
  validateBatchSize,
  validateLogicalPath,
  normalizePath,
} from '../src/lib/validation.js';
import { ValidationError } from '../src/utils/errors.js';

describe('Validation', () => {
  describe('validateFileSize', () => {
    it('should accept valid file sizes', () => {
      expect(() => validateFileSize(1024)).not.toThrow();
      expect(() => validateFileSize(1024 * 1024)).not.toThrow();
      expect(() => validateFileSize(1024 * 1024 * 1024)).not.toThrow();
    });

    it('should reject files that are too large', () => {
      const maxSize = 5 * 1024 * 1024 * 1024; // 5 GB
      expect(() => validateFileSize(maxSize + 1)).toThrow(ValidationError);
    });

    it('should reject zero or negative sizes', () => {
      expect(() => validateFileSize(0)).toThrow(ValidationError);
      expect(() => validateFileSize(-1)).toThrow(ValidationError);
    });
  });

  describe('validateBatchSize', () => {
    it('should accept valid batch sizes', () => {
      expect(() => validateBatchSize(1024)).not.toThrow();
      expect(() => validateBatchSize(50 * 1024 * 1024 * 1024)).not.toThrow();
    });

    it('should reject batches that are too large', () => {
      const maxSize = 100 * 1024 * 1024 * 1024; // 100 GB
      expect(() => validateBatchSize(maxSize + 1)).toThrow(ValidationError);
    });
  });

  describe('validateLogicalPath', () => {
    it('should accept valid logical paths', () => {
      expect(() => validateLogicalPath('/test/path')).not.toThrow();
      expect(() => validateLogicalPath('/archives/collection/box_1')).not.toThrow();
      expect(() => validateLogicalPath('/test/file.pdf')).not.toThrow();
    });

    it('should reject paths with invalid characters', () => {
      expect(() => validateLogicalPath('/test/path<invalid>')).toThrow(ValidationError);
      expect(() => validateLogicalPath('/test/path|invalid')).toThrow(ValidationError);
    });

    it('should reject paths that do not start with /', () => {
      expect(() => validateLogicalPath('relative/path')).toThrow(ValidationError);
    });
  });

  describe('normalizePath', () => {
    it('should convert backslashes to forward slashes', () => {
      expect(normalizePath('path\\to\\file')).toBe('path/to/file');
      expect(normalizePath('path\\with\\backslashes\\')).toBe('path/with/backslashes/');
    });

    it('should leave forward slashes unchanged', () => {
      expect(normalizePath('path/to/file')).toBe('path/to/file');
    });

    it('should handle mixed slashes', () => {
      expect(normalizePath('path\\to/file\\name')).toBe('path/to/file/name');
    });
  });
});
