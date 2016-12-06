import 'dart:async';
import 'dart:io';

import '../http/http.dart';
import 'auth.dart';

/// The type of authorization strategy to use for an [Authorizer].
enum AuthStrategy {
  /// The resource owner strategy requires that a [Request] have a Bearer token.
  ///
  /// This value is deprecated. Use [AuthStrategy.bearer] instead.
  resourceOwner,

  /// The client strategy requires that the [Request] have a Basic Authorization Client ID and Client secret.
  ///
  /// This value is deprecated. Use [AuthStrategy.basic] instead.
  client,

  /// This strategy will parse the Authorization header using the Basic Authorization scheme.
  ///
  /// The resulting username/password will be passed to [AuthValidator.fromBasicCredentials].
  basic,

  /// This strategy will parse the Authorization header using the Bearer Authorization scheme.
  ///
  /// The resulting bearer token will be passed to [AuthValidator.fromBearerToken].
  bearer
}

/// A [RequestController] that will authorize further passage in a [RequestController] chain when appropriate credentials
/// are provided in the request being handled.
///
/// An instance of [Authorizer] will validate a [Request] given a [strategy] with its [validator].
/// If the [Request] is unauthorized (as determined by the [validator]), it will respond with the appropriate status code and prevent
/// further request processing. If the [Request] is valid, this instance will attach a [Authorization]
/// to the [Request] and deliver it to this instance's [nextController].
class Authorizer extends RequestController {
  /// Creates an instance of [Authorizer].
  ///
  /// The default strategy is [AuthStrategy.bearer].
  Authorizer(this.validator,
      {this.strategy: AuthStrategy.bearer, this.scopes}) {
    policy = null;
  }

  /// Creates an instance of [Authorizer] using [AuthStrategy.basic].
  Authorizer.basic(AuthValidator validator)
      : this(validator, strategy: AuthStrategy.basic);

  /// Creates an instance of [Authorizer] using [AuthStrategy.bearer].
  ///
  /// Optionally allows the setting of [Authorizer.scopes].
  Authorizer.bearer(AuthValidator validator, {List<String> scopes})
      : this(validator, strategy: AuthStrategy.bearer, scopes: scopes);

  /// The validating authorization object.
  ///
  /// This object will check credentials parsed from the Authorization header and produce an
  /// [Authorizer] instance representing the authorization the credentials have. It may also
  /// reject a request.
  AuthValidator validator;

  /// The list of scopes this instance requires.
  ///
  /// A bearer token must have access to all of the scopes in this list in order to pass
  /// through to this instances [nextController].
  List<String> scopes;

  /// The [AuthStrategy] for authorizing a request.
  AuthStrategy strategy;

  // This is temporary while resourceOwner/client deprecate
  AuthStrategy get _actualStrategy {
    if (strategy == AuthStrategy.resourceOwner) {
      return AuthStrategy.bearer;
    } else if (strategy == AuthStrategy.client) {
      return AuthStrategy.basic;
    }

    return strategy;
  }

  @override
  Future<RequestControllerEvent> processRequest(Request req) async {
    var header = req.innerRequest.headers.value(HttpHeaders.AUTHORIZATION);
    if (header == null) {
      return new Response.unauthorized();
    }

    var s = _actualStrategy;
    if (s == AuthStrategy.bearer) {
      return await _processBearerHeader(req, header);
    } else if (s == AuthStrategy.basic) {
      return await _processBasicHeader(req, header);
    }

    return new Response.serverError();
  }

  Future<RequestControllerEvent> _processBearerHeader(
      Request request, String headerValue) async {
    String bearerToken;
    try {
      bearerToken = AuthorizationBearerParser.parse(headerValue);
    } on AuthorizationParserException catch (e) {
      return _responseFromParseException(e);
    }

    var authorization = await validator.fromBearerToken(bearerToken, scopes);
    if (authorization == null) {
      return new Response.unauthorized();
    }

    request.authorization = authorization;
    return request;
  }

  Future<RequestControllerEvent> _processBasicHeader(
      Request request, String headerValue) async {
    AuthorizationBasicElements elements;
    try {
      elements = AuthorizationBasicParser.parse(headerValue);
    } on AuthorizationParserException catch (e) {
      return _responseFromParseException(e);
    }

    var authorization = await validator.fromBasicCredentials(
        elements.username, elements.password);
    if (authorization == null) {
      return new Response.unauthorized();
    }

    request.authorization = authorization;
    return request;
  }

  Response _responseFromParseException(AuthorizationParserException e) {
    if (e.reason == AuthorizationParserExceptionReason.malformed) {
      return new Response.badRequest(
          body: {"error": "invalid_authorization_header"});
    } else if (e.reason == AuthorizationParserExceptionReason.missing) {
      return new Response.unauthorized();
    }

    return new Response.serverError();
  }

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) {
    List<APIOperation> items = nextController.documentOperations(resolver);


    var secReq = new APISecurityRequirement()..scopes = [];

    if (strategy == AuthStrategy.client) {
      strategy = AuthStrategy.basic;
      secReq.name = "oauth2.application";
    } else if (strategy == AuthStrategy.resourceOwner) {
      strategy = AuthStrategy.bearer;
      secReq.name = "oauth2.password";
    }

    //TODO: put this in validator

    items.forEach((i) {
      i.security = [secReq];
    });

    return items;
  }
}

/// Instances that implement this type can be used in [Authorizer]s to authorize access to another [RequestController].
///
/// When an [Authorizer] processes a [Request], it invokes methods from this type to determine the [Authorization] from the Authorization
/// header of the [Request].
abstract class AuthValidator {
  /// Returns an [Authorization] from basic credentials.
  ///
  /// This method must either return a [Future] that yields an [Authorization] or return null.
  /// If this method returns null, the invoking [Authorizer] will disallow further
  /// request handling and immediately return a 401 status code. If this method returns an
  /// [Authorization], it will be set as the [Request.authorization] and request handling
  /// will continue to the [Authorizer.nextController].
  Future<Authorization> fromBasicCredentials(String username, String password);

  /// Returns an [Authorization] from a bearer token.
  ///
  /// This method must either return a [Future] that yields an [Authorization] or return null.
  /// If this method returns null, the invoking [Authorizer] will disallow further
  /// request handling and immediately return a 401 status code. If this method returns an
  /// [Authorization], it will be set as the [Request.authorization] and request handling
  /// will continue to the [Authorizer.nextController].
  ///
  /// [scopesRequired] is the list of scopes established when the calling [Authorizer]
  /// is created. Implementors of this method must verify the bearer token access to [scopesRequired].
  ///
  /// If [scopesRequired] is null, an implementor may make its own determination about whether
  /// the token results in an [Authorization]. By default, [AuthServer] - the primary implementor of this type -
  /// will allow access, assuming that 'null scope' means 'any scope'.
  Future<Authorization> fromBearerToken(
      String bearerToken, List<String> scopesRequired);


}
