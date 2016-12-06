import 'dart:async';
import 'dart:io';

import '../http/http.dart';
import 'auth.dart';
import 'package:path/path.dart' as path_lib;

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
  AuthCodeController(this.authenticationServer,
      {Future<String> renderAuthorizationPageHTML(AuthCodeController controller,
          Uri requestURI, Map<String, String> queryParameters)}) {
    acceptedContentTypes = [
      new ContentType("application", "x-www-form-urlencoded")
    ];

    _renderFunction = renderAuthorizationPageHTML;
  }

  /// A reference to the [AuthServer] this controller uses to grant authorization codes.
  AuthServer authenticationServer;

  _RenderAuthorizationPageFunction _renderFunction;

  @httpGet
  Future<Response> getAuthorizationPage(
      {@HTTPQuery("response_type") String responseType,
      @HTTPQuery("client_id") String clientID,
      @HTTPQuery("state") String state,
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

    return new Response.ok(renderedPage)..contentType = ContentType.HTML;
  }

  /// Creates a one-time use authorization code.
  ///
  /// The authorization code is returned as a query parameter in the resulting 302 response.
  /// If [state] is supplied, it will be returned in the query as a way
  /// for the client to ensure it is receiving a response from the expected endpoint.
  @httpPost
  Future<Response> authorize(
      @HTTPQuery("client_id") String clientID,
      @HTTPQuery("response_type") String responseType,
      @HTTPQuery("username") String username,
      @HTTPQuery("password") String password,
      {@HTTPQuery("state") String state}) async {
    var authCode =
        await authenticationServer.createAuthCode(username, password, clientID);
    return AuthCodeController.authCodeResponse(authCode, state);
  }

  static Response authCodeResponse(
      AuthTokenExchangable code, String clientState) {
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
          "Location": responseURI.toString(),
          "Cache-Control": "no-store",
          "Pragma": "no-cache"
        },
        null);
  }

  @override
  void willSendResponse(Response response) {

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

//  Future<String> _defaultRenderFunction(String path, String clientID, String state) async {
//    if (_defaultRenderTemplate == null) {
//      try {
//        var file = new File(path_lib.join("web", "login.html"));
//        _defaultRenderTemplate = file.readAsStringSync();
//      } catch (e) {
//        logger.warning("Could not find authorization HTML template web/login.html.");
//        _defaultRenderTemplate = "";
//      }
//    }
//
//    var substituted = _defaultRenderTemplate.replaceFirst("{{client_id}}", clientID);
//    substituted = substituted.replaceFirst("{{path}}", path);
//    if (state != null) {
//      substituted = substituted.replaceFirst("{{state}}", state);
//    } else {
//      substituted = substituted.replaceFirst('<input type="hidden" name="state" value="{{state}}">', "");
//    }
//
//    return substituted;
//  }
}
