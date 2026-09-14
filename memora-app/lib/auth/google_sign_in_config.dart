/// Web client ID, passed as `serverClientId` to Google Sign-In so the
/// serverAuthCode it produces is redeemable by memora-backend's
/// `POST /api/v1/auth/google`. Not a secret — see
/// specs/memora-app/spec02-login-google.md. Configurable per environment.
const String googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue:
      '677454923415-sjt01rvlh4of49p1ufvgoh1vi3b1i70m.apps.googleusercontent.com',
);

/// iOS client ID. Only meaningful on iOS, paired with the URL scheme
/// configured in ios/Runner/Info.plist. Not a secret.
const String googleIosClientId = String.fromEnvironment(
  'GOOGLE_IOS_CLIENT_ID',
  defaultValue:
      '677454923415-b3q3s2ku6qrik4j6fpki1qp97151n0o7.apps.googleusercontent.com',
);
