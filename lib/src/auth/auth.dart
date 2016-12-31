import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../utilities/pbkdf2.dart';
import 'objects.dart';

export 'auth_code_controller.dart';
export 'auth_controller.dart';
export 'authorization_server.dart';
export 'authorization_parser.dart';
export 'authorizer.dart';
export 'exceptions.dart';
export 'objects.dart';
export 'protocols.dart';

/// Exposes static utility methods for password, salt and API credential generation.
///
///
class AuthUtility {
  /// A utility method to generate a password hash using the PBKDF2 scheme.
  ///
  ///
  static String generatePasswordHash(String password, String salt,
      {int hashRounds: 1000, int hashLength: 32}) {
    var generator = new PBKDF2(hashAlgorithm: sha256);
    var key = generator.generateKey(password, salt, hashRounds, hashLength);

    return new Base64Encoder().convert(key);
  }

  /// A utility method to generate a random base64 salt.
  ///
  ///
  static String generateRandomSalt({int hashLength: 32}) {
    var random = new Random.secure();
    List<int> salt = [];
    for (var i = 0; i < hashLength; i++) {
      salt.add(random.nextInt(256));
    }

    return new Base64Encoder().convert(salt);
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
      {String redirectURI: null}) {
    if (secret == null) {
      if (redirectURI != null) {
        throw new AuthUtilityException(
            "Public API Clients cannot have a redirect URL");
      }
      return new AuthClient.withRedirectURI(clientID, null, null, redirectURI);
    }

    var salt = generateRandomSalt();
    var hashed = generatePasswordHash(secret, salt);

    return new AuthClient.withRedirectURI(clientID, hashed, salt, redirectURI);
  }
}

class AuthUtilityException implements Exception {
  AuthUtilityException(this.message);
  String message;
}
