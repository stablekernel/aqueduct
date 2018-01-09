import 'dart:mirrors';

import 'package:open_api/v3.dart';

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

  APIParameter asDocumentedParameter() {
    final p = new APIParameter()
      ..location = binding.location
      ..name = name
      ..isRequired = isRequired
      ..schema = _schemaFromBoundType(boundValueType);

    if (p.schema.type == APIType.boolean) {
      p.allowEmptyValue = true;
    }

    return p;
  }
  
  static APISchemaObject _schemaFromBoundType(ClassMirror type) {
    if (type.isAssignableTo(reflectType(int))) {
      return new APISchemaObject.integer();
    } else if (type.isAssignableTo(reflectType(double))) {
      return new APISchemaObject.number();
    } else if (type.isAssignableTo(reflectType(String))) {
      return new APISchemaObject.string();
    } else if (type.isAssignableTo(reflectType(bool))) {
      return new APISchemaObject.boolean();
    } else if (type.isAssignableTo(reflectType(DateTime))) {
      return new APISchemaObject.string(format: "date-time");
    } else if (type.isAssignableTo(reflectType(List))) {
      return new APISchemaObject.array(ofSchema: _schemaFromBoundType(type.typeArguments.first));
    }

    return new APISchemaObject.string();
  }

  
  String _methodErrorName(VariableMirror mirror) {
    return "${MirrorSystem.getName(mirror.owner.owner.simpleName)}.${MirrorSystem.getName(mirror.owner.simpleName)}";
  }
}