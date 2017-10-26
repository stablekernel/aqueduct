import 'dart:io';
import 'dart:mirrors';

import '../serializable.dart';
import '../http_response_exception.dart';
import '../request.dart';
import 'internal.dart';

/// Parent class for annotations used for optional parameters in controller methods
abstract class HTTPBinding {
  HTTPBinding(this.externalName);

  /// The name of the variable in the HTTP request.
  final String externalName;

  String get type;

  dynamic parse(ClassMirror intoType, Request request);

  dynamic convertParameterListWithMirror(List<String> parameterValues, TypeMirror typeMirror) {
    if (parameterValues == null) {
      return null;
    }

    if (typeMirror.isSubtypeOf(reflectType(List))) {
      return parameterValues.map((str) => convertParameterWithMirror(str, typeMirror.typeArguments.first)).toList();
    } else {
      if (parameterValues.length > 1) {
        throw new InternalControllerException("Duplicate value for parameter", HttpStatus.BAD_REQUEST,
            errorMessage: "Duplicate parameter for non-List parameter type");
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

    if (typeMirror is ClassMirror) {
      var parseDecl = typeMirror.declarations[#parse];
      if (parseDecl != null) {
        try {
          var reflValue = typeMirror.invoke(parseDecl.simpleName, [parameterValue]);
          return reflValue.reflectee;
        } catch (e) {
          throw new InternalControllerException("Invalid value for parameter type", HttpStatus.BAD_REQUEST,
              errorMessage: "URI parameter is wrong type");
        }
      }
    }

    // If we get here, then it wasn't a string and couldn't be parsed, and we should throw?
    throw new InternalControllerException(
        "Invalid path parameter type, types must be String or implement parse", HttpStatus.INTERNAL_SERVER_ERROR,
        errorMessage: "URI parameter is wrong type");
  }
}


class HTTPValueBinding {
  HTTPValueBinding(this.value, {this.symbol});

  HTTPValueBinding.deferred(this.deferredBinder, {this.symbol});

  HTTPValueBinding.error(this.errorMessage);

  Symbol symbol;
  dynamic value;
  HTTPControllerParameterBinder deferredBinder;
  String errorMessage;
}

class HTTPMethod extends HTTPBinding {
  HTTPMethod(String method) : super(method.toLowerCase());

  @override
  String get type => "Method";

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    return request.raw.method.toLowerCase();
  }
}

class HTTPPath extends HTTPBinding {
  HTTPPath(String segment) : super(segment);

  @override
  String get type => null;

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
  dynamic parse(ClassMirror intoType, Request request) {
    if (request.body.isEmpty) {
      return null;
    }

    if (intoType.isAssignableTo(reflectType(HTTPSerializable))) {
      if (!reflectType(request.body.decodedType).isSubtypeOf(reflectType(Map))) {
        throw new HTTPResponseException(400, "Expected Map, got ${request.body.decodedType}");
      }

      var value = intoType.newInstance(new Symbol(""), []).reflectee as HTTPSerializable;
      value.readFromMap(request.body.asMap());

      return value;
    } else if (intoType.isSubtypeOf(reflectType(List))) {
      if (!reflectType(request.body.decodedType).isSubtypeOf(reflectType(List))) {
        throw new HTTPResponseException(400, "Expected List, got ${request.body.decodedType}");
      }

      var bodyList = request.body.asList();
      if (bodyList.isEmpty) {
        return [];
      }

      var typeArg = intoType.typeArguments.first as ClassMirror;
      return bodyList.map((object) {
        if (!reflectType(object.runtimeType).isSubtypeOf(reflectType(Map))) {
          throw new HTTPResponseException(400, "Expected List<Map>, got List<${object.runtimeType}>");
        }

        var value = typeArg.newInstance(new Symbol(""), []).reflectee as HTTPSerializable;
        value.readFromMap(object);

        return value;
      }).toList();
    }

    throw new HTTPBodyBindingException(
        "Failed to bind HTTPBody: ${intoType.reflectedType} is not HTTPSerializable or List<HTTPSerializable>");
  }
}

class HTTPBodyBindingException implements Exception {
  HTTPBodyBindingException(this.message);

  String message;

  @override
  String toString() => message;
}