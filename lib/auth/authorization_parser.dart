part of monadart;

abstract class AuthorizationFailable {
  Response errorResponse;
}

class AuthorizationBearerParser extends AuthorizationFailable {
  String bearerToken;

  AuthorizationBearerParser(String authorizationHeader) {
    errorResponse = parse(authorizationHeader);
  }

  Response parse(String authorizationHeader) {
    if (authorizationHeader == null) {
      return new Response.unauthorized(body: JSON.encode({"error": "No authorization header."}));
    }

    var matcher = new RegExp("Bearer (.*)");
    var match = matcher.firstMatch(authorizationHeader);
    if (match == null) {
      return new Response.badRequest(body: JSON.encode({"error": "Improper authorization header."}));
    }

    bearerToken = match[1];

    return null;
  }
}

class AuthorizationBasicParser extends AuthorizationFailable {
  String username;
  String password;

  AuthorizationBasicParser(String authorizationHeader) {
    errorResponse = parse(authorizationHeader);
  }

  Response parse(String authorizationHeader) {
    if (authorizationHeader == null) {
      return new Response.unauthorized(body: JSON.encode({"error": "No authorization header."}));
    }

    var matcher = new RegExp("Basic (.*)");
    var match = matcher.firstMatch(authorizationHeader);
    if (match == null) {
      return new Response.badRequest(body: JSON.encode({"error": "Improper authorization header."}));
    }

    var base64String = match[1];
    var decodedCredentials = null;
    try {
      decodedCredentials = new String.fromCharCodes(CryptoUtils.base64StringToBytes(base64String));
    } catch (e) {
      return new Response.badRequest(body: JSON.encode({"error": "Improper authorization header."}));
    }

    var splitCredentials = decodedCredentials.split(":");
    if (splitCredentials.length != 2) {
      return new Response.badRequest(body: JSON.encode({"error": "Improper client credentials."}));
    }

    username = splitCredentials.first;
    password = splitCredentials.last;

    return null;
  }
}
