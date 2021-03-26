import 'dart:async';

import 'package:aqueduct/src/http/request.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'auth.dart';

/// Instances that implement this type can be used by an [Authorizer] to determine authorization of a request.
///
/// When an [Authorizer] processes a [Request], it invokes [validate], passing in the parsed Authorization
/// header of the [Request].
///
/// [AuthServer] implements this interface.
abstract class AuthValidator {
  /// Returns an [Authorization] if [authorizationData] is valid.
  ///
  /// This method is invoked by [Authorizer] to validate the Authorization header of a request. [authorizationData]
  /// is the parsed contents of the Authorization header, while [parser] is the object that parsed the header.
  ///
  /// If this method returns null, an [Authorizer] will send a 401 Unauthorized response.
  /// If this method throws an [AuthorizationParserException], a 400 Bad Request response is sent.
  /// If this method throws an [AuthServerException], an appropriate status code is sent for the details of the exception.
  ///
  /// If [requiredScope] is provided, a request's authorization must have at least that much scope to pass the [Authorizer].
  FutureOr<Authorization> validate<T>(
      AuthorizationParser<T> parser, T authorizationData,
      {List<AuthScope> requiredScope});

  /// Provide [APISecurityRequirement]s for [authorizer].
  ///
  /// An [Authorizer] that adds security requirements to operations will invoke this method to allow this validator to define those requirements.
  /// The [Authorizer] must provide the [context] it was given to document the operations, itself and optionally a list of [scopes] required to pass it.
  List<APISecurityRequirement> documentRequirementsForAuthorizer(
          APIDocumentContext context, Authorizer authorizer,
          {List<AuthScope> scopes}) =>
      [];
}
