import 'dart:async';
import 'dart:io';

import '../http/http.dart';
import 'auth.dart';

/// Provides [AuthCodeController] with application-specific behavior.
abstract class AuthCodeControllerDelegate {
  /// Returns an HTML representation of a login form.
  ///
  /// Invoked when [AuthCodeController.getAuthorizationPage] is called in response to a GET request.
  /// Must provide HTML that will be returned to the browser for rendering. This form submission of this page
  /// should be a POST to [requestUri].
  ///
  /// The form submission should include the values of [responseType], [clientID], [state], [scope]
  /// as well as user-entered username and password in `x-www-form-urlencoded` data, e.g.
  ///
  ///         POST https://example.com/auth/code
  ///         Content-Type: application/x-www-form-urlencoded
  ///
  ///         response_type=code&client_id=com.aqueduct.app&state=o9u3jla&username=bob&password=password
  ///
  ///
  /// If not null, [scope] should also be included as an additional form parameter.
  Future<String> render(AuthCodeController forController, Uri requestUri, String responseType, String clientID,
      String state, String scope);
}

/// [Controller] for issuing OAuth 2.0 authorization codes.
///
/// This controller provides an endpoint for the creating an OAuth 2.0 authorization code. This authorization code
/// can be exchanged for an access token with an [AuthController]. This is known as the OAuth 2.0 'Authorization Code Grant' flow.
///
/// See operation methods [getAuthorizationPage] and [authorize] for more details.
///
/// Usage:
///
///       router
///         .route("/auth/code")
///         .link(() => new AuthCodeController(authServer));
///
class AuthCodeController extends RESTController {
  /// Creates a new instance of an [AuthCodeController].
  ///
  /// [authServer] is the required authorization server. If [delegate] is provided, this controller will return a login page for all GET requests.
  AuthCodeController(this.authServer, {this.delegate}) {
    acceptedContentTypes = [new ContentType("application", "x-www-form-urlencoded")];
  }

  /// A reference to the [AuthServer] used to grant authorization codes.
  final AuthServer authServer;

  /// A randomly generated value the client can use to verify the origin of the redirect.
  ///
  /// Clients must include this query parameter and verify that any redirects from this
  /// server have the same value for 'state' as passed in. This value is usually a randomly generated
  /// session identifier.
  @Bind.query("state")
  String state;

  /// Must be 'code'.
  @Bind.query("response_type")
  String responseType;

  /// The client ID of the authenticating client.
  ///
  /// This must be a valid client ID according to [authServer].
  @Bind.query("client_id")
  String clientID;

  /// Renders an HTML login form.
  final AuthCodeControllerDelegate delegate;

  /// Returns an HTML login form.
  ///
  /// A client that wishes to authenticate with this server should direct the user
  /// to this page. The user will enter their username and password that is sent as a POST
  /// request to this same controller.
  ///
  /// The 'client_id' must be a registered, valid client of this server. The client must also provide
  /// a [state] to this request and verify that the redirect contains the same value in its query string.
  @Operation.get()
  Future<Response> getAuthorizationPage({@Bind.query("scope") String scope}) async {
    if (delegate == null) {
      return new Response(405, {}, null);
    }

    var renderedPage = await delegate.render(this, request.raw.uri, responseType, clientID, state, scope);
    if (renderedPage == null) {
      return new Response.notFound();
    }

    return new Response.ok(renderedPage)..contentType = ContentType.HTML;
  }

  /// Creates a one-time use authorization code.
  ///
  /// This method will respond with a redirect that contains an authorization code ('code')
  /// and the passed in 'state'. If this request fails, the redirect URL
  /// will contain an 'error' key instead of the authorization code.
  ///
  /// This method is typically invoked by the login form returned from the GET to this controller.
  @Operation.post()
  Future<Response> authorize(
      {@Bind.query("username") String username,
      @Bind.query("password") String password,
      @Bind.query("scope") String scope}) async {
    var client = await authServer.clientForID(clientID);

    if (state == null) {
      var exception = new AuthServerException(AuthRequestError.invalidRequest, client);
      return _redirectResponse(null, null, error: exception);
    }

    if (responseType != "code") {
      if (client?.redirectURI == null) {
        return new Response.badRequest();
      }

      var exception = new AuthServerException(AuthRequestError.invalidRequest, client);
      return _redirectResponse(null, state, error: exception);
    }

    try {
      var scopes = scope?.split(" ")?.map((s) => new AuthScope(s))?.toList();

      var authCode = await authServer.authenticateForCode(username, password, clientID, requestedScopes: scopes);
      return _redirectResponse(client.redirectURI, state, code: authCode.code);
    } on FormatException {
      return _redirectResponse(null, state, error: new AuthServerException(AuthRequestError.invalidScope, client));
    } on AuthServerException catch (e) {
      return _redirectResponse(null, state, error: e);
    }
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
          ..description = "Missing one or more of: 'client_id', 'username', 'password'.",
        new APIResponse()
          ..statusCode = HttpStatus.UNAUTHORIZED
          ..description = "Not authorized",
      ]);
    }

    return responses;
  }

  @override
  void willSendResponse(Response resp) {
    if (resp.statusCode == 302) {
      var locationHeader = resp.headers[HttpHeaders.LOCATION];
      if (locationHeader != null && state != null) {
        resp.headers[HttpHeaders.LOCATION] = locationHeader;
      }
    }
  }

  static Response _redirectResponse(String uriString, String clientStateOrNull,
      {String code, AuthServerException error}) {
    uriString ??= error.client?.redirectURI;
    if (uriString == null) {
      return new Response.badRequest(body: {"error": error.reasonString});
    }

    var redirectURI = Uri.parse(uriString);
    Map<String, String> queryParameters = new Map.from(redirectURI.queryParameters);

    if (code != null) {
      queryParameters["code"] = code;
    }
    if (clientStateOrNull != null) {
      queryParameters["state"] = clientStateOrNull;
    }
    if (error != null) {
      queryParameters["error"] = error.reasonString;
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
          HttpHeaders.LOCATION: responseURI.toString(),
          HttpHeaders.CACHE_CONTROL: "no-store",
          HttpHeaders.PRAGMA: "no-cache"
        },
        null);
  }
}
