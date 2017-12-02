import 'dart:async';
import 'dart:io';

import '../http/http.dart';
import 'auth.dart';

/// Interface for providing [AuthCodeController] with application-specific behavior.
abstract class AuthCodeControllerDelegate {
  /// Returns an HTML string for a login page.
  ///
  /// Invoked when [AuthCodeController.getAuthorizationPage] is called in response to a GET request.
  /// Must provide HTML that will be returned to the browser for rendering. This page must execute
  /// a POST request to the same endpoint, including the values of [responseType], [clientID], [state], [scope]
  /// as well as user-entered username and password.
  ///
  /// All four of [responseType], [clientID], [state] and [scope] are provided in the query parameters of the request
  /// that triggered this method. Only [scope] may be null; the other three are non-null.
  ///
  /// [requestUri] is the request [Uri] that triggered this page fetch.
  Future<String> render(AuthCodeController forController, Uri requestUri, String responseType, String clientID,
      String state, String scope);
}

/// [RESTController] for issuing OAuth 2.0 authorization codes.
///
/// This controller provides the necessary methods for issuing OAuth 2.0 authorization codes: returning
/// a HTML login form and issuing a request for an authorization code. The login form's submit
/// button should initiate the request for the authorization code.
///
/// This controller should be routed to by a pattern like `/auth/code`. It will respond to POST and GET HTTP methods.
/// Do not put an [Authorizer] in front of instances of this type. Example:
///
///       router.route("/auth/token").generate(() => new AuthCodeController(authServer));
///
///
/// See [getAuthorizationPage] (GET) and [authorize] (POST) for more details.
class AuthCodeController extends RESTController {
  /// Creates a new instance of an [AuthCodeController].
  ///
  /// An [AuthCodeController] requires an [AuthServer].
  ///
  /// By default, an [AuthCodeController] has only one [acceptedContentTypes]: 'application/x-www-form-urlencoded'.
  ///
  /// A GET request to this controller will return an HTML login page. This page is provided through [delegate]'s callback methods.
  /// This page should allow a user to submit their username and password via POST request to the same endpoint.  See [AuthCodeControllerDelegate.render] for more details.
  AuthCodeController(this.authServer, {this.delegate}) {
    acceptedContentTypes = [new ContentType("application", "x-www-form-urlencoded")];
  }

  /// A reference to the [AuthServer] this controller uses to grant authorization codes.
  AuthServer authServer;

  /// The state parameter a client uses to verify the origin of a redirect when receiving an authorization redirect.
  ///
  /// Clients must include this query parameter and verify that any redirects from this
  /// server have the same value for 'state' as passed in. This value is usually a randomly generated
  /// session identifier.
  @Bind.query("state")
  String state;

  /// The desired response type; must be 'code'.
  @Bind.query("response_type")
  String responseType;

  /// The client ID of the authenticating client.
  ///
  /// This must be a valid client ID according to [authServer].
  @Bind.query("client_id")
  String clientID;

  AuthCodeControllerDelegate delegate;

  /// Returns an HTML login form.
  ///
  /// A client that wishes to authenticate with this server should direct the user
  /// to this page. The user will enter their username and password, and upon successful
  /// authentication, the returned page will redirect the user back to the initial application.
  /// The redirect URL will contain a 'code' query parameter that the application can intercept
  /// and send to the route that exchanges authorization codes for tokens.
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
  /// This method is typically invoked by the login form returned from the GET to this path.
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
  List<APIOperation> documentOperations(PackagePathResolver resolver) {
    var ops = super.documentOperations(resolver);
    ops.forEach((op) {
      op.parameters.forEach((param) {
        if (param.name == "username" ||
            param.name == "password" ||
            param.name == "client_id" ||
            param.name == "response_type" ||
            param.name == "state") {
          param.required = true;
        } else {
          param.required = false;
        }
      });
    });

    ops.firstWhere((op) => op.method == "get").produces = [ContentType.HTML];

    return ops;
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
