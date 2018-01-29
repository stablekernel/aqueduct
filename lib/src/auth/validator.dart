import 'dart:async';

import 'package:aqueduct/src/http/request.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'auth.dart';

/// Instances that implement this type can be used by an [Authorizer] to determine authorization of a request.
///
/// When an [Authorizer] processes a [Request], it invokes methods from this type to determine the [Authorization] from the Authorization
/// header of the [Request]. [AuthServer] implements this interface.
abstract class AuthValidator {
  /// Returns an [Authorization] if [authorizationData] is valid.
  ///
  /// [authorizationData] is usually the contents of an Authorization header. Instances of this type validate the data
  /// and the [Authorization] that data represents. For example, if [authorizationData] were a username and password
  /// and this instance verifies it is the correct password for the user, an [Authorization] for that user will be returned.
  ///
  /// This method must return null if [authorizationData] is invalid. This includes instances like an incorrect password, malformed data,
  /// or any other kind of error.
  ///
  /// [parser] indicates the object that provided [authorizationData]. For example, a [AuthorizationBearerParser] will provide a [String] representation of the bearer token.
  ///
  /// If [requiredScope] is provided, this instance will verify that the [Authorization] for [authorizationData] has the appropriate scope to access to every element in [requiredScope].
  /// This parameter is only valid for instances that support scoping (e.g., OAuth2).
  FutureOr<Authorization> validate<T>(AuthorizationParser<T> parser, T authorizationData,
      {List<AuthScope> requiredScope});


  List<APISecurityRequirement> documentRequirementsForAuthorizer(APIDocumentContext context, Authorizer authorizer, {List<AuthScope> scopes}) => [];
}
