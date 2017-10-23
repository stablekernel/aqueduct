import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'http_controller.dart';
import 'http_controller_binding.dart';
import 'request.dart';
import 'response.dart';
import 'serializable.dart';
import 'http_response_exception.dart';

class InternalControllerException implements Exception {
  final String message;
  final int statusCode;
  final Map<String, String> additionalHeaders;
  final String errorMessage;

  InternalControllerException(this.message, this.statusCode, {Map<String, String> headers, String errorMessage})
      : this.additionalHeaders = headers,
        this.errorMessage = errorMessage;

  Response get response {
    var bodyMap;
    if (errorMessage != null) {
      bodyMap = {"error": errorMessage};
    }
    return new Response(statusCode, additionalHeaders, bodyMap);
  }

  @override
  String toString() => "InternalControllerException: $message";
}

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

class HTTPRequestBinding {
  Symbol methodSymbol;
  Map<Symbol, dynamic> properties = {};
  List<dynamic> positionalMethodArguments = [];
  Map<Symbol, dynamic> optionalMethodArguments = {};
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

class HTTPControllerBinder {
  HTTPControllerBinder(Type controllerType) {
    var allDeclarations = reflectClass(controllerType).declarations;

    var boundProperties = allDeclarations.values
        .where((decl) => decl is VariableMirror)
        .where((decl) => decl.metadata.any((im) => im.reflectee is Bind))
        .map((decl) {
      var isRequired = allDeclarations[decl.simpleName].metadata.any((im) => im.reflectee is HTTPRequiredParameter);
      return new HTTPControllerParameterBinder(decl, isRequired: isRequired);
    });
    propertyBinders.addAll(boundProperties);

    reflectClass(controllerType)
        .instanceMembers
        .values
        .where(isResponderMethod)
        .map((decl) => new HTTPControllerMethodBinder(decl))
        .forEach((HTTPControllerMethodBinder method) {
      var key = HTTPControllerMethodBinder.generateKey(method.httpMethod.externalName, method.pathParameters.length);

      methodBinders[key] = method;
    });
  }

  static Map<Type, HTTPControllerBinder> controllerBinders = {};

  static HTTPControllerBinder binderForType(Type t) {
    var binder = controllerBinders[t];
    if (binder != null) {
      return binder;
    }

    controllerBinders[t] = new HTTPControllerBinder(t);
    return controllerBinders[t];
  }

  // At the end of this method, request.body.decodedData will have been invoked.
  static Future<HTTPRequestBinding> bindRequest(HTTPController controller, Request request) async {
    var controllerBinder = binderForType(controller.runtimeType);
    var methodBinder = controllerBinder.methodBinderForRequest(request);
    if (methodBinder == null) {
      var allowHeaders = {
        "Allow": controllerBinder.allowedMethodsForArity(request.path.variables?.length ?? 0).join(", ")
      };
      throw new InternalControllerException("No operation found", 405, headers: allowHeaders);
    }

    var parseWith = (HTTPControllerParameterBinder binder) {
      var value = binder.parse(request);
      if (value == null && binder.isRequired) {
        return new HTTPValueBinding.error("Missing ${binder.binding.type} '${binder.name ?? ""}'");
      }

      return new HTTPValueBinding(value, symbol: binder.symbol);
    };

    var initiallyBindWith = (HTTPControllerParameterBinder binder) {
      if (binder.binding is HTTPBody || (binder.binding is HTTPQuery && requestHasFormData(request))) {
        return new HTTPValueBinding.deferred(binder, symbol: binder.symbol);
      }

      return parseWith(binder);
    };

    var properties = controllerBinder.propertyBinders.map(initiallyBindWith).toList();
    var positional = methodBinder.positionalParameters.map(initiallyBindWith).toList();
    var optional = methodBinder.optionalParameters.map(initiallyBindWith).toList();
    var flattened = [properties, positional, optional].expand((x) => x).toList();

    var errorMessage = flattened.where((v) => v.errorMessage != null).map((v) => v.errorMessage).join(", ");

    if (errorMessage.isNotEmpty) {
      throw new InternalControllerException("Missing required values", 400, errorMessage: errorMessage);
    }

    if (!request.body.isEmpty) {
      controller.willDecodeRequestBody(request.body);
      await request.body.decodedData;
      controller.didDecodeRequestBody(request.body);
    }

    flattened.forEach((boundValue) {
      if (boundValue.deferredBinder != null) {
        var output = parseWith(boundValue.deferredBinder);
        boundValue.value = output.value;
        boundValue.errorMessage = output.errorMessage;
      }
    });

    // Recheck error after deferred
    errorMessage = flattened.where((v) => v.errorMessage != null).map((v) => v.errorMessage).join(", ");

    if (errorMessage.isNotEmpty) {
      throw new InternalControllerException("Missing required values", 400, errorMessage: errorMessage);
    }

    return new HTTPRequestBinding()
      ..methodSymbol = methodBinder.methodSymbol
      ..positionalMethodArguments = positional.map((v) => v.value).toList()
      ..optionalMethodArguments = toSymbolMap(optional)
      ..properties = toSymbolMap(properties);
  }

  Map<String, HTTPControllerMethodBinder> methodBinders = {};
  List<HTTPControllerParameterBinder> propertyBinders = [];

  HTTPControllerMethodBinder methodBinderForRequest(Request req) {
    var key = HTTPControllerMethodBinder.generateKey(req.innerRequest.method, req.path.orderedVariableNames.length);

    return methodBinders[key];
  }

  // Used to respond with 405 when there is no operation method for HTTP method
  List<String> allowedMethodsForArity(int arity) {
    return methodBinders.values
        .where((m) => m.pathParameters.length == arity)
        .map((m) => m.httpMethod.externalName.toUpperCase())
        .toList();
  }

  // Used during document generation
  bool hasRequiredBindingsForMethod(MethodMirror mm) {
    if (propertyBinders.any((binder) => binder.isRequired)) {
      return true;
    }

    // todo (joeconwaystk): seems like we are creating a duplicate HTTPControllerMethodBinder here
    if (isResponderMethod(mm)) {
      HTTPControllerMethodBinder method = new HTTPControllerMethodBinder(mm);
      var key = HTTPControllerMethodBinder.generateKey(method.httpMethod.externalName, method.pathParameters.length);

      return methodBinders[key].positionalParameters.any((p) => p.binding is! HTTPPath && p.isRequired);
    }

    return false;
  }
}

class HTTPControllerMethodBinder {
  HTTPControllerMethodBinder(MethodMirror mirror) {
    httpMethod = methodBindingFrom(mirror);
    methodSymbol = mirror.simpleName;

    positionalParameters = mirror.parameters
        .where((pm) => !pm.isOptional)
        .map((pm) => new HTTPControllerParameterBinder(pm, isRequired: true))
        .toList();
    optionalParameters = mirror.parameters
        .where((pm) => pm.isOptional)
        .map((pm) => new HTTPControllerParameterBinder(pm, isRequired: false))
        .toList();
  }

  static String generateKey(String httpMethod, int pathArity) {
    return "${httpMethod.toLowerCase()}/$pathArity";
  }

  Symbol methodSymbol;
  HTTPMethod httpMethod;
  List<HTTPControllerParameterBinder> positionalParameters = [];
  List<HTTPControllerParameterBinder> optionalParameters = [];

  List<HTTPControllerParameterBinder> get pathParameters =>
      positionalParameters.where((p) => p.binding is HTTPPath).toList();
}

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

bool requestHasFormData(Request request) {
  var contentType = request.innerRequest.headers.contentType;
  if (contentType != null &&
      contentType.primaryType == "application" &&
      contentType.subType == "x-www-form-urlencoded") {
    return true;
  }

  return false;
}

Map<Symbol, dynamic> toSymbolMap(List<HTTPValueBinding> boundValues) {
  return new Map.fromIterable(boundValues.where((v) => v.value != null),
      key: (HTTPValueBinding v) => v.symbol, value: (HTTPValueBinding v) => v.value);
}

class HTTPMethod extends HTTPBinding {
  HTTPMethod(String method) : super(method.toLowerCase());

  @override
  String get type => "Method";

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    return request.innerRequest.method.toLowerCase();
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
    var value = request.innerRequest.headers[externalName];
    return convertParameterListWithMirror(value, intoType);
  }
}

class HTTPQuery extends HTTPBinding {
  HTTPQuery(String key) : super(key);

  @override
  String get type => "Query Parameter";

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    var queryParameters = request.innerRequest.uri.queryParametersAll;
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

    throw new _HTTPBodyBindingException(
        "Failed to bind HTTPBody: ${intoType.reflectedType} is not HTTPSerializable or List<HTTPSerializable>");
  }
}

class _HTTPBodyBindingException implements Exception {
  _HTTPBodyBindingException(this.message);

  String message;

  @override
  String toString() => message;
}

bool isResponderMethod(DeclarationMirror m) {
  return methodBindingFrom(m) != null;
}

HTTPMethod methodBindingFrom(DeclarationMirror m) {
  if (m is! MethodMirror) {
    return null;
  }

  MethodMirror method = m;
  if (!method.isRegularMethod || method.isStatic) {
    return null;
  }

  Bind metadata = method.metadata.firstWhere((im) => im.reflectee is Bind, orElse: () => null)?.reflectee;
  if (metadata == null) {
    return null;
  }

  var binding = metadata.binding;
  if (binding is! HTTPMethod) {
    return null;
  }

  return binding;
}
