import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/openapi/openapi.dart';

import '../http/http.dart';
import 'auth.dart';

/// A [Controller] that validates the Authorization header of a request.
///
/// An instance of this type will validate that the authorization information in an Authorization header is sufficient to access
/// the next controller in the channel.
///
/// For each request, this controller parses the authorization header, validates it with an [AuthValidator] and then create an [Authorization] object
/// if successful. The [Request] keeps a reference to this [Authorization] and is then sent to the next controller in the channel.
///
/// If either parsing or validation fails, a 401 Unauthorized response is sent and the [Request] is removed from the channel.
///
/// Parsing occurs according to [parser]. The resulting value (e.g., username and password) is sent to [validator].
/// [validator] verifies this value (e.g., lookup a user in the database and verify their password matches).
///
/// Usage:
///
///         router
///           .route("/protected-route")
///           .link(() =>new Authorizer.bearer(authServer))
///           .link(() => new ProtectedResourceController());
class Authorizer extends Controller {
  /// Creates an instance of [Authorizer].
  ///
  /// Use this constructor to provide custom [AuthorizationParser]s.
  ///
  /// By default, this instance will parse bearer tokens from the authorization header, e.g.:
  ///
  ///         Authorization: Bearer ap9ijlarlkz8jIOa9laweo
  ///
  /// If [scopes] is provided, the authorization granted must have access to *all* scopes according to [validator].
  Authorizer(this.validator, {this.parser: const AuthorizationBearerParser(), List<String> scopes})
      : this.scopes = scopes?.map((s) => new AuthScope(s))?.toList() {
    policy = null;
  }

  /// Creates an instance of [Authorizer] with Basic Authentication parsing.
  ///
  /// Parses a username and password from the request's Basic Authentication data in the Authorization header, e.g.:
  ///
  ///         Authorization: Basic base64(username:password)
  Authorizer.basic(AuthValidator validator) : this(validator, parser: const AuthorizationBasicParser());

  /// Creates an instance of [Authorizer] with Bearer token parsing.
  ///
  /// Parses a bearer token from the request's Authorization header, e.g.
  ///
  ///         Authorization: Bearer ap9ijlarlkz8jIOa9laweo
  ///
  /// If [scopes] is provided, the bearer token must have access to *all* scopes according to [validator].
  Authorizer.bearer(AuthValidator validator, {List<String> scopes})
      : this(validator, parser: const AuthorizationBearerParser(), scopes: scopes);

  /// The validating authorization object.
  ///
  /// This object will check credentials parsed from the Authorization header and produce an
  /// [Authorization] object representing the authorization the credentials have. It may also
  /// reject a request. This is typically an instance of [AuthServer].
  final AuthValidator validator;

  /// The list of required scopes.
  ///
  /// If [validator] grants scope-limited authorizations (e.g., OAuth2 bearer tokens), the authorization
  /// provided by the request's header must have access to all [scopes] in order to move on to the next controller.
  ///
  /// This property is set with a list of scope strings in a constructor. Each scope string is parsed into
  /// an [AuthScope] and added to this list.
  final List<AuthScope> scopes;

  /// Parses the Authorization header.
  ///
  /// The parser determines how to interpret the data in the Authorization header. Concrete subclasses
  /// are [AuthorizationBasicParser] and [AuthorizationBearerParser].
  ///
  /// Once parsed, the parsed value is validated by [validator].
  final AuthorizationParser parser;

  @override
  FutureOr<RequestOrResponse> handle(Request req) async {
    var authData = req.raw.headers.value(HttpHeaders.AUTHORIZATION);
    if (authData == null) {
      return new Response.unauthorized();
    }

    var value;
    try {
      value = parser.parse(authData);
    } on AuthorizationParserException catch (e) {
      return _responseFromParseException(e);
    }

    req.authorization = await validator.validate(parser, value, requiredScope: scopes);

    if (req.authorization == null) {
      return new Response.unauthorized();
    }

    return req;
  }

  Response _responseFromParseException(AuthorizationParserException e) {
    switch (e.reason) {
      case AuthorizationParserExceptionReason.malformed:
        return new Response.badRequest(body: {"error": "invalid_authorization_header"});
      case AuthorizationParserExceptionReason.missing:
        return new Response.unauthorized();
      default:
        return new Response.serverError();
    }
  }

  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext components, APIPath path) {
    final operations = super.documentOperations(components, path);

    final requirements = validator.documentRequirementsForAuthorizer(this, scopes: scopes);
    operations.forEach((_, op) {
      requirements.forEach((req) {
        op.addSecurityRequirement(req);
      });
    });

    return operations;
  }
}