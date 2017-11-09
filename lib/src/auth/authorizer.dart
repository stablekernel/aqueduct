import 'dart:async';
import 'dart:io';

import '../http/http.dart';
import 'auth.dart';

/// The type of authorization strategy to use for an [Authorizer].
enum AuthStrategy {
  /// This strategy will parse the Authorization header using the Basic Authorization scheme.
  ///
  /// The resulting [AuthBasicCredentials] will be passed to [AuthValidator.fromBasicCredentials].
  basic,

  /// This strategy will parse the Authorization header using the Bearer Authorization scheme.
  ///
  /// The resulting bearer token will be passed to [AuthValidator.fromBearerToken].
  bearer
}

/// A [RequestController] that will authorize further passage in a [RequestController] chain when a request has valid
/// credentials.
///
/// An instance of [Authorizer] will validate a [Request] given a [strategy] and a [validator]. [validator] is typically the instance
/// of [AuthServer] in an application.
///
/// If the [Request] is unauthorized (as determined by the [validator]), it will respond with the appropriate status code and prevent
/// further request processing. If the [Request] is valid, an [Authorization] will be added
/// to the [Request] and the request will be delivered to this instance's [nextController]. Usage:
///
///         router
///           .route("/protectedroute")
///           .pipe(new Authorizer.bearer(authServer))
///           .generate(() => new ProtectedResourceController());
class Authorizer extends RequestController {
  /// Creates an instance of [Authorizer].
  ///
  /// The default strategy is [AuthStrategy.bearer].
  Authorizer(this.validator,
      {this.strategy: AuthStrategy.bearer, List<String> scopes}) {
    this.scopes = scopes;
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
  /// [Authorization] instance representing the authorization the credentials have. It may also
  /// reject a request. This is typically an instance of [AuthServer].
  AuthValidator validator;

  /// The list of scopes this instance requires.
  ///
  /// A bearer token must have access to all of the scopes in this list in order to pass
  /// through to the [nextController].
  List<String> get scopes => _scopes?.map((s) => s.scopeString)?.toList();
  set scopes(List<String> scopes) {
    _scopes = scopes?.map((s) => new AuthScope(s))?.toList();
  }
  List<AuthScope> _scopes;

  /// The [AuthStrategy] for authorizing a request.
  ///
  /// This property determines which [AuthValidator] method is invoked on [validator].
  AuthStrategy strategy;

  @override
  FutureOr<RequestOrResponse> handle(Request req) {
    var header = req.raw.headers.value(HttpHeaders.AUTHORIZATION);
    if (header == null) {
      return new Response.unauthorized();
    }

    switch (strategy) {
      case AuthStrategy.bearer: return _processBearerHeader(req, header);
      case AuthStrategy.basic: return _processBasicHeader(req, header);
      default: return new Response.serverError();
    }
  }

  Future<RequestOrResponse> _processBearerHeader(
      Request request, String headerValue) async {
    String bearerToken;
    try {
      bearerToken = AuthorizationBearerParser.parse(headerValue);
    } on AuthorizationParserException catch (e) {
      return _responseFromParseException(e);
    }

    var authorization = await validator.fromBearerToken(bearerToken, scopesRequired: _scopes);
    if (authorization == null) {
      return new Response.unauthorized();
    }

    request.authorization = authorization;
    return request;
  }

  Future<RequestOrResponse> _processBasicHeader(
      Request request, String headerValue) async {
    AuthBasicCredentials elements;
    try {
      elements = AuthorizationBasicParser.parse(headerValue);
    } on AuthorizationParserException catch (e) {
      return _responseFromParseException(e);
    }

    var authorization = await validator.fromBasicCredentials(elements);
    if (authorization == null) {
      return new Response.unauthorized();
    }

    request.authorization = authorization;
    return request;
  }

  Response _responseFromParseException(AuthorizationParserException e) {
    switch (e.reason) {
      case AuthorizationParserExceptionReason.malformed:
        return new Response.badRequest(
            body: {"error": "invalid_authorization_header"});
      case AuthorizationParserExceptionReason.missing:
        return new Response.unauthorized();
      default:
        return new Response.serverError();
    }    
  }

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) {
    List<APIOperation> operations = nextController.documentOperations(resolver);
    var requirements = validator.requirementsForStrategy(strategy);

    operations.forEach((i) {
      i.security = requirements;
    });

    return operations;
  }
}

/// Instances that implement this type can be used by an [Authorizer] to determine authorization of a request.
///
/// When an [Authorizer] processes a [Request], it invokes methods from this type to determine the [Authorization] from the Authorization
/// header of the [Request]. [AuthServer] implements this interface.
abstract class AuthValidator {
  /// Returns an [Authorization] from basic credentials.
  ///
  /// This method must either return a [Future] that yields an [Authorization] or return null.
  /// If this method returns null, the invoking [Authorizer] will disallow further
  /// request handling and immediately return a 401 status code. If this method returns an
  /// [Authorization], it will be set as the [Request.authorization] and request handling
  /// will continue to the [Authorizer.nextController].
  FutureOr<Authorization> fromBasicCredentials(
      AuthBasicCredentials usernameAndPassword);

  /// Returns an [Authorization] from a bearer token.
  ///
  /// This method must either return a [Future] that yields an [Authorization] or return null.
  /// If this method returns null, the invoking [Authorizer] will disallow further
  /// request handling and immediately return a 401 status code. If this method returns an
  /// [Authorization], it will be set as the [Request.authorization] and request handling
  /// will continue to the [Authorizer.nextController].
  ///
  /// [scopesRequired] is the list of scopes established when the [Authorizer]
  /// is created. Implementors of this method must verify the bearer token has access to [scopesRequired].
  ///
  /// If [scopesRequired] is null, an implementor may make its own determination about whether
  /// the token results in an [Authorization]. By default, [AuthServer] - the primary implementor of this type -
  /// will allow access, assuming that 'null scope' means 'any scope'.
  FutureOr<Authorization> fromBearerToken(
      String bearerToken, {List<AuthScope> scopesRequired});

  List<APISecurityRequirement> requirementsForStrategy(AuthStrategy strategy) => [];
}
