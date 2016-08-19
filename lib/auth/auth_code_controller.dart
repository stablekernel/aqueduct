part of aqueduct;

class AuthCodeController extends HTTPController {

  /// Creates a new instance of an [AuthCodeController].
  ///
  /// An [AuthCodeController] requires an [AuthenticationServer], with the specified [ResourceOwner] and [AuthCodeType] instance
  /// types. These types will be used when communicating with the [AuthenticationServer] for creating and refreshing
  /// authentication tokens.
  ///
  /// By default, an [AuthCodeController] has only one [acceptedContentTypes] - 'application/x-www-form-urlencoded'.
  AuthCodeController(AuthenticationServer authServer) {
    authenticationServer = authServer;
    acceptedContentTypes = [new ContentType("application", "x-www-form-urlencoded")];
  }

  /// A reference to the [AuthenticationServer] this controller uses to grant authorization codes.
  AuthenticationServer authenticationServer;

  /// Creates a one-time use authorization code.
  ///
  /// Content-Type must be application/x-www-form-urlencoded. (Query string in the body, e.g. username=bob&password=password)
  /// Values must be URL percent encoded by client.
  /// The authorization code is returned as a query parameter in the resulting 302 response.
  /// If [state] is supplied, it will be returned in the query as a way
  /// for the client to ensure it is receiving a response from the expected endpoint.
  @httpPost
  Future<Response> authorize({
    @HTTPQuery.required("client_id") String clientID,
    @HTTPQuery.required("username") String username,
    @HTTPQuery.required("password") String password,
    @HTTPQuery.optional("state") String state
  }) async {
    var authCode = await authenticationServer.createAuthCode(username, password, clientID);
    return AuthCodeController.authCodeResponse(authCode, state);
  }

  static Response authCodeResponse(TokenExchangable authCode, String clientState) {
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

  @override
  List<APIResponse> documentResponsesForOperation(APIOperation operation) {
    if (operation.id == APIOperation.idForMethod(this, #authorize)) {
      return [
        new APIResponse()
          ..statusCode = HttpStatus.MOVED_TEMPORARILY
          ..description = "Successfully issued an authorization code.",
        new APIResponse()
          ..statusCode = HttpStatus.BAD_REQUEST
          ..description = "Missing one or more of: 'client_id', 'username', 'password'.",
        new APIResponse()
          ..key = "default"
          ..description = "Something went wrong",
      ];
    }

    return null;
  }
}
