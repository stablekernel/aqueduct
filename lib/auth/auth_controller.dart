part of aqueduct;

/// [RequestController] for issuing OAuth 2.0 authorization tokens.
class AuthController extends HTTPController {
  /// Creates a new instance of an [AuthController].
  ///
  /// An [AuthController] requires an [AuthServer] to carry out tasks.
  /// By default, an [AuthController] has only one [acceptedContentTypes] - 'application/x-www-form-urlencoded'.
  AuthController(this.authenticationServer) {
    acceptedContentTypes = [
      new ContentType("application", "x-www-form-urlencoded")
    ];
  }

  /// A reference to the [AuthServer] this controller uses to grant tokens.
  AuthServer authenticationServer;

  /// Required basic authorization header containing client ID and secret for the authenticating client.
  @requiredHTTPParameter
  @HTTPHeader(HttpHeaders.AUTHORIZATION)
  String authHeader;

  /// The type of token to request.
  ///
  /// Valid options are 'password', 'refresh_token' and 'authorization_code'.
  @requiredHTTPParameter
  @HTTPQuery("grant_type")
  String grantType;

  /// Creates or refreshes an authentication token.
  ///
  /// When grant_type is 'password', there must be username and password values.
  /// When grant_type is 'refresh_token', there must be a refresh_token value.
  /// When grant_type is 'authorization_code', there must be a authorization_code value.
  @httpPost
  Future<Response> create(
      {@HTTPQuery("username") String username,
      @HTTPQuery("password") String password,
      @HTTPQuery("refresh_token") String refreshToken,
      @HTTPQuery("authorization_code") String authCode}) async {
    var basicRecord = AuthorizationBasicParser.parse(authHeader);
    if (grantType == "password") {
      if (username == null || password == null) {
        return new Response.badRequest(
            body: {"error": "username and password required"});
      }

      var token = await authenticationServer.authenticate(
          username, password, basicRecord.username, basicRecord.password);
      return AuthController.tokenResponse(token);
    } else if (grantType == "refresh_token") {
      if (refreshToken == null) {
        return new Response.badRequest(
            body: {"error": "missing refresh_token"});
      }

      var token = await authenticationServer.refresh(
          refreshToken, basicRecord.username, basicRecord.password);
      return AuthController.tokenResponse(token);
    } else if (grantType == "authorization_code") {
      if (authCode == null) {
        return new Response.badRequest(
            body: {"error": "missing authorization_code"});
      }

      var token = await authenticationServer.exchange(
          authCode, basicRecord.username, basicRecord.password);
      return AuthController.tokenResponse(token);
    }

    return new Response.badRequest(body: {"error": "invalid grant_type"});
  }

  /// Transforms a [AuthTokenizable] into a [Response] object with an RFC6749 compliant JSON token
  /// as the HTTP response body.
  static Response tokenResponse(AuthTokenizable token) {
    var jsonToken = {
      "access_token": token.accessToken,
      "token_type": token.type,
      "expires_in":
          token.expirationDate.difference(new DateTime.now().toUtc()).inSeconds,
      "refresh_token": token.refreshToken
    };
    return new Response(
        200, {"Cache-Control": "no-store", "Pragma": "no-cache"}, jsonToken);
  }

  @override
  List<APIResponse> documentResponsesForOperation(APIOperation operation) {
    var responses = super.documentResponsesForOperation(operation);
    if (operation.id == APIOperation.idForMethod(this, #create)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = "Successfully exchanged credentials for credentials"
          ..schema = new APISchemaObject(properties: {
            "access_token": new APISchemaObject.string(),
            "token_type": new APISchemaObject.string(),
            "expires_in": new APISchemaObject.int(),
            "refresh_token": new APISchemaObject.string()
          }),
        new APIResponse()
          ..statusCode = HttpStatus.BAD_REQUEST
          ..description =
              "Missing one or more of: 'client_id', 'username', 'password'."
          ..schema = new APISchemaObject(
              properties: {"error": new APISchemaObject.string()}),
      ]);
    }

    return responses;
  }
}
