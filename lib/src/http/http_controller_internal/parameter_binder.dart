import 'dart:mirrors';
import '../request.dart';
import '../http_controller_binding.dart';
import 'internal.dart';

class HTTPControllerParameterBinder {
  HTTPControllerParameterBinder(VariableMirror mirror, {this.isRequired: false}) {
    symbol = mirror.simpleName;

    Bind b = mirror.metadata.firstWhere((im) => im.reflectee is Bind).reflectee;
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