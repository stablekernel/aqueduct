import 'dart:async';
import 'dart:io';

import '../http/http.dart';
import 'auth.dart';

typedef Future<String> _RenderAuthorizationPageFunction(
    AuthCodeController controller,
    Uri requestURI,
    Map<String, String> queryParameters);

/// [RequestController] for issuing OAuth 2.0 authorization codes.
///
/// This controller provides the necessary methods for issuing OAuth 2.0 authorization codes: returning
/// a HTML login form and issuing a request for an authorization code. The login form's submit
/// button should initiate the request for the authorization code.
///
/// See [getAuthorizationPage] and [authorize] for more details.
class AuthCodeController extends HTTPController {
  /// Creates a new instance of an [AuthCodeController].
  ///
  /// An [AuthCodeController] requires an [AuthServer] to carry out tasks.
  ///
  /// By default, an [AuthCodeController] has only one [acceptedContentTypes] - 'application/x-www-form-urlencoded'.
  AuthCodeController(this.authServer,
      {Future<String> renderAuthorizationPageHTML(AuthCodeController controller,
          Uri requestURI, Map<String, String> queryParameters)}) {
    acceptedContentTypes = [
      new ContentType("application", "x-www-form-urlencoded")
    ];
    responseContentType = ContentType.HTML;

    _renderFunction = renderAuthorizationPageHTML;
  }

  /// A reference to the [AuthServer] this controller uses to grant authorization codes.
  AuthServer authServer;

  /// The state parameter a client uses to verify the origin of a redirect when receiving an authorization redirect.
  ///
  /// Clients must include this query parameter and verify that any redirects from this
  /// server have the same value for 'state' as passed in. This value is usually a randomly generated
  /// session identifier.
  @HTTPQuery("state")
  String state;

  /// The desired response type; must be 'code'.
  @HTTPQuery("response_type")
  String responseType;

  /// The client ID of the authenticating client.
  ///
  /// This must be a valid client ID according to [authServer].
  @HTTPQuery("client_id")
  String clientID;

  _RenderAuthorizationPageFunction _renderFunction;

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
  @httpGet
  Future<Response> getAuthorizationPage(
      {@HTTPQuery("scope") String scope}) async {
    if (_renderFunction == null) {
      return new Response(405, {}, null);
    }

    var renderedPage = await _renderFunction(this, request.innerRequest.uri, {
      "response_type": responseType,
      "client_id": clientID,
      "state": state,
      "scope": scope
    });
    if (renderedPage == null) {
      return new Response.notFound();
    }

    return new Response.ok(renderedPage);
  }

  /// Creates a one-time use authorization code.
  ///
  /// This method will respond with a redirect that contains an authorization code ('code')
  /// and the passed in 'state'. If this request fails, the redirect URL
  /// will contain an 'error' key instead of the authorization code.
  ///
  /// This method is typically invoked by the login form returned from the GET to this path.
  @httpPost
  Future<Response> authorize(
      {@HTTPQuery("username") String username,
      @HTTPQuery("password") String password,
      @HTTPQuery("scope") String scope}) async {
    var client = await authServer.clientForID(clientID);

    if (responseType != "code") {
      if (clientID == null) {
        return new Response.badRequest();
      }

      if (client.redirectURI == null) {
        return new Response.badRequest();
      }

      var exception =
          new AuthServerException(AuthRequestError.invalidRequest, client);
      return _redirectResponse(null, state, error: exception);
    }

    try {
      var authCode = await authServer.authenticateForCode(
          username, password, clientID);
      return _redirectResponse(client.redirectURI, state, code: authCode.code);
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
            param.name == "response_type") {
          param.required = true;
        } else {
          param.required = false;
        }
      });
    });

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
          ..description =
              "Missing one or more of: 'client_id', 'username', 'password'.",
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
        locationHeader += "&state=${Uri.encodeQueryComponent(state)}";
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
    Map<String, String> queryParameters =
        new Map.from(redirectURI.queryParameters);

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
