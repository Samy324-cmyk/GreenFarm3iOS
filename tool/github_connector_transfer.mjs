// Read-only adapter for bounded Node REPL -> functions.exec connector transfers.
// This module performs no network requests and cannot update a GitHub ref.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

const sha256 = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const normalize = (value) => path.sep === '\\' ? value.toLowerCase() : value;

export async function openSnapshot(manifestPath) {
  const absoluteManifest = path.resolve(manifestPath);
  const manifest = JSON.parse(await fs.readFile(absoluteManifest, 'utf8'));
  if (manifest.schema !== 1 || !Array.isArray(manifest.files)) {
    throw new Error('Unsupported snapshot manifest');
  }
  const root = path.resolve(manifest.repository_root);
  if (normalize(root) !== normalize(path.join(path.dirname(absoluteManifest), 'repository'))) {
    throw new Error('Only the frozen repository beside the manifest can be read');
  }
  const blobs = new Map();
  const fileNames = new Set();
  for (const entry of manifest.files) {
    const parts = entry.path.split('/');
    if (!entry.path || /[\\:\0\r\n]/.test(entry.path) || parts.some(p => !p || p === '.' || p === '..')) {
      throw new Error(`Invalid snapshot path: ${entry.path}`);
    }
    if (fileNames.has(entry.path.toLowerCase())) throw new Error(`Duplicate snapshot path: ${entry.path}`);
    fileNames.add(entry.path.toLowerCase());
    blobs.set(entry.git_blob_sha, entry);
  }
  const canonical = JSON.stringify(manifest.files.map(entry => Object.fromEntries(Object.entries(entry).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0))));
  if (sha256(canonical) !== manifest.files_digest_sha256) throw new Error('Snapshot manifest digest mismatch');
  let cachedSha;
  let cachedBase64;

  async function readBlob(sha) {
    if (sha === cachedSha) return cachedBase64;
    const entry = blobs.get(sha);
    if (!entry) throw new Error(`Blob is not listed in the snapshot: ${sha}`);
    const filePath = path.join(root, ...entry.path.split('/'));
    if (normalize(await fs.realpath(filePath)) !== normalize(filePath)) {
      throw new Error(`Linked snapshot path is not allowed: ${entry.path}`);
    }
    const bytes = await fs.readFile(filePath);
    const actualSha = crypto.createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
    if (bytes.length !== entry.size || sha256(bytes) !== entry.sha256 || actualSha !== sha) {
      throw new Error(`Snapshot blob has changed: ${entry.path}`);
    }
    cachedBase64 = bytes.toString('base64');
    cachedSha = sha;
    return cachedBase64;
  }

  return {
    summary() {
      return { files: manifest.files.length, uniqueBlobs: blobs.size,
        manifestDigest: manifest.files_digest_sha256, reviewState: manifest.review_state };
    },
    async readBlobChunk(sha, offset = 0, maxChars = 524288) {
      if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(maxChars) || maxChars < 1 || maxChars > 1048576) {
        throw new Error('Invalid bounded chunk request');
      }
      const encoded = await readBlob(sha);
      if (offset > encoded.length) throw new Error('Chunk offset exceeds blob length');
      const nextOffset = Math.min(offset + maxChars, encoded.length);
      return { sha, offset, nextOffset, totalChars: encoded.length,
        content: encoded.slice(offset, nextOffset), encoding: 'base64' };
    },
    clearCache() { cachedSha = undefined; cachedBase64 = undefined; },
  };
}
