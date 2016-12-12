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
/// allows the developer to provide a page rendering anonymous function in the constructor.
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
  AuthCodeController(this.authenticationServer,
      {Future<String> renderAuthorizationPageHTML(AuthCodeController controller,
          Uri requestURI, Map<String, String> queryParameters)}) {
    acceptedContentTypes = [
      new ContentType("application", "x-www-form-urlencoded")
    ];
    responseContentType = ContentType.HTML;

    _renderFunction = renderAuthorizationPageHTML;
  }

  /// A reference to the [AuthServer] this controller uses to grant authorization codes.
  AuthServer authenticationServer;

  _RenderAuthorizationPageFunction _renderFunction;

  @HTTPQuery("state") String state;

  @httpGet
  Future<Response> getAuthorizationPage(
      {@HTTPQuery("response_type") String responseType,
      @HTTPQuery("client_id") String clientID,
      @HTTPQuery("scope") String scope}) async {
    if (_renderFunction == null) {
      return new Response(405, {}, null);
    }

    var renderedPage = await _renderFunction(this, request.innerRequest.uri, {
      "response_type": responseType,
      "client_id": clientID,
      "state": state,
      "scope": scope
    });

    return new Response.ok(renderedPage);
  }

  /// Creates a one-time use authorization code.
  ///
  /// The authorization code is returned as a query parameter in the resulting 302 response.
  /// If [state] is supplied, it will be returned in the query as a way
  /// for the client to ensure it is receiving a response from the expected endpoint.
  @httpPost
  Future<Response> authorize(
      {@HTTPQuery("client_id") String clientID,
      @HTTPQuery("response_type") String responseType,
      @HTTPQuery("username") String username,
      @HTTPQuery("password") String password,
      @HTTPQuery("scope") String scope}) async {

    if (responseType != "code") {
      if (clientID == null) {
        return new Response.badRequest();
      }

      var client = await authenticationServer.clientForID(clientID);
      if (client.redirectURI == null) {
        return new Response.badRequest();
      }

      var exception = new AuthServerException(AuthRequestError.invalidRequest, client);
      return _redirectResponse(exception);
    }

    try {
      var authCode =
          await authenticationServer.authenticateForCode(username, password, clientID);
      return AuthCodeController.authCodeResponse(authCode, state);
    } on AuthServerException catch (e) {
      return _redirectResponse(e);
    }
  }

  static Response authCodeResponse(
      AuthCode code, String clientState) {
    var redirectURI = Uri.parse(code.redirectURI);
    Map<String, String> queryParameters =
        new Map.from(redirectURI.queryParameters);
    queryParameters["code"] = code.code;
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
          HttpHeaders.LOCATION: responseURI.toString(),
          HttpHeaders.CACHE_CONTROL: "no-store",
          HttpHeaders.PRAGMA: "no-cache"
        },
        null);
  }

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) {
    var ops = super.documentOperations(resolver);
    ops.forEach((op) {
      op.parameters.forEach((param) {
        if (param.name == "username"
        || param.name == "password"
        || param.name == "client_id"
        || param.name == "response_type") {
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

  Response _redirectResponse(AuthServerException exception) {
    if (exception.client?.redirectURI == null) {
      return new Response.badRequest(
          body: {"error" : exception.reasonString});
    }

    var redirectURI = Uri.parse(exception.client.redirectURI);
    Map<String, String> queryParameters =
      new Map.from(redirectURI.queryParameters);

    queryParameters["error"] = exception.reasonString;

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
