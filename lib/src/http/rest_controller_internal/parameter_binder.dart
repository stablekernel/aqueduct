import 'dart:mirrors';
import '../request.dart';
import '../rest_controller_binding.dart';
import 'internal.dart';

class RESTControllerParameterBinder {
  RESTControllerParameterBinder(VariableMirror mirror, {this.isRequired: false}) {
    symbol = mirror.simpleName;

    Bind b = mirror.metadata.firstWhere((im) => im.reflectee is Bind, orElse: () => null)?.reflectee;
    if (b == null) {
      throw new StateError("Invalid operation method parameter '${MirrorSystem.getName(symbol)}' on '${_methodErrorName(mirror)}': Must have @Bind annotation.");
    }

    if (!b.binding.validateType(mirror.type)) {
      throw new StateError("Invalid binding '${MirrorSystem.getName(symbol)}' on '${_methodErrorName(mirror)}': "
          "'${MirrorSystem.getName(mirror.type.simpleName)}' may not be bound to ${b.binding.type}.");
    }
    
    binding = b.binding;
    boundValueType = mirror.type;
  }

  Symbol symbol;

  String get name => binding.externalName;
  ClassMirror boundValueType;
  HTTPBinding binding;
  bool isRequired;

  dynamic parse(Request request) {
    return binding.parse(boundValueType, request);
  }

  String _methodErrorName(VariableMirror mirror) {
    return "${MirrorSystem.getName(mirror.owner.owner.simpleName)}.${MirrorSystem.getName(mirror.owner.simpleName)}";
  }
}