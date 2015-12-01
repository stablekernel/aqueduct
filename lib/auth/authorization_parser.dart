part of monadart;

class AuthorizationBearerParser {
  String bearerToken;

  AuthorizationBearerParser(String authorizationHeader) {
    if (authorizationHeader == null) {
      throw new HttpResponseException(401, "No authorization header.");
    }

    var matcher = new RegExp("Bearer (.*)");
    var match = matcher.firstMatch(authorizationHeader);
    if (match == null) {
      throw new HttpResponseException(400, "Improper authorization header.");
    }

    bearerToken = match[1];
  }
}

class AuthorizationBasicParser {
  String username;
  String password;

  AuthorizationBasicParser(String authorizationHeader) {
    if (authorizationHeader == null) {
      throw new HttpResponseException(401, "No authorization header.");
    }

    var matcher = new RegExp("Basic (.*)");
    var match = matcher.firstMatch(authorizationHeader);
    if (match == null) {
      throw new HttpResponseException(400, "Improper authorization header.");
    }

    var base64String = match[1];
    var decodedCredentials = null;
    try {
      decodedCredentials = new String.fromCharCodes(CryptoUtils.base64StringToBytes(base64String));
    } catch (e) {
      throw new HttpResponseException(400, "Improper authorization header.");
    }

    var splitCredentials = decodedCredentials.split(":");
    if (splitCredentials.length != 2) {
      throw new HttpResponseException(400, "Improper client credentials.");
    }

    username = splitCredentials.first;
    password = splitCredentials.last;
  }
}
