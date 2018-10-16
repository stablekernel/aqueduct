import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/openapi/openapi.dart';

import '../http/http.dart';
import 'auth.dart';

/// Provides [AuthRedirectController] with application-specific behavior.
abstract class AuthRedirectControllerDelegate {
  /// Returns an HTML representation of a login form.
  ///
  /// Invoked when [AuthRedirectController.getAuthorizationPage] is called in response to a GET request.
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
  Future<String> render(AuthRedirectController forController, Uri requestUri,
      String responseType, String clientID, String state, String scope);
}

/// [Controller] for issuing OAuth 2.0 authorization codes and tokens.
///
/// This controller provides an endpoint for creating an OAuth 2.0 authorization code or access token. An authorization code
/// can be exchanged for an access token with an [AuthController]. This is known as the OAuth 2.0 'Authorization Code Grant' flow.
/// Returning an access token is known as the OAuth 2.0 'Implicit Grant' flow.
///
/// See operation methods [getAuthorizationPage] and [authorize] for more details.
///
/// Usage:
///
///       router
///         .route("/auth/code")
///         .link(() => new AuthRedirectController(authServer));
///
class AuthRedirectController extends ResourceController {
  /// Creates a new instance of an [AuthRedirectController].
  ///
  /// [authServer] is the required authorization server. If [delegate] is provided, this controller will return a login page for all GET requests.
  AuthRedirectController(this.authServer, {this.delegate, this.allowsImplicit = true}) {
    acceptedContentTypes = [
      ContentType("application", "x-www-form-urlencoded")
    ];
  }

  static Response _unsupportedResponseTypeResponse = Response.badRequest(body: "<h1>Error</h1><p>unsupported_response_type</p>")..contentType = ContentType.html;

  /// A reference to the [AuthServer] used to grant authorization codes and access tokens.
  final AuthServer authServer;

  /// When true, the controller allows for the Implicit Grant Flow
  final bool allowsImplicit;

  /// A randomly generated value the client can use to verify the origin of the redirect.
  ///
  /// Clients must include this query parameter and verify that any redirects from this
  /// server have the same value for 'state' as passed in. This value is usually a randomly generated
  /// session identifier.
  @Bind.query("state")
  String state;

  /// Must be 'code' or 'token'.
  @Bind.query("response_type")
  String responseType;

  /// The client ID of the authenticating client.
  ///
  /// This must be a valid client ID according to [authServer].\
  @Bind.query("client_id")
  String clientID;

  /// Renders an HTML login form.
  final AuthRedirectControllerDelegate delegate;

  /// Returns an HTML login form.
  ///
  /// A client that wishes to authenticate with this server should direct the user
  /// to this page. The user will enter their username and password that is sent as a POST
  /// request to this same controller.
  ///
  /// The 'client_id' must be a registered, valid client of this server. The client must also provide
  /// a [state] to this request and verify that the redirect contains the same value in its query string.
  @Operation.get()
  Future<Response> getAuthorizationPage(
      {

      /// A space-delimited list of access scopes to be requested by the form submission on the returned page.
      @Bind.query("scope") String scope}) async {
    if (delegate == null) {
      return Response(405, {}, null);
    }

    if (responseType != "code" && responseType != "token") {
      return _unsupportedResponseTypeResponse;
    }

    if (responseType == "token" && !allowsImplicit) {
      return _unsupportedResponseTypeResponse;
    }

    final renderedPage = await delegate.render(
        this, request.raw.uri, responseType, clientID, state, scope);
    if (renderedPage == null) {
      return Response.notFound();
    }

    return Response.ok(renderedPage)..contentType = ContentType.html;
  }

  /// Creates a one-time use authorization code or an access token.
  ///
  /// This method will respond with a redirect that either contains an authorization code ('code')
  /// or an access token ('token') along with the passed in 'state'. If this request fails,
  /// the redirect URL will contain an 'error' instead of the authorization code or access token.
  ///
  /// This method is typically invoked by the login form returned from the GET to this controller.
  @Operation.post()
  Future<Response> authorize(
      {

      /// The username of the authenticating user.
      @Bind.query("username") String username,

      /// The password of the authenticating user.
      @Bind.query("password") String password,

      /// A space-delimited list of access scopes being requested.
      @Bind.query("scope") String scope}) async {
    final client = await authServer.getClient(clientID);

    if (client?.redirectURI == null) {
      return Response.badRequest();
    }

    if (responseType == "token" && !allowsImplicit) {
      return _unsupportedResponseTypeResponse;
    }

    if (state == null) {
      return _redirectResponse(null, null,
          error: AuthServerException(AuthRequestError.invalidRequest, client));
    }

    try {
      final scopes = scope?.split(" ")?.map((s) => AuthScope(s))?.toList();

      if (responseType == "code") {
        if (client.hashedSecret == null) {
          return _redirectResponse(null, state,
              error: AuthServerException(AuthRequestError.unauthorizedClient, client));
        }

        final authCode = await authServer.authenticateForCode(
            username, password, clientID,
            requestedScopes: scopes);
        return _redirectResponse(client.redirectURI, state, code: authCode.code);
      } else if (responseType == "token") {
        final token = await authServer.authenticate(username, password, clientID, null, requestedScopes: scopes);
        return _redirectResponse(client.redirectURI, state, token: token);
      } else {
        return _redirectResponse(null, state,
            error: AuthServerException(AuthRequestError.invalidRequest, client));
      }
    } on FormatException {
      return _redirectResponse(null, state,
          error: AuthServerException(AuthRequestError.invalidScope, client));
    } on AuthServerException catch (e) {
      if (responseType == "token" && e.reason == AuthRequestError.invalidGrant) {
        return _redirectResponse(null, state,
            error: AuthServerException(AuthRequestError.accessDenied, client));
      }

      return _redirectResponse(null, state, error: e);
    }
  }

  @override
  APIRequestBody documentOperationRequestBody(
      APIDocumentContext context, Operation operation) {
    final body = super.documentOperationRequestBody(context, operation);
    if (operation.method == "POST") {
      body.content["application/x-www-form-urlencoded"].schema
          .properties["password"].format = "password";
      body.content["application/x-www-form-urlencoded"].schema.required = [
        "client_id",
        "state",
        "response_type",
        "username",
        "password"
      ];
    }
    return body;
  }

  @override
  List<APIParameter> documentOperationParameters(
      APIDocumentContext context, Operation operation) {
    final params = super.documentOperationParameters(context, operation);
    params.where((p) => p.name != "scope").forEach((p) {
      p.isRequired = true;
    });
    return params;
  }

  @override
  Map<String, APIResponse> documentOperationResponses(
      APIDocumentContext context, Operation operation) {
    if (operation.method == "GET") {
      return {
        "200": APIResponse.schema(
            "Serves a login form.", APISchemaObject.string(),
            contentTypes: ["text/html"])
      };
    } else if (operation.method == "POST") {
      return {
        "${HttpStatus.movedTemporarily}": APIResponse(
            "If successful, in the case of a 'response type' of 'code', the query "
            "parameter of the redirect URI named 'code' contains authorization code. "
            "Otherwise, the query parameter 'error' is present and contains a error string. "
            "In the case of a 'response type' of 'token', the redirect URI's fragment "
            "contains an access token. Otherwise, the fragment contains an error code.",
            headers: {
              "Location": APIHeader()
                ..schema = APISchemaObject.string(format: "uri")
            }),
        "${HttpStatus.badRequest}": APIResponse.schema(
            "If 'client_id' is invalid, the redirect URI cannot be verified and this response is sent.",
            APISchemaObject.object({"error": APISchemaObject.string()}),
            contentTypes: ["application/json"])
      };
    }

    throw StateError("AuthRedirectController documentation failed.");
  }

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext context, String route, APIPath path) {
    final ops = super.documentOperations(context, route, path);
    final uri = Uri(path: route.substring(1));
    authServer.documentedAuthorizationCodeFlow.authorizationURL = uri;
    authServer.documentedImplicitFlow.authorizationURL = uri;
    return ops;
  }

  Response _redirectResponse(
      final String inputUri, String clientStateOrNull,
      {String code, AuthToken token, AuthServerException error}) {
    final uriString = inputUri ?? error.client?.redirectURI;
    if (uriString == null) {
      return Response.badRequest(body: {"error": error.reasonString});
    }

    Uri redirectURI;

    try {
      redirectURI = Uri.parse(uriString);
    } catch (error) {
      return Response.badRequest();
    }

    final queryParameters =
        Map<String, String>.from(redirectURI.queryParameters);
    String fragment;

    if (responseType == "code") {
      if (code != null) {
        queryParameters["code"] = code;
      }
      if (clientStateOrNull != null) {
        queryParameters["state"] = clientStateOrNull;
      }
      if (error != null) {
        queryParameters["error"] = error.reasonString;
      }
    } else if (responseType == "token") {
      final params = token?.asMap() ?? {};

      if (clientStateOrNull != null) {
        params["state"] = clientStateOrNull;
      }
      if (error != null) {
        params["error"] = error.reasonString;
      }

      fragment = params.keys.map((key) => "$key=${Uri.encodeComponent(params[key].toString())}").join("&");
    } else {
      return _unsupportedResponseTypeResponse;
    }

    final responseURI = Uri(
        scheme: redirectURI.scheme,
        userInfo: redirectURI.userInfo,
        host: redirectURI.host,
        port: redirectURI.port,
        path: redirectURI.path,
        queryParameters: queryParameters,
        fragment: fragment);
    return Response(
        HttpStatus.movedTemporarily,
        {
          HttpHeaders.locationHeader: responseURI.toString(),
          HttpHeaders.cacheControlHeader: "no-store",
          HttpHeaders.pragmaHeader: "no-cache"
        },
        null);
  }
}
