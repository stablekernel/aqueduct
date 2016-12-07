import 'dart:io';
import 'dart:mirrors';

import 'controller_routing.dart';
import 'request.dart';
import 'response.dart';

class InternalControllerException implements Exception {
  final String message;
  final int statusCode;
  final HttpHeaders additionalHeaders;
  final String responseMessage;

  InternalControllerException(this.message, this.statusCode,
      {HttpHeaders additionalHeaders: null, String responseMessage: null})
      : this.additionalHeaders = additionalHeaders,
        this.responseMessage = responseMessage;

  Response get response {
    var headerMap = <String, dynamic>{};
    additionalHeaders?.forEach((k, _) {
      headerMap[k] = additionalHeaders.value(k);
    });

    var bodyMap = null;
    if (responseMessage != null) {
      bodyMap = {"error": responseMessage};
    }
    return new Response(statusCode, headerMap, bodyMap);
  }
}

/// Parent class for annotations used for optional parameters in controller methods
abstract class HTTPParameter {
  const HTTPParameter(this.externalName);

  /// The name of the variable in the HTTP request.
  final String externalName;
}

class HTTPControllerCache {
  static Map<Type, HTTPControllerCache> controllerCache = {};
  static HTTPControllerCache cacheForType(Type t) {
    var cacheItem = controllerCache[t];
    if (cacheItem != null) {
      return cacheItem;
    }

    controllerCache[t] = new HTTPControllerCache(t);
    return controllerCache[t];
  }

  HTTPControllerCache(Type controllerType) {
    var allDeclarations = reflectClass(controllerType).declarations;

    allDeclarations.values
        .where((decl) => decl is VariableMirror)
        .where(
            (decl) => decl.metadata.any((im) => im.reflectee is HTTPParameter))
        .forEach((decl) {
      HTTPControllerCachedParameter param;
      var isRequired = allDeclarations[decl.simpleName]
          .metadata
          .any((im) => im.reflectee is HTTPRequiredParameter);
      if (isRequired) {
        hasControllerRequiredParameter = true;
        param = new HTTPControllerCachedParameter(decl, isRequired: true);
      } else {
        param = new HTTPControllerCachedParameter(decl, isRequired: false);
      }

      propertyCache[param.symbol] = param;
    });

    allDeclarations.values
        .where((decl) => decl is MethodMirror)
        .where((decl) => decl.metadata.any((im) => im.reflectee is HTTPMethod))
        .map((decl) => new HTTPControllerCachedMethod(decl))
        .forEach((HTTPControllerCachedMethod method) {
      var key = HTTPControllerCachedMethod.generateRequestMethodKey(
          method.httpMethod.method, method.pathParameters.length);

      methodCache[key] = method;
    });
  }

  Map<String, HTTPControllerCachedMethod> methodCache = {};
  Map<Symbol, HTTPControllerCachedParameter> propertyCache = {};
  bool hasControllerRequiredParameter = false;

  bool hasRequiredParametersForMethod(MethodMirror mm) {
    if (hasControllerRequiredParameter) {
      return true;
    }

    if (mm is MethodMirror &&
        mm.metadata.any((im) => im.reflectee is HTTPMethod)) {
      HTTPControllerCachedMethod method = new HTTPControllerCachedMethod(mm);
      var key = HTTPControllerCachedMethod.generateRequestMethodKey(
          method.httpMethod.method, method.pathParameters.length);

      return methodCache[key]
          .positionalParameters
          .any((p) => p.httpParameter is! HTTPPath && p.isRequired);
    }

    return false;
  }

  HTTPControllerCachedMethod mapperForRequest(Request req) {
    var key = HTTPControllerCachedMethod.generateRequestMethodKey(
        req.innerRequest.method, req.path.orderedVariableNames.length);

    return methodCache[key];
  }

  Map<Symbol, dynamic> propertiesFromRequest(
      HttpHeaders headers, Map<String, List<String>> queryParameters) {
    return parseParametersFromRequest(propertyCache, headers, queryParameters);
  }

  List<String> allowedMethodsForArity(int arity) {
    return methodCache.values
        .where((m) => m.pathParameters.length == arity)
        .map((m) => m.httpMethod.method.toUpperCase())
        .toList();
  }
}

class HTTPControllerCachedMethod {
  static String generateRequestMethodKey(String httpMethod, int arity) {
    return "${httpMethod.toLowerCase()}/$arity";
  }

  HTTPControllerCachedMethod(MethodMirror mirror) {
    httpMethod =
        mirror.metadata.firstWhere((m) => m.reflectee is HTTPMethod).reflectee;
    methodSymbol = mirror.simpleName;
    positionalParameters = mirror.parameters
        .where((pm) => !pm.isOptional)
        .map((pm) => new HTTPControllerCachedParameter(pm, isRequired: true))
        .toList();
    optionalParameters = new Map.fromIterable(
        mirror.parameters.where((pm) => pm.isOptional).map(
            (pm) => new HTTPControllerCachedParameter(pm, isRequired: false)),
        key: (HTTPControllerCachedParameter p) => p.symbol,
        value: (p) => p);
  }

  Symbol methodSymbol;
  HTTPMethod httpMethod;
  List<HTTPControllerCachedParameter> positionalParameters = [];
  Map<Symbol, HTTPControllerCachedParameter> optionalParameters = {};
  List<HTTPControllerCachedParameter> get pathParameters =>
      positionalParameters.where((p) => p.httpParameter is HTTPPath).toList();

  List<dynamic> positionalParametersFromRequest(
      Request req, Map<String, List<String>> queryParameters) {
    return positionalParameters.map((param) {
      if (param.httpParameter is HTTPPath) {
        return convertParameterWithMirror(
            req.path.variables[param.name], param.typeMirror);
      } else if (param.httpParameter is HTTPQuery) {
        return convertParameterListWithMirror(
                queryParameters[param.name], param.typeMirror) ??
            new HTTPControllerMissingParameter(
                HTTPControllerMissingParameterType.query, param.name);
      } else if (param.httpParameter is HTTPHeader) {
        return convertParameterListWithMirror(
                req.innerRequest.headers[param.name], param.typeMirror) ??
            new HTTPControllerMissingParameter(
                HTTPControllerMissingParameterType.header, param.name);
      }
    }).toList();
  }

  Map<Symbol, dynamic> optionalParametersFromRequest(
      HttpHeaders headers, Map<String, List<String>> queryParameters) {
    return parseParametersFromRequest(
        optionalParameters, headers, queryParameters);
  }
}

class HTTPControllerCachedParameter {
  HTTPControllerCachedParameter(VariableMirror mirror,
      {this.isRequired: false}) {
    symbol = mirror.simpleName;
    httpParameter = mirror.metadata
        .firstWhere((im) => im.reflectee is HTTPParameter, orElse: () => null)
        ?.reflectee;
    typeMirror = mirror.type;
  }

  Symbol symbol;
  String get name => httpParameter.externalName;
  TypeMirror typeMirror;
  HTTPParameter httpParameter;
  bool isRequired;
}

enum HTTPControllerMissingParameterType { header, query }

class HTTPControllerMissingParameter {
  HTTPControllerMissingParameter(this.type, this.externalName);

  HTTPControllerMissingParameterType type;
  String externalName;
}

Map<Symbol, dynamic> parseParametersFromRequest(
    Map<Symbol, HTTPControllerCachedParameter> mappings,
    HttpHeaders headers,
    Map<String, List<String>> queryParameters) {
  return mappings.keys.fold({}, (m, sym) {
    var mapper = mappings[sym];
    List<String> value = null;
    var paramType = null;

    if (mapper.httpParameter is HTTPQuery) {
      paramType = HTTPControllerMissingParameterType.query;
      value = queryParameters[mapper.httpParameter.externalName];
    } else if (mapper.httpParameter is HTTPHeader) {
      paramType = HTTPControllerMissingParameterType.header;
      value = headers[mapper.httpParameter.externalName];
    }

    if (value != null) {
      m[sym] = convertParameterListWithMirror(value, mapper.typeMirror);
    } else if (mapper.isRequired) {
      m[sym] = new HTTPControllerMissingParameter(
          paramType, mapper.httpParameter.externalName);
    }

    return m;
  });
}

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
      throw new InternalControllerException(
          "Duplicate value for parameter", HttpStatus.BAD_REQUEST,
          responseMessage: "Duplicate parameter for non-List parameter type");
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

  if (typeMirror is ClassMirror) {
    var parseDecl = typeMirror.declarations[#parse];
    if (parseDecl != null) {
      try {
        var reflValue =
            typeMirror.invoke(parseDecl.simpleName, [parameterValue]);
        return reflValue.reflectee;
      } catch (e) {
        throw new InternalControllerException(
            "Invalid value for parameter type", HttpStatus.BAD_REQUEST,
            responseMessage: "URI parameter is wrong type");
      }
    }
  }

  // If we get here, then it wasn't a string and couldn't be parsed, and we should throw?
  throw new InternalControllerException(
      "Invalid path parameter type, types must be String or implement parse",
      HttpStatus.INTERNAL_SERVER_ERROR,
      responseMessage: "URI parameter is wrong type");
}
