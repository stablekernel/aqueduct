part of aqueduct;

class AuthController extends HTTPController {

  /// Creates a new instance of an [AuthController].
  ///
  /// An [AuthController] requires an [AuthenticationServer], with the specified [ResourceOwner] and [TokenType] instance
  /// types. These types will be used when communicating with the [AuthenticationServer] for creating and refreshing
  /// authentication tokens.
  ///
  /// By default, an [AuthController] has only one [acceptedContentTypes] - 'application/x-www-form-urlencoded'.
  AuthController(AuthenticationServer authServer) {
    authenticationServer = authServer;
    acceptedContentTypes = [new ContentType("application", "x-www-form-urlencoded")];
  }

  /// A reference to the [AuthenticationServer] this controller uses to grant tokens.
  AuthenticationServer authenticationServer;

  /// Creates or refreshes an authentication token.
  ///
  /// Authorization header must contain Basic authorization scheme where username is Client ID and password is Client Secret,
  /// e.g. Authorization: Basic base64(ClientID:ClientSecret)
  /// Content-Type must be application/x-www-form-urlencoded. (Query string in the body, e.g. username=bob&password=password)
  /// Values must be URL percent encoded by client.
  /// When grant_type is 'password', there must be username and password values.
  /// When grant_type is 'refresh', there must be a refresh_token value.
  @httpPost
  Future<Response> create({String grant_type, String username, String password, String refresh_token, String authorization_code}) async {
    var authorizationHeader = request.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first;

    var basicRecord = AuthorizationBasicParser.parse(authorizationHeader);
    if (grant_type == "password") {
      if (username == null || password == null) {
        return new Response.badRequest(body: {"error": "username and password required"});
      }

      var token = await authenticationServer.authenticate(username, password, basicRecord.username, basicRecord.password);
      return AuthController.tokenResponse(token);
    } else if (grant_type == "refresh") {
      if (refresh_token == null) {
        return new Response.badRequest(body: {"error": "missing refresh_token"});
      }

      var token = await authenticationServer.refresh(refresh_token, basicRecord.username, basicRecord.password);
      return AuthController.tokenResponse(token);
    } else if (grant_type == "authorization_code") {
      if (authorization_code == null) {
        return new Response.badRequest(body: {"error": "missing authorization_code"});
      }

      var token = await authenticationServer.exchange(authorization_code, basicRecord.username, basicRecord.password);
      return AuthController.tokenResponse(token);
    }

    return new Response.badRequest(body: {"error": "invalid grant_type"});
  }

  /// Transforms a [Tokenizable] into a [Response] object with an RFC6749 compliant JSON token
  /// as the HTTP response body.
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
