import 'dart:mirrors';

import 'package:aqueduct/src/utilities/mirror_helpers.dart';
import 'package:open_api/v3.dart';

import '../request.dart';
import '../response.dart';
import '../serializable.dart';
import 'internal.dart';

/// Parent class for annotations used for optional parameters in controller methods
abstract class BoundInput {
  BoundInput(this.externalName);

  /// The name of the variable in the HTTP request.
  final String externalName;

  String get type;

  APIParameterLocation get location;

  bool validateType(TypeMirror type) {
    if (type.reflectedType == dynamic) {
      return false;
    }

    if (type.isAssignableTo(reflectType(String))) {
      return true;
    } else if (type is ClassMirror && type.staticMembers.containsKey(#parse)) {
      final parseMethod = type.staticMembers[#parse];
      final params =
          parseMethod.parameters.where((p) => !p.isOptional).toList();
      if (params.length == 1 &&
          params.first.type.isAssignableTo(reflectType(String))) {
        return true;
      }
      return false;
    } else if (type.isAssignableTo(reflectType(List))) {
      return validateType(type.typeArguments.first);
    }

    return false;
  }

  dynamic parse(ClassMirror intoType, Request request);

  dynamic convertParameterListWithMirror(
      List<String> parameterValues, TypeMirror typeMirror) {
    if (parameterValues == null) {
      return null;
    }

    if (typeMirror.isSubtypeOf(reflectType(List))) {
      return parameterValues
          .map((str) =>
              convertParameterWithMirror(str, typeMirror.typeArguments.first))
          .toList();
    } else {
      if (parameterValues.length > 1) {
        throw Response.badRequest(body: {
          "error": "multiple values for '$externalName' not expected"
        });
      }
      return convertParameterWithMirror(parameterValues.first, typeMirror);
    }
  }

  dynamic convertParameterWithMirror(
      String parameterValue, TypeMirror typeMirror) {
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
      throw StateError(
          "Invalid binding. Type '${MirrorSystem.getName(classMirror.simpleName)}' does not implement 'parse'.");
    }

    try {
      return classMirror
          .invoke(parseDecl.simpleName, [parameterValue]).reflectee;
    } catch (_) {
      throw Response.badRequest(
          body: {"error": "invalid value for '$externalName'"});
    }
  }
}

class BoundValue {
  BoundValue(this.value, {this.symbol});

  BoundValue.deferred(this.deferredBinder, {this.symbol});

  BoundValue.error(this.errorMessage);

  Symbol symbol;
  dynamic value;
  BoundParameter deferredBinder;
  String errorMessage;
}

class BoundPath extends BoundInput {
  BoundPath(String segment) : super(segment);

  @override
  String get type => "Path";

  @override
  APIParameterLocation get location => APIParameterLocation.path;

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    return convertParameterWithMirror(
        request.path.variables[externalName], intoType);
  }
}

class BoundHeader extends BoundInput {
  BoundHeader(String header) : super(header);

  @override
  String get type => "Header";

  @override
  APIParameterLocation get location => APIParameterLocation.header;

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    var value = request.raw.headers[externalName];
    return convertParameterListWithMirror(value, intoType);
  }
}

class BoundQueryParameter extends BoundInput {
  BoundQueryParameter(String key) : super(key);

  @override
  String get type => "Query Parameter";

  @override
  APIParameterLocation get location => APIParameterLocation.query;

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
    var value = queryParameters[externalName];
    if (value == null) {
      if (requestHasFormData(request)) {
        value = request.body.as<Map<String, List<String>>>()[externalName];
      }
    }

    return convertParameterListWithMirror(value, intoType);
  }
}

class BoundBody extends BoundInput {
  BoundBody() : super(null);

  @override
  String get type => "Body";

  @override
  APIParameterLocation get location => null;

  @override
  bool validateType(TypeMirror type) {
    if (type.isAssignableTo(reflectType(List))) {
      return validateType(type.typeArguments.first);
    }

    return type.isAssignableTo(reflectType(Serializable));
  }

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    if (request.body.isEmpty) {
      return null;
    }

    if (intoType.isSubtypeOf(reflectType(Serializable))) {
      final value =
          intoType.newInstance(const Symbol(""), []).reflectee as Serializable;
      value.readFromMap(request.body.as());

      return value;
    } else if (intoType.isSubtypeOf(reflectType(List))) {
      final bodyList = request.body.as<List<Map<String, dynamic>>>();
      if (bodyList.isEmpty) {
        return [];
      }

      final typeArg = intoType.typeArguments.first as ClassMirror;
      return bodyList.map((object) {
        final value =
            typeArg.newInstance(const Symbol(""), []).reflectee as Serializable;
        value.readFromMap(object);

        return value;
      }).toList();
    }

    return runtimeCast(request.body.as(), intoType);
  }
}

class BoundBodyException implements Exception {
  BoundBodyException(this.message);

  String message;

  @override
  String toString() => message;
}
