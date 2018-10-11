import 'package:crypto/crypto.dart';
import 'package:password_hash/password_hash.dart';

import 'objects.dart';

export 'auth_code_controller.dart';
export 'auth_controller.dart';
export 'auth_redirect_controller.dart';
export 'authorization_parser.dart';
export 'authorization_server.dart';
export 'authorizer.dart';
export 'exceptions.dart';
export 'objects.dart';
export 'protocols.dart';
export 'validator.dart';

/// Exposes static utility methods for password, salt and API credential generation.
///
/// Use the `aqueduct auth` tool to generate API credentials.
class AuthUtility {
  /// A utility method to generate a password hash using the PBKDF2 scheme.
  ///
  ///
  static String generatePasswordHash(String password, String salt,
      {int hashRounds = 1000, int hashLength = 32, Hash hashFunction}) {
    final generator = PBKDF2(hashAlgorithm: hashFunction ?? sha256);
    return generator.generateBase64Key(password, salt, hashRounds, hashLength);
  }

  /// A utility method to generate a random base64 salt.
  ///
  ///
  static String generateRandomSalt({int hashLength = 32}) {
    return Salt.generateAsBase64String(hashLength);
  }

  /// A utility method to generate a ClientID and Client Secret Pair.
  ///
  /// [secret] may be null. If secret is null, the return value is a 'public' client. Otherwise, the
  /// client is 'confidential'. Public clients must not include a client secret when sent to the
  /// authorization server. Confidential clients must include the secret in all requests. Use public clients when
  /// the source code of the client application is visible, i.e. a JavaScript browser application.
  ///
  /// Any client that allows the authorization code flow must include [redirectURI].
  ///
  /// Note that [secret] is hashed with a randomly generated salt, and therefore cannot be retrieved
  /// later. The plain-text secret must be stored securely elsewhere.
  static AuthClient generateAPICredentialPair(String clientID, String secret,
      {String redirectURI,
      int hashLength = 32,
      int hashRounds = 1000,
      Hash hashFunction}) {
    if (secret == null) {
      return AuthClient.withRedirectURI(clientID, null, null, redirectURI);
    }

    final salt = generateRandomSalt(hashLength: hashLength);
    final hashed = generatePasswordHash(secret, salt,
        hashRounds: hashRounds,
        hashLength: hashLength,
        hashFunction: hashFunction);

    return AuthClient.withRedirectURI(clientID, hashed, salt, redirectURI);
  }
}

class AuthUtilityException implements Exception {
  AuthUtilityException(this.message);
  String message;
}
