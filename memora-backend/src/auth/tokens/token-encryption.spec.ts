import { decryptToken, encryptToken, encryptionKey } from './token-encryption';

describe('token encryption', () => {
  it('round-trips AES-256-GCM data with a per-record nonce', () => {
    const key = encryptionKey(Buffer.alloc(32, 7).toString('base64'));
    const first = encryptToken('refresh-token', key);
    const second = encryptToken('refresh-token', key);
    expect(decryptToken(first, key)).toBe('refresh-token');
    expect(first.nonce).not.toBe(second.nonce);
    expect(first.ciphertext).not.toContain('refresh-token');
  });

  it('accepts exactly 32 bytes in hex or base64 and rejects other sizes', () => {
    expect(encryptionKey('a'.repeat(64))).toHaveLength(32);
    expect(encryptionKey(Buffer.alloc(32).toString('base64'))).toHaveLength(32);
    expect(() => encryptionKey('too-short')).toThrow();
  });
});
