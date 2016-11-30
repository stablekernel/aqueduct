import 'dart:async';
import 'dart:io';

import '../http/http.dart';
import 'auth.dart';

/// [RequestController] for issuing OAuth 2.0 authorization codes.
///
/// Requests to this controller should come from a login form hosted by the authorization server.
/// A client will navigate to a page that hosts the login form, including a client_id, response_type and state
/// in the query string. (The query string may optionally contain a scope parameter, where each requested scope
/// is separated by a URL percent encoded space.)
///
/// The form submission should combine the parameters from the query string
/// and the submitted username and password into a single query string. This controller responds to
/// the form submission request, which must be a POST.
///
/// The implementation of this form page is up to the discretion of the developer. This controller
/// provides no mechanism for providing the page.
///
/// The request handled by this controller will redirect the client back to its registered redirection URI, including the initial state query
/// parameter and an authorization code. The authorization code can be exchanged for an access token with a request to a
/// [AuthController].
class AuthCodeController extends HTTPController {
  /// Creates a new instance of an [AuthCodeController].
  ///
  /// An [AuthCodeController] requires an [AuthServer] to carry out tasks.
  ///
  /// By default, an [AuthCodeController] has only one [acceptedContentTypes] - 'application/x-www-form-urlencoded'.
  AuthCodeController(this.authenticationServer) {
    acceptedContentTypes = [
      new ContentType("application", "x-www-form-urlencoded")
    ];
  }

  /// A reference to the [AuthServer] this controller uses to grant authorization codes.
  AuthServer authenticationServer;

  /// Creates a one-time use authorization code.
  ///
  /// The authorization code is returned as a query parameter in the resulting 302 response.
  /// If [state] is supplied, it will be returned in the query as a way
  /// for the client to ensure it is receiving a response from the expected endpoint.
  @httpPost
  Future<Response> authorize(
      @HTTPQuery("client_id") String clientID,
      @HTTPQuery("username") String username,
      @HTTPQuery("password") String password,
      {@HTTPQuery("state") String state}) async {
    var authCode =
        await authenticationServer.createAuthCode(username, password, clientID);
    return AuthCodeController.authCodeResponse(authCode, state);
  }

  static Response authCodeResponse(
      AuthTokenExchangable authCode, String clientState) {
    var redirectURI = Uri.parse(authCode.redirectURI);
    Map<String, String> queryParameters =
        new Map.from(redirectURI.queryParameters);
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
        queryParameters: queryParameters);
    return new Response(
        HttpStatus.MOVED_TEMPORARILY,
        {
          "Location": responseURI.toString(),
          "Cache-Control": "no-store",
          "Pragma": "no-cache"
        },
        null);
  }

  @override
  List<APIResponse> documentResponsesForOperation(APIOperation operation) {
    var responses = super.documentResponsesForOperation(operation);
    if (operation.id == APIOperation.idForMethod(this, #authorize)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.MOVED_TEMPORARILY
          ..description = "Successfully issued an authorization code.",
        new APIResponse()
          ..statusCode = HttpStatus.BAD_REQUEST
          ..description =
              "Missing one or more of: 'client_id', 'username', 'password'.",
        new APIResponse()
          ..statusCode = HttpStatus.UNAUTHORIZED
          ..description = "Not authorized",
      ]);
    }

    return responses;
  }
}
