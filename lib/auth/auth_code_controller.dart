part of aqueduct;

class AuthCodeController extends HTTPController {

  /// Creates a new instance of an [AuthCodeController].
  ///
  /// An [AuthController] requires an [AuthenticationServer], with the specified [ResourceOwner] and [TokenType] instance
  /// types. These types will be used when communicating with the [AuthenticationServer] for creating and refreshing
  /// authentication tokens.
  ///
  /// By default, an [AuthController] has only one [acceptedContentTypes] - 'application/x-www-form-urlencoded'.
  AuthCodeController(AuthenticationServer authServer) {
    authenticationServer = authServer;
    acceptedContentTypes = [new ContentType("application", "x-www-form-urlencoded")];
  }

  /// A reference to the [AuthenticationServer] this controller uses to grant tokens.
  AuthenticationServer authenticationServer;

  /// Creates a one-time use authorization code.
  ///
  /// Content-Type must be application/x-www-form-urlencoded. (Query string in the body, e.g. username=bob&password=password)
  /// Values must be URL percent encoded by client.
  /// If [state] is supplied, it will be returned in the response object as a way
  /// for the client to insure it is receiving a response from the expected endpoint.
  @httpPost
  Future<Response> authorize({String client_id, String username, String password, String state}) async {
    if (client_id == null || username == null || password == null) {
      return new Response.badRequest();
    }

    var authCode = await authenticationServer.createAuthCode(username, password, client_id);
    return AuthCodeController.authCodeResponse(authCode, state);
  }

  static Response authCodeResponse(Authorizable authCode, String clientState) {
    var redirectURI = Uri.parse(authCode.redirectURI);
    var queryParameters = new Map.from(redirectURI.queryParameters);
    queryParameters["code"] = authCode.code;
    if (clientState != null) {
      queryParameters["state"] = clientState;
    }

    var responseURI = new Uri(
        scheme: redirectURI.scheme,
        userInfo: redirectURI.userInfo,
        host: redirectURI.host,
        port: redirectURI.port,
        path: redirectURI.path,
        queryParameters: queryParameters
    );
    return new Response(HttpStatus.MOVED_TEMPORARILY, {"Location": responseURI.toString(), "Cache-Control": "no-store", "Pragma": "no-cache"}, null);
  }
}
