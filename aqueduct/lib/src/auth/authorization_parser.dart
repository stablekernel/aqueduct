import 'dart:convert';

abstract class AuthorizationParser<T> {
  const AuthorizationParser();

  T parse(String authorizationHeader);
}

/// Parses a Bearer token from an Authorization header.
class AuthorizationBearerParser extends AuthorizationParser<String> {
  const AuthorizationBearerParser();

  /// Parses a Bearer token from [authorizationHeader]. If the header is malformed or doesn't exist,
  /// throws an [AuthorizationParserException]. Otherwise, returns the [String] representation of the bearer token.
  ///
  /// For example, if the input to this method is "Bearer token" it would return 'token'.
  ///
  /// If [authorizationHeader] is malformed or null, throws an [AuthorizationParserException].
  @override
  String parse(String authorizationHeader) {
    if (authorizationHeader == null) {
      throw AuthorizationParserException(
          AuthorizationParserExceptionReason.missing);
    }

    final matcher = RegExp("Bearer (.+)");
    final match = matcher.firstMatch(authorizationHeader);
    if (match == null) {
      throw AuthorizationParserException(
          AuthorizationParserExceptionReason.malformed);
    }
    return match[1];
  }
}

/// A structure to hold Basic authorization credentials.
///
/// See [AuthorizationBasicParser] for getting instances of this type.
class AuthBasicCredentials {
  /// The username of a Basic Authorization header.
  String username;

  /// The password of a Basic Authorization header.
  String password;

  @override
  String toString() => "$username:$password";
}

/// Parses a Basic Authorization header.
class AuthorizationBasicParser
    extends AuthorizationParser<AuthBasicCredentials> {
  const AuthorizationBasicParser();

  /// Returns a [AuthBasicCredentials] containing the username and password
  /// base64 encoded in [authorizationHeader]. For example, if the input to this method
  /// was 'Basic base64String' it would decode the base64String
  /// and return the username and password by splitting that decoded string around the character ':'.
  ///
  /// If [authorizationHeader] is malformed or null, throws an [AuthorizationParserException].
  @override
  AuthBasicCredentials parse(String authorizationHeader) {
    if (authorizationHeader == null) {
      throw AuthorizationParserException(
          AuthorizationParserExceptionReason.missing);
    }

    final matcher = RegExp("Basic (.+)");
    final match = matcher.firstMatch(authorizationHeader);
    if (match == null) {
      throw AuthorizationParserException(
          AuthorizationParserExceptionReason.malformed);
    }

    final base64String = match[1];
    String decodedCredentials;
    try {
      decodedCredentials =
          String.fromCharCodes(const Base64Decoder().convert(base64String));
    } catch (e) {
      throw AuthorizationParserException(
          AuthorizationParserExceptionReason.malformed);
    }

    final splitCredentials = decodedCredentials.split(":");
    if (splitCredentials.length != 2) {
      throw AuthorizationParserException(
          AuthorizationParserExceptionReason.malformed);
    }

    return AuthBasicCredentials()
      ..username = splitCredentials.first
      ..password = splitCredentials.last;
  }
}

/// The reason either [AuthorizationBearerParser] or [AuthorizationBasicParser] failed.
enum AuthorizationParserExceptionReason { missing, malformed }

/// An exception indicating why Authorization parsing failed.
class AuthorizationParserException implements Exception {
  AuthorizationParserException(this.reason);

  AuthorizationParserExceptionReason reason;
}
