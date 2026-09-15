// Dummy values so GoogleOAuthClient / SessionTokenService can construct
// during tests without real secrets. Tests that need Google behavior
// override the GOOGLE_AUTH_CLIENT provider instead of hitting the network.
process.env.GOOGLE_CLIENT_ID ??= 'test-google-client-id';
process.env.GOOGLE_CLIENT_SECRET ??= 'test-google-client-secret';
process.env.JWT_SESSION_SECRET ??= 'test-jwt-session-secret';
// spec05-colaboradores.md — both have code defaults (7 days / the dev
// placeholder URL), so these dummies mainly document that the app can boot
// without a real .env; tests that care about a specific value set it
// per-test via ConfigModule's overrideProvider or similar.
process.env.APP_INVITE_BASE_URL ??= 'https://memora.test/invite/{token}';
process.env.INVITATION_TTL_DAYS ??= '7';
// spec09-compartir-visor.md — has a code default (the dev placeholder URL),
// same reasoning as APP_INVITE_BASE_URL above.
process.env.APP_SHARE_BASE_URL ??= 'https://memora.test/s/{token}';
// spec10-nfc-qr.md — its own env var (NOT a reuse of APP_SHARE_BASE_URL,
// see memora-backend/README.md "NFC/QR (spec10-nfc-qr)" for why); same
// has-a-code-default reasoning as the others above.
process.env.APP_NFC_QR_BASE_URL ??= 'https://memora.test/n/{token}';
