part of monadart;

class AuthController<ResourceOwner extends Authenticatable, TokenType extends Tokenizable> extends HttpController {
  static String get RoutePattern => "/auth/token/[refresh]";

  AuthenticationServer<ResourceOwner, TokenType> authenticationServer;

  AuthController(AuthenticationServer<ResourceOwner, TokenType> authServer) {
    authenticationServer = authServer;
    acceptedContentTypes = [new ContentType("application", "x-www-form-urlencoded")];
  }

  @httpPost
  Future<Response> refreshToken(String _) async {
    var authorizationHeader = request.innerRequest.headers[HttpHeaders
        .AUTHORIZATION]?.first;

    var rec = new AuthorizationBasicParser(authorizationHeader);
    if (rec.errorResponse != null) {
      return rec.errorResponse;
    }

    var grantType = requestBody["grant_type"];
    if (grantType != "refresh_token") {
      return new Response.badRequest(body: {"error" : "grant_type must be refresh_token"});
    }

    var refreshToken = requestBody["refresh_token"];
    var token = await authenticationServer.refresh(refreshToken, rec.username, rec.password);

    return AuthController.tokenResponse(token);
  }

  @httpPost
  Future<Response> createToken() async {
    var authorizationHeader = request.innerRequest.headers[HttpHeaders
        .AUTHORIZATION]?.first;

    var rec = new AuthorizationBasicParser(authorizationHeader);
    if (rec.errorResponse != null) {
      return rec.errorResponse;
    }

    if (requestBody["grant_type"] != "password") {
      return new Response.badRequest(body: {"error" : "grant_type must be password"});
    }

    var username = requestBody["username"];
    var password = requestBody["password"];
    if (username == null || password == null) {
      return new Response.badRequest(body: {"error" : "username and password required"});
    }

    var token = await authenticationServer.authenticate(
        username, password, rec.username, rec.password);

    return AuthController.tokenResponse(token);
  }

  static Response tokenResponse(Tokenizable token) {
    var jsonToken = {
      "access_token" : token.accessToken,
      "token_type" : token.type,
      "expires_in" : token.expirationDate.difference(new DateTime.now().toUtc()).inSeconds,
      "refresh_token" : token.refreshToken
    };
    return new Response(200, {"Cache-Control" : "no-store", "Pragma" : "no-cache"}, jsonToken);
  }
}