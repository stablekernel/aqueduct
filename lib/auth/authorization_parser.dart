part of aqueduct;

/// Parses a Bearer token in an Authorization header.
class AuthorizationBearerParser {

  /// Parses a Bearer token from [authorizationHeader]. If the header is malformed or doesn't exist,
  /// throws an [HTTPResponseException]. Otherwise, returns the [String] representation of the bearer token.
  /// For example, if the input to this method is "Authorization: Bearer token" it would return 'token'.
  static String parse(String authorizationHeader) {
    if (authorizationHeader == null) {
      throw new HTTPResponseException(401, "No authorization header.");
    }

    var matcher = new RegExp("Bearer (.*)");
    var match = matcher.firstMatch(authorizationHeader);
    if (match == null) {
      throw new HTTPResponseException(400, "Improper authorization header.");
    }
    return match[1];
  }
}

/// A container for Basic authorization elements.
class AuthorizationBasicElements {

  /// The username of a Basic Authorization header.
  String username;

  /// The password of a Basic Authorization header.
  String password;
}

/// Parses a Basic Authorization header.
class AuthorizationBasicParser {
  /// Returns a [AuthorizationBasicElements] containing the username and password
  /// base64 encoded in [authorizationHeader]. For example, if the input to this method
  /// was 'Authorization: Basic base64String' it would decode the base64String,
  /// and return the username and password by splitting that decoded string around the character ':'.
  static AuthorizationBasicElements parse(String authorizationHeader) {
    if (authorizationHeader == null) {
      throw new HTTPResponseException(401, "No authorization header.");
    }

    var matcher = new RegExp("Basic (.*)");
    var match = matcher.firstMatch(authorizationHeader);
    if (match == null) {
      throw new HTTPResponseException(400, "Improper authorization header.");
    }

    var base64String = match[1];
    var decodedCredentials = null;
    try {
      decodedCredentials = new String.fromCharCodes(new Base64Decoder().convert(base64String));
    } catch (e) {
      throw new HTTPResponseException(400, "Improper authorization header.");
    }

    var splitCredentials = decodedCredentials.split(":");
    if (splitCredentials.length != 2) {
      throw new HTTPResponseException(400, "Improper client credentials.");
    }

    return new AuthorizationBasicElements()
        ..username = splitCredentials.first
        ..password = splitCredentials.last;
  }
}
