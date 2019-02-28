import 'dart:mirrors';
import 'package:aqueduct/src/auth/auth.dart';
import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

import 'internal.dart';

class BoundMethod {
  BoundMethod(MethodMirror mirror) {
    final operation = getMethodOperationMetadata(mirror);
    httpMethod = operation.method.toUpperCase();
    pathVariables = operation.pathVariables;
    methodSymbol = mirror.simpleName;

    final parametersWithoutMetadata = mirror.parameters.where((p) => firstMetadataOfType<Bind>(p) == null).toList();
    if (parametersWithoutMetadata.isNotEmpty) {
      final names = parametersWithoutMetadata.map((p) => "'${MirrorSystem.getName(p.simpleName)}'").join(", ");
      throw StateError("Invalid operation method parameter(s) $names on "
        "'${getMethodAndClassName(parametersWithoutMetadata.first)}': Must have @Bind annotation.");
    }

    positionalParameters = mirror.parameters
        .where((pm) => !pm.isOptional)
        .map((pm) => BoundParameter(pm, isRequired: true))
        .toList();
    optionalParameters = mirror.parameters
        .where((pm) => pm.isOptional)
        .map((pm) => BoundParameter(pm, isRequired: false))
        .toList();

    scopes = getMethodScopes(mirror);
  }

  Symbol methodSymbol;
  String httpMethod;
  List<String> pathVariables;
  List<BoundParameter> positionalParameters = [];
  List<BoundParameter> optionalParameters = [];
  List<AuthScope> scopes;

  /// Checks if a request's method and path variables will select this binder.
  ///
  /// Note that [requestMethod] may be null; if this is the case, only
  /// path variables are compared.
  bool isSuitableForRequest(
      String requestMethod, List<String> requestPathVariables) {
    if (requestMethod != null && requestMethod.toUpperCase() != httpMethod) {
      return false;
    }

    if (pathVariables.length != requestPathVariables.length) {
      return false;
    }

    return requestPathVariables
        .every((varName) => pathVariables.contains(varName));
  }
}
