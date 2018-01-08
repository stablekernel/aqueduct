import 'dart:mirrors';
import '../request.dart';
import '../rest_controller_binding.dart';
import 'internal.dart';

class RESTControllerParameterBinder {
  RESTControllerParameterBinder(VariableMirror mirror, {this.isRequired: false}) {
    symbol = mirror.simpleName;

    Bind b = mirror.metadata.firstWhere((im) => im.reflectee is Bind, orElse: () => null)?.reflectee;
    if (b == null) {
      throw new StateError("Invalid operation method parameter '${MirrorSystem.getName(symbol)}' for controller '${MirrorSystem.getName(mirror.owner.simpleName)}'. Must have @Bind annotation.");
    }
    binding = b?.binding;
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
}