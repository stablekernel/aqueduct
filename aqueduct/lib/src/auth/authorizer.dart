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
  Authorizer(this.validator,
      {this.parser = const AuthorizationBearerParser(), List<String> scopes})
      : scopes = scopes?.map((s) => AuthScope(s))?.toList();

  /// Creates an instance of [Authorizer] with Basic Authentication parsing.
  ///
  /// Parses a username and password from the request's Basic Authentication data in the Authorization header, e.g.:
  ///
  ///         Authorization: Basic base64(username:password)
  Authorizer.basic(AuthValidator validator)
      : this(validator, parser: const AuthorizationBasicParser());

  /// Creates an instance of [Authorizer] with Bearer token parsing.
  ///
  /// Parses a bearer token from the request's Authorization header, e.g.
  ///
  ///         Authorization: Bearer ap9ijlarlkz8jIOa9laweo
  ///
  /// If [scopes] is provided, the bearer token must have access to *all* scopes according to [validator].
  Authorizer.bearer(AuthValidator validator, {List<String> scopes})
      : this(validator,
            parser: const AuthorizationBearerParser(), scopes: scopes);

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
  FutureOr<RequestOrResponse> handle(Request request) async {
    final authData = request.raw.headers.value(HttpHeaders.authorizationHeader);
    if (authData == null) {
      return Response.unauthorized();
    }

    try {
      final value = parser.parse(authData);
      request.authorization =
          await validator.validate(parser, value, requiredScope: scopes);
      if (request.authorization == null) {
        return Response.unauthorized();
      }

      _addScopeRequirementModifier(request);
    } on AuthorizationParserException catch (e) {
      return _responseFromParseException(e);
    } on AuthServerException catch (e) {
      if (e.reason == AuthRequestError.invalidScope) {
        return Response.forbidden(body: {
          "error": "insufficient_scope",
          "scope": scopes.map((s) => s.toString()).join(" ")
        });
      }

      return Response.unauthorized();
    }

    return request;
  }

  Response _responseFromParseException(AuthorizationParserException e) {
    switch (e.reason) {
      case AuthorizationParserExceptionReason.malformed:
        return Response.badRequest(
            body: {"error": "invalid_authorization_header"});
      case AuthorizationParserExceptionReason.missing:
        return Response.unauthorized();
      default:
        return Response.serverError();
    }
  }

  void _addScopeRequirementModifier(Request request) {
    // If a controller returns a 403 because of invalid scope,
    // this Authorizer adds its required scope as well.
    if (scopes != null) {
      request.addResponseModifier((resp) {
        if (resp.statusCode == 403 && resp.body is Map) {
          final body = resp.body as Map<String, dynamic>;
          if (body.containsKey("scope")) {
            final declaredScopes = (body["scope"] as String).split(" ");
            final scopesToAdd = scopes
                .map((s) => s.toString())
                .where((s) => !declaredScopes.contains(s));
            body["scope"] =
                [scopesToAdd, declaredScopes].expand((i) => i).join(" ");
          }
        }
      });
    }
  }

  @override
  void documentComponents(APIDocumentContext context) {
    super.documentComponents(context);

    context.responses.register(
        "InsufficientScope",
        APIResponse(
            "The provided credentials or bearer token have insufficient permission to access this route.",
            content: {
              "application/json": APIMediaType(
                  schema: APISchemaObject.object({
                "error": APISchemaObject.string(),
                "scope": APISchemaObject.string()
                  ..description = "The required scope for this operation."
              }))
            }));

    context.responses.register(
        "InsufficientAccess",
        APIResponse(
            "The provided credentials or bearer token are not authorized for this request.",
            content: {
              "application/json": APIMediaType(
                  schema: APISchemaObject.object(
                      {"error": APISchemaObject.string()}))
            }));

    context.responses.register(
        "MalformedAuthorizationHeader",
        APIResponse("The provided Authorization header was malformed.",
            content: {
              "application/json": APIMediaType(
                  schema: APISchemaObject.object(
                      {"error": APISchemaObject.string()}))
            }));
  }

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext context, String route, APIPath path) {
    final operations = super.documentOperations(context, route, path);

    operations.forEach((_, op) {
      op.addResponse(400, context.responses["MalformedAuthorizationHeader"]);
      op.addResponse(401, context.responses["InsufficientAccess"]);
      op.addResponse(403, context.responses["InsufficientScope"]);

      final requirements = validator
          .documentRequirementsForAuthorizer(context, this, scopes: scopes);
      requirements.forEach((req) {
        op.addSecurityRequirement(req);
      });
    });

    return operations;
  }
}
