import 'dart:io';
import 'dart:mirrors';

import '../serializable.dart';
import '../errors.dart';
import '../request.dart';
import '../response.dart';
import 'internal.dart';

/// Parent class for annotations used for optional parameters in controller methods
abstract class HTTPBinding {
  HTTPBinding(this.externalName);

  /// The name of the variable in the HTTP request.
  final String externalName;

  String get type;

  bool validateType(TypeMirror type) {
    if (type.reflectedType == dynamic) {
      return false;
    }

    if (type.isAssignableTo(reflectType(String))) {
      return true;
    } else if (type is ClassMirror && type.staticMembers.containsKey(#parse)) {
      final parseMethod = type.staticMembers[#parse];
      final params = parseMethod.parameters.where((p) => !p.isOptional).toList();
      if (params.length == 1 && params.first.type.isAssignableTo(reflectType(String))) {
        return true;
      }
      return false;
    } else if (type.isAssignableTo(reflectType(List))) {
      return validateType(type.typeArguments.first);
    }

    return false;
  }

  dynamic parse(ClassMirror intoType, Request request);

  dynamic convertParameterListWithMirror(List<String> parameterValues, TypeMirror typeMirror) {
    if (parameterValues == null) {
      return null;
    }

    if (typeMirror.isSubtypeOf(reflectType(List))) {
      return parameterValues.map((str) => convertParameterWithMirror(str, typeMirror.typeArguments.first)).toList();
    } else {
      if (parameterValues.length > 1) {
        throw new Response.badRequest(body: {"error": "multiple values for '$externalName' not expected"});
      }
      return convertParameterWithMirror(parameterValues.first, typeMirror);
    }
  }

  dynamic convertParameterWithMirror(String parameterValue, TypeMirror typeMirror) {
    if (parameterValue == null) {
      return null;
    }

    if (typeMirror.isSubtypeOf(reflectType(bool))) {
      return true;
    }

    if (typeMirror.isSubtypeOf(reflectType(String))) {
      return parameterValue;
    }

    final classMirror = typeMirror as ClassMirror;
    var parseDecl = classMirror.declarations[#parse];
    if (parseDecl == null) {
      throw new StateError("Invalid binding. Type '${MirrorSystem.getName(classMirror.simpleName)}' does not implement 'parse'.");
    }

    try {
      return classMirror.invoke(parseDecl.simpleName, [parameterValue]).reflectee;
    } catch (_) {
      throw new Response.badRequest(body: {"error": "invalid value for '$externalName'"});
    }
  }
}

class HTTPValueBinding {
  HTTPValueBinding(this.value, {this.symbol});

  HTTPValueBinding.deferred(this.deferredBinder, {this.symbol});

  HTTPValueBinding.error(this.errorMessage);

  Symbol symbol;
  dynamic value;
  RESTControllerParameterBinder deferredBinder;
  String errorMessage;
}

class HTTPPath extends HTTPBinding {
  HTTPPath(String segment) : super(segment);

  @override
  String get type => "Path";

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    return convertParameterWithMirror(request.path.variables[externalName], intoType);
  }
}

class HTTPHeader extends HTTPBinding {
  HTTPHeader(String header) : super(header);

  @override
  String get type => "Header";

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    var value = request.raw.headers[externalName];
    return convertParameterListWithMirror(value, intoType);
  }
}

class HTTPQuery extends HTTPBinding {
  HTTPQuery(String key) : super(key);

  @override
  String get type => "Query Parameter";

  @override
  bool validateType(TypeMirror type) {
    if (super.validateType(type)) {
      return true;
    }

    return type.isAssignableTo(reflectType(bool));
  }

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    var queryParameters = request.raw.uri.queryParametersAll;
    dynamic value = queryParameters[externalName];
    if (value == null) {
      if (requestHasFormData(request)) {
        value = request.body.asMap()[externalName];
      }
    }

    return convertParameterListWithMirror(value, intoType);
  }
}

class HTTPBody extends HTTPBinding {
  HTTPBody() : super(null);

  @override
  String get type => "Body";

  @override
  bool validateType(TypeMirror type) {
    if (type.isAssignableTo(reflectType(List))) {
      return validateType(type.typeArguments.first);
    }

    return type.isAssignableTo(reflectType(HTTPSerializable));
  }

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    if (request.body.isEmpty) {
      return null;
    }

    if (intoType.isAssignableTo(reflectType(HTTPSerializable))) {
      if (!reflectType(request.body.decodedType).isSubtypeOf(reflectType(Map))) {
        throw new Response(422, null, {"error": "unexpected request entity data type"});
      }

      var value = intoType.newInstance(new Symbol(""), []).reflectee as HTTPSerializable;
      value.readFromMap(request.body.asMap());

      return value;
    } else if (intoType.isSubtypeOf(reflectType(List))) {
      if (!reflectType(request.body.decodedType).isSubtypeOf(reflectType(List))) {
        throw new Response(422, null, {"error": "unexpected request entity data type"});
      }

      var bodyList = request.body.asList();
      if (bodyList.isEmpty) {
        return [];
      }

      var typeArg = intoType.typeArguments.first as ClassMirror;
      return bodyList.map((object) {
        if (!reflectType(object.runtimeType).isSubtypeOf(reflectType(Map))) {
          throw new Response(422, null, {"error": "unexpected request entity data type"});
        }

        var value = typeArg.newInstance(new Symbol(""), []).reflectee as HTTPSerializable;
        value.readFromMap(object);

        return value;
      }).toList();
    }

    throw new Response(422, null, {"error": "unexpected request entity data type"});
  }
}

class HTTPBodyBindingException implements Exception {
  HTTPBodyBindingException(this.message);

  String message;

  @override
  String toString() => message;
}
