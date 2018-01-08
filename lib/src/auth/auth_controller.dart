import 'dart:async';
import 'dart:io';

import '../http/http.dart';
import 'auth.dart';

/// [Controller] for issuing and refreshing OAuth 2.0 access tokens.
///
/// This controller issues and refreshes access tokens. Access tokens are issued for valid username and password (resource owner password grant)
/// or for an authorization code (authorization code grant) from a [AuthCodeController].
///
/// See operation method [grant] for more details.
///
/// Usage:
///
///       router
///         .route("/auth/token")
///         .link(() => new AuthController(authServer));
///
class AuthController extends RESTController {
  /// Creates a new instance of an [AuthController].
  ///
  /// [authServer] is the required authorization server that grants tokens.
  AuthController(this.authServer) {
    acceptedContentTypes = [
      new ContentType("application", "x-www-form-urlencoded")
    ];
  }

  /// A reference to the [AuthServer] this controller uses to grant tokens.
  final AuthServer authServer;

  /// Required basic authentication Authorization header containing client ID and secret for the authenticating client.
  ///
  /// Requests must contain the client ID and client secret in the authorization header,
  /// using the basic authentication scheme. If the client is a public client - i.e., no client secret -
  /// the client secret is omitted from the Authorization header.
  ///
  /// Example: com.stablekernel.public is a public client. The Authorization header should be constructed
  /// as so:
  ///
  ///         Authorization: Basic base64("com.stablekernel.public:")
  ///
  /// Notice the trailing colon indicates that the client secret is the empty string.
  @Bind.header(HttpHeaders.AUTHORIZATION)
  String authHeader;

  final AuthorizationBasicParser _parser = new AuthorizationBasicParser();

  /// Creates or refreshes an authentication token.
  ///
  /// When grant_type is 'password', there must be username and password values.
  /// When grant_type is 'refresh_token', there must be a refresh_token value.
  /// When grant_type is 'authorization_code', there must be a authorization_code value.
  ///
  /// This endpoint requires client_id authentication. The Authorization header must
  /// include a valid Client ID and Secret in the Basic authorization scheme format.
  @Operation.post()
  Future<Response> grant(
      {@Bind.query("username") String username,
      @Bind.query("password") String password,
      @Bind.query("refresh_token") String refreshToken,
      @Bind.query("code") String authCode,
      @Bind.query("grant_type") String grantType,
      @Bind.query("scope") String scope}) async {
    AuthBasicCredentials basicRecord;
    try {
      basicRecord = _parser.parse(authHeader);
    } on AuthorizationParserException catch (_) {
      return _responseForError(AuthRequestError.invalidClient);
    }

    try {
      var scopes = scope
        ?.split(" ")
        ?.map((s) => new AuthScope(s))
        ?.toList();

      if (grantType == "password") {
        var token = await authServer.authenticate(
            username, password, basicRecord.username, basicRecord.password, requestedScopes: scopes);

        return AuthController.tokenResponse(token);
      } else if (grantType == "refresh_token") {
        var token = await authServer.refresh(
            refreshToken, basicRecord.username, basicRecord.password, requestedScopes: scopes);

        return AuthController.tokenResponse(token);
      } else if (grantType == "authorization_code") {
        if (scope != null) {
          return _responseForError(AuthRequestError.invalidRequest);
        }

        var token = await authServer.exchange(
            authCode, basicRecord.username, basicRecord.password);

        return AuthController.tokenResponse(token);
      } else if (grantType == null) {
        return _responseForError(AuthRequestError.invalidRequest);
      }
    } on FormatException {
      return _responseForError(AuthRequestError.invalidScope);
    } on AuthServerException catch (e) {
      return _responseForError(e.reason);
    }

    return _responseForError(AuthRequestError.unsupportedGrantType);
  }

  /// Transforms a [AuthToken] into a [Response] object with an RFC6749 compliant JSON token
  /// as the HTTP response body.
  static Response tokenResponse(AuthToken token) {
    return new Response(HttpStatus.OK,
        {"Cache-Control": "no-store", "Pragma": "no-cache"}, token.asMap());
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
        response.body = {
          "error":
              AuthServerException.errorString(AuthRequestError.invalidRequest)
        };
      }
    }
  }

  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext components, APIPath path) {
    final operations = super.documentOperations(components, path);

    operations.forEach((_, op) {
      op.security = [new APISecurityRequirement()..requirements = {
        "oauth2-client-authentication": []
      }];
    });

    return operations;
  }

  @override
  List<APIResponse> documentResponsesForOperation(APIOperation operation) {
    var responses = super.documentResponsesForOperation(operation);
    if (operation.id == APIOperation.idForMethod(this, #grant)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = "Successfully exchanged credentials for credentials"
          ..schema = new APISchemaObject(properties: {
            "access_token": new APISchemaObject.string(),
            "token_type": new APISchemaObject.string(),
            "expires_in": new APISchemaObject.int(),
            "refresh_token": new APISchemaObject.string()..required = false
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

  Response _responseForError(AuthRequestError error) {
    var errorString = AuthServerException.errorString(error);
    return new Response.badRequest(body: {"error": errorString});
  }
}
