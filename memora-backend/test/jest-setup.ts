// Dummy values so GoogleOAuthClient / SessionTokenService can construct
// during tests without real secrets. Tests that need Google behavior
// override the GOOGLE_AUTH_CLIENT provider instead of hitting the network.
process.env.GOOGLE_CLIENT_ID ??= 'test-google-client-id';
process.env.GOOGLE_CLIENT_SECRET ??= 'test-google-client-secret';
process.env.JWT_SESSION_SECRET ??= 'test-jwt-session-secret';
