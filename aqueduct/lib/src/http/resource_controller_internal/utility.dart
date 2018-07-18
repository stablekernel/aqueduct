import 'dart:mirrors';

import 'package:aqueduct/src/auth/auth.dart';
import 'package:aqueduct/src/http/resource_controller_scope.dart';

import '../request.dart';
import '../resource_controller_bindings.dart';
import 'bindings.dart';

bool requestHasFormData(Request request) {
  var contentType = request.raw.headers.contentType;
  if (contentType != null &&
      contentType.primaryType == "application" &&
      contentType.subType == "x-www-form-urlencoded") {
    return true;
  }

  return false;
}

Map<Symbol, dynamic> toSymbolMap(Iterable<BoundValue> boundValues) {
  return Map.fromIterable(boundValues.where((v) => v.value != null),
      key: (v) => (v as BoundValue).symbol,
      value: (v) => (v as BoundValue).value);
}

bool isOperation(DeclarationMirror m) {
  return getMethodOperationMetadata(m) != null;
}

List<AuthScope> getMethodScopes(DeclarationMirror m) {
  if (!isOperation(m)) {
    return null;
  }

  MethodMirror method = m;
  Scope metadata = method.metadata
      .firstWhere((im) => im.reflectee is Scope, orElse: () => null)
      ?.reflectee;

  return metadata?.scopes?.map((scope) => AuthScope(scope))?.toList();
}

Operation getMethodOperationMetadata(DeclarationMirror m) {
  if (m is! MethodMirror) {
    return null;
  }

  MethodMirror method = m;
  if (!method.isRegularMethod || method.isStatic) {
    return null;
  }

  Operation metadata = method.metadata
      .firstWhere((im) => im.reflectee is Operation, orElse: () => null)
      ?.reflectee;

  return metadata;
}
