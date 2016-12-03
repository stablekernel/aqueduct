import 'dart:async';
import 'dart:io';

import '../http/http.dart';
import 'auth.dart';

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
  @HTTPHeader(HttpHeaders.AUTHORIZATION)
  String authHeader;

  /// Creates or refreshes an authentication token.
  ///
  /// When grant_type is 'password', there must be username and password values.
  /// When grant_type is 'refresh_token', there must be a refresh_token value.
  /// When grant_type is 'authorization_code', there must be a authorization_code value.
  ///
  /// This endpoint requires client authentication. The Authorization header must
  /// include a valid Client ID and Secret in the Basic authorization scheme format.
  ///
  /// Do not put an [Authorizer] in front of this endpoint, as it will not allow
  /// authorization of public clients.
  @httpPost
  Future<Response> create(
      {@HTTPQuery("username") List<String> usernames,
      @HTTPQuery("password") List<String> passwords,
      @HTTPQuery("refresh_token") List<String> refreshTokens,
      @HTTPQuery("code") List<String> authCodes,
      @HTTPQuery("grant_type") List<String> grantTypes}) async {
    AuthorizationBasicElements basicRecord;
    try {
      basicRecord = AuthorizationBasicParser.parse(authHeader);
    } on AuthorizationParserException catch (_) {
      return new Response.badRequest(body: {"error": "invalid_client"});
    }

    var grantType = _ensureOneAndReturnElseThrow(grantTypes);

    if (grantType == "password") {
      var token = await authenticationServer.authenticate(
          _ensureOneAndReturnElseThrow(usernames),
          _ensureOneAndReturnElseThrow(passwords),
          basicRecord.username, basicRecord.password);

      return AuthController.tokenResponse(token);
    } else if (grantType == "refresh_token") {
      var token = await authenticationServer.refresh(
          _ensureOneAndReturnElseThrow(refreshTokens),
          basicRecord.username, basicRecord.password);

      return AuthController.tokenResponse(token);
    } else if (grantType == "authorization_code") {
      var token = await authenticationServer.exchange(
          _ensureOneAndReturnElseThrow(authCodes),
          basicRecord.username, basicRecord.password);

      return AuthController.tokenResponse(token);
    }

    return new Response.badRequest(body: {"error": "unsupported_grant_type"});
  }

  /// Transforms a [AuthTokenizable] into a [Response] object with an RFC6749 compliant JSON token
  /// as the HTTP response body.
  static Response tokenResponse(AuthTokenizable token) {
    var jsonToken = {
      "access_token": token.accessToken,
      "token_type": token.type,
      "expires_in":
          token.expirationDate.difference(new DateTime.now().toUtc()).inSeconds,
    };

    if (token.refreshToken != null) {
      jsonToken["refresh_token"] = token.refreshToken;
    }

    return new Response(
        HttpStatus.OK, {"Cache-Control": "no-store", "Pragma": "no-cache"}, jsonToken);
  }

  String _ensureOneAndReturnElseThrow(List<String> items) {
    if (items == null || items.length > 1 || items.isEmpty) {
      throw new HTTPResponseException(HttpStatus.BAD_REQUEST, "invalid_request");
    }

    var first = items.first;
    if (first == "") {
      throw new HTTPResponseException(HttpStatus.BAD_REQUEST, "invalid_request");
    }

    return first;
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
