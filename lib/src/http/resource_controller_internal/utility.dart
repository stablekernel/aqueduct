import 'dart:mirrors';

import '../resource_controller_bindings.dart';
import '../request.dart';
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
  return new Map.fromIterable(boundValues.where((v) => v.value != null),
      key: (BoundValue v) => v.symbol, value: (BoundValue v) => v.value);
}


bool isOperation(DeclarationMirror m) {
  return getMethodOperationMetadata(m) != null;
}

Operation getMethodOperationMetadata(DeclarationMirror m) {
  if (m is! MethodMirror) {
    return null;
  }

  MethodMirror method = m;
  if (!method.isRegularMethod || method.isStatic) {
    return null;
  }

  Operation metadata = method.metadata.firstWhere((im) => im.reflectee is Operation, orElse: () => null)?.reflectee;

  return metadata;
}