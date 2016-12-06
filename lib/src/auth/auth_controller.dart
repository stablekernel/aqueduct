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
      {@HTTPQuery("username") String username,
      @HTTPQuery("password") String password,
      @HTTPQuery("refresh_token") String refreshToken,
      @HTTPQuery("code") String authCode,
      @HTTPQuery("grant_type") String grantType}) async {
    AuthorizationBasicElements basicRecord;
    try {
      basicRecord = AuthorizationBasicParser.parse(authHeader);
    } on AuthorizationParserException catch (_) {
      return AuthServerException.responseForError(AuthRequestError.invalidClient);
    }

    try {
      if (grantType == "password") {
        var token = await authenticationServer.authenticate(
            username, password, basicRecord.username, basicRecord.password);

        return AuthController.tokenResponse(token);
      } else if (grantType == "refresh_token") {
        var token = await authenticationServer.refresh(
            refreshToken, basicRecord.username, basicRecord.password);

        return AuthController.tokenResponse(token);
      } else if (grantType == "authorization_code") {
        var token = await authenticationServer.exchange(
            authCode, basicRecord.username, basicRecord.password);

        return AuthController.tokenResponse(token);
      } else if (grantType == null) {
        return AuthServerException.responseForError(AuthRequestError.invalidRequest);
      }
    } on AuthServerException catch (e) {
      return e.directResponse;
    }

    return AuthServerException.responseForError(AuthRequestError.unsupportedGrantType);
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

    return new Response(HttpStatus.OK,
        {"Cache-Control": "no-store", "Pragma": "no-cache"}, jsonToken);
  }

  @override
  void willSendResponse(Response response) {
    if (response.statusCode == 400) {
      if (response.body != null &&
          response.body["error"] ==
              "Duplicate parameter for non-List parameter type") {
        // This post-processes the response in the case that duplicate parameters
        // were in the request, which violates oauth2 spec. It just adjusts the error message.
        // This could be hardened some.
        response.body = {"error": AuthServerException.errorStringFromRequestError(AuthRequestError.invalidRequest)};
      }
    }
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
