part of monadart;

class AuthController<ResourceOwner extends Authenticatable, TokenType extends Tokenizable> extends HttpController {
  static String get RoutePattern => "/auth/token";

  AuthenticationServer<ResourceOwner, TokenType> authenticationServer;

  AuthController(AuthenticationServer<ResourceOwner, TokenType> authServer) {
    authenticationServer = authServer;
    acceptedContentTypes = [new ContentType("application", "x-www-form-urlencoded")];
  }

  /// Creates or refreshes an authentication token.
  ///
  /// Content-Type must be application/x-www-form-urlencoded. (Query string in the body, e.g. username=bob&password=password)
  /// Values must be URL percent encoded by client.
  /// When grant_type is 'password', there must be username and password values.
  /// When grant_type is 'refresh', there must be a refresh_token value.
  @httpPost
  Future<Response> create({String grant_type, String username, String password, String refresh_token}) async {
    var authorizationHeader = request.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first;

    var rec = new AuthorizationBasicParser(authorizationHeader);
    if (grant_type == "password") {
      if (username == null || password == null) {
        return new Response.badRequest(body: {"error": "username and password required"});
      }

      var token = await authenticationServer.authenticate(username, password, rec.username, rec.password);
      return AuthController.tokenResponse(token);
    } else if (grant_type == "refresh") {
      if (refresh_token == null) {
        return new Response.badRequest(body: {"error": "missing refresh_token"});
      }

      var token = await authenticationServer.refresh(refresh_token, rec.username, rec.password);
      return AuthController.tokenResponse(token);
    }

    return new Response.badRequest(body: {"error": "invalid grant_type"});
  }

  static Response tokenResponse(Tokenizable token) {
    var jsonToken = {
      "access_token": token.accessToken,
      "token_type": token.type,
      "expires_in": token.expirationDate.difference(new DateTime.now().toUtc()).inSeconds,
      "refresh_token": token.refreshToken
    };
    return new Response(200, {"Cache-Control": "no-store", "Pragma": "no-cache"}, jsonToken);
  }
}
