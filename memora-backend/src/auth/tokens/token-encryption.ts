import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

export function encryptionKey(value: string | undefined): Buffer {
  if (!value) throw new Error('TOKEN_ENCRYPTION_KEY is not configured');
  const decoded = /^[0-9a-f]{64}$/i.test(value)
    ? Buffer.from(value, 'hex')
    : Buffer.from(value, 'base64');
  if (decoded.length !== 32)
    throw new Error('TOKEN_ENCRYPTION_KEY must decode to exactly 32 bytes');
  return decoded;
}

export function encryptToken(token: string, key: Buffer) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  const ciphertext = Buffer.concat([
    cipher.update(token, 'utf8'),
    cipher.final(),
  ]);
  return {
    ciphertext: ciphertext.toString('base64'),
    nonce: nonce.toString('base64'),
    authTag: cipher.getAuthTag().toString('base64'),
  };
}
export function decryptToken(
  value: { ciphertext: string; nonce: string; authTag: string },
  key: Buffer,
) {
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(value.nonce, 'base64'),
  );
  decipher.setAuthTag(Buffer.from(value.authTag, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(value.ciphertext, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}
