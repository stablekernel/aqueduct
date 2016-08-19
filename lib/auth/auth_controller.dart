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

  @HTTPHeader.required(HttpHeaders.AUTHORIZATION) String authHeader;
  @HTTPQuery.required("grant_type") String grantType;

  /// Creates or refreshes an authentication token.
  ///
  /// Authorization header must contain Basic authorization scheme where username is Client ID and password is Client Secret,
  /// e.g. Authorization: Basic base64(ClientID:ClientSecret)
  /// Content-Type must be application/x-www-form-urlencoded. (Query string in the body, e.g. username=bob&password=password)
  /// Values must be URL percent encoded by client.
  /// When grant_type is 'password', there must be username and password values.
  /// When grant_type is 'refresh', there must be a refresh_token value.
  /// When grant_type is 'authorization_code', there must be a authorization_code value.
  @httpPost
  Future<Response> create({
    @HTTPQuery.optional("username") String username,
    @HTTPQuery.optional("password") String password,
    @HTTPQuery.optional("refresh_token") String refreshToken,
    @HTTPQuery.optional("authorization_code") String authCode
  }) async {
    var basicRecord = AuthorizationBasicParser.parse(authHeader);
    if (grantType == "password") {
      if (username == null || password == null) {
        return new Response.badRequest(body: {"error": "username and password required"});
      }

      var token = await authenticationServer.authenticate(username, password, basicRecord.username, basicRecord.password);
      return AuthController.tokenResponse(token);
    } else if (grantType == "refresh") {
      if (refreshToken == null) {
        return new Response.badRequest(body: {"error": "missing refresh_token"});
      }

      var token = await authenticationServer.refresh(refreshToken, basicRecord.username, basicRecord.password);
      return AuthController.tokenResponse(token);
    } else if (grantType == "authorization_code") {
      if (authCode == null) {
        return new Response.badRequest(body: {"error": "missing authorization_code"});
      }

      var token = await authenticationServer.exchange(authCode, basicRecord.username, basicRecord.password);
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

  @override
  List<APIResponse> documentResponsesForOperation(APIOperation operation) {
    if (operation.id == APIOperation.idForMethod(this, #create)) {
      return [
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = "Successfully exchanged credentials for credentials"
          ..schema = (new APISchemaObject()
            ..type = APISchemaObjectTypeObject
            ..properties = {
              "access_token" : new APISchemaObject()..type = APISchemaObjectTypeString,
              "token_type" : new APISchemaObject()..type = APISchemaObjectTypeString,
              "expires_in" : new APISchemaObject()..type = APISchemaObjectTypeInteger ..format = APISchemaObjectFormatInt32,
              "refresh_token" : new APISchemaObject()..type = APISchemaObjectTypeString
            }
          ),
        new APIResponse()
          ..statusCode = HttpStatus.BAD_REQUEST
          ..description = "Missing one or more of: 'client_id', 'username', 'password'."
          ..schema = (new APISchemaObject()
            ..type = APISchemaObjectTypeObject
            ..properties = {
              "error" : new APISchemaObject()..type = APISchemaObjectTypeString
            }
          ),
        new APIResponse()
          ..key = "default"
          ..description = "Something went wrong",
      ];
    }

    return null;
  }
}
