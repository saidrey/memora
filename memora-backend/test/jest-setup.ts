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
