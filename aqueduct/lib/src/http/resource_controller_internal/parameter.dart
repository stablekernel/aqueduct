import 'dart:mirrors';

import '../request.dart';
import '../resource_controller_bindings.dart';
import 'internal.dart';

class BoundParameter {
  BoundParameter(VariableMirror mirror, {this.isRequired = false})
      : symbol = mirror.simpleName {
    Bind b = mirror.metadata
        .firstWhere((im) => im.reflectee is Bind, orElse: () => null)
        ?.reflectee;
    if (b == null) {
      throw StateError(
          "Invalid operation method parameter '${MirrorSystem.getName(symbol)}' on '${_methodErrorName(mirror)}': Must have @Bind annotation.");
    }

    if (!b.binding.validateType(mirror.type)) {
      throw StateError(
          "Invalid binding '${MirrorSystem.getName(symbol)}' on '${_methodErrorName(mirror)}': "
          "'${MirrorSystem.getName(mirror.type.simpleName)}' may not be bound to ${b.binding.type}.");
    }

    binding = b.binding;

    final type = mirror.type;
    if (type is! ClassMirror) {
      throw StateError(
          "Invalid binding '${MirrorSystem.getName(symbol)}' on '${_methodErrorName(mirror)}': "
          "parameter type '${type.reflectedType}' cannot be bound.");
    }
    boundValueType = type as ClassMirror;
  }

  final Symbol symbol;
  String get name => binding.externalName;
  ClassMirror boundValueType;
  BoundInput binding;
  final bool isRequired;

  dynamic parse(Request request) {
    return binding.parse(boundValueType, request);
  }

  String _methodErrorName(VariableMirror mirror) {
    return "${MirrorSystem.getName(mirror.owner.owner.simpleName)}.${MirrorSystem.getName(mirror.owner.simpleName)}";
  }
}
