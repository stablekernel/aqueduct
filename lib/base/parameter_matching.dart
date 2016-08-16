part of aqueduct;

/// Parent class for annotations used for optional parameters in controller methods
abstract class _HTTPParameter {
  const _HTTPParameter.required(this.externalName) : isRequired = true;
  const _HTTPParameter.optional(this.externalName) : isRequired = false;

  /// The name of the variable in the HTTP request.
  final String externalName;

  /// If [isRequired] is true, requests missing this parameter will not be directed
  /// to the controller method and will return a 400 immediately.
  final bool isRequired;
}

/// Metadata indicating a parameter to a controller's method should be set from
/// the HTTP header indicated by the [header] field. The [header] value is case-
/// insensitive.
class HTTPHeader extends _HTTPParameter {

  /// Creates a required HTTP header parameter.
  const HTTPHeader.required(String header) : super.required(header);

  /// Creates an optional HTTP header parameter.
  const HTTPHeader.optional(String header) : super.optional(header);
}

/// Metadata indicating a parameter to a controller's method should be set from
/// the query value (or form-encoded body) from the indicated [key]. The [key]
/// value is case-sensitive.
class HTTPQuery extends _HTTPParameter {

  /// Creates a required HTTP query parameter.
  const HTTPQuery.required(String key) : super.required(key);

  /// Creates an optional HTTP query parameter.
  const HTTPQuery.optional(String key) : super.optional(key);
}

class _HTTPControllerCache {
  static Map<Type, _HTTPControllerCache> controllerCache = {};
  static _HTTPControllerCache cacheForType(Type t) {
    var cacheItem = controllerCache[t];
    if (cacheItem != null) {
      return cacheItem;
    }

    controllerCache[t] = new _HTTPControllerCache(t);
    return controllerCache[t];
  }

  _HTTPControllerCache(Type controllerType) {
    var allDeclarations = reflectClass(controllerType).declarations;

    allDeclarations.values
        .where((decl) => decl is VariableMirror)
        .where((decl) => decl.metadata.any((im) => im.reflectee is _HTTPParameter))
        .map((decl) => new _HTTPControllerCachedParameter(decl))
        .forEach((_HTTPControllerCachedParameter param) {
          propertyCache[param.symbol] = param;
        });

    allDeclarations.values
        .where((decl) => decl is MethodMirror)
        .where((decl) => decl.metadata.any((im) => im.reflectee is HTTPMethod))
        .map((decl) => new _HTTPControllerCachedMethod(decl))
        .forEach((_HTTPControllerCachedMethod method) {
          var key = _HTTPControllerCachedMethod.generateHandlerMethodKey(method.httpMethod.method, method.orderedPathParameters.map((p) => p.name).toList());
          methodCache[key] = method;
        });
  }

  Map<String, _HTTPControllerCachedMethod> methodCache = {};
  Map<Symbol, _HTTPControllerCachedParameter> propertyCache = {};

  _HTTPControllerCachedMethod mapperForRequest(Request req) {
    return methodCache[_HTTPControllerCachedMethod.generateHandlerMethodKey(req.innerRequest.method, req.path.orderedVariableNames)];
  }

  Map<Symbol, dynamic> propertiesFromRequest(HttpHeaders headers, Map<String, List<String>> queryParameters) {
    return _parseParametersFromRequest(propertyCache, headers, queryParameters);
  }
}

class _HTTPControllerCachedMethod {
  static String generateHandlerMethodKey(String httpMethod, List<String> params) {
    return "${httpMethod.toLowerCase()}-" + params.map((pathParam) => pathParam).join("-");
  }

  _HTTPControllerCachedMethod(MethodMirror mirror) {
    List<_HTTPControllerCachedParameter> params = mirror.parameters
        .where((pm) => !pm.isOptional)
        .map((pm) => new _HTTPControllerCachedParameter(pm))
        .toList();

    Iterable<_HTTPControllerCachedParameter> optionalParams = mirror.parameters
        .where((pm) => pm.metadata.any((im) => im.reflectee is _HTTPParameter))
        .map((pm) => new _HTTPControllerCachedParameter(pm));

    httpMethod = mirror.metadata.firstWhere((m) => m.reflectee is HTTPMethod).reflectee;
    methodSymbol = mirror.simpleName;
    orderedPathParameters = params;
    optionalParameters = new Map.fromIterable(optionalParams, key: (_HTTPControllerCachedParameter p) => p.symbol, value: (p) => p);;
  }

  Symbol methodSymbol;
  HTTPMethod httpMethod;
  List<_HTTPControllerCachedParameter> orderedPathParameters = [];
  Map<Symbol, _HTTPControllerCachedParameter> optionalParameters = {};

  List<dynamic> orderedParametersFromRequest(Request req) {
    return orderedPathParameters
        .map((param) => _convertParameterWithMirror(req.path.variables[param.name], param.typeMirror))
        .toList();
  }

  Map<Symbol, dynamic> optionalParametersFromRequest(HttpHeaders headers, Map<String, List<String>> queryParameters) {
    return _parseParametersFromRequest(optionalParameters, headers, queryParameters);
  }
}

class _HTTPControllerCachedParameter {
  _HTTPControllerCachedParameter(VariableMirror mirror) {
    symbol = mirror.simpleName;
    httpParameter = mirror.metadata.firstWhere((im) => im.reflectee is _HTTPParameter, orElse: () => null)?.reflectee;
    typeMirror = mirror.type;
  }

  Symbol symbol;
  String get name => MirrorSystem.getName(symbol);
  TypeMirror typeMirror;
  _HTTPParameter httpParameter;
}

enum _HTTPControllerMissingParameterType {
  header,
  query
}

class _HTTPControllerMissingParameter {
  _HTTPControllerMissingParameter(this.type, this.externalName);

  _HTTPControllerMissingParameterType type;
  String externalName;
}

Map<Symbol, dynamic> _parseParametersFromRequest(Map<Symbol, _HTTPControllerCachedParameter> mappings, HttpHeaders headers, Map<String, List<String>> queryParameters) {
  return mappings.keys.fold({}, (m, sym) {
    var mapper = mappings[sym];
    var parameterType = null;
    var value = null;

    if (mapper.httpParameter is HTTPQuery) {
      parameterType = _HTTPControllerMissingParameterType.query;
      value = queryParameters[mapper.httpParameter.externalName];
    } else if (mapper.httpParameter is HTTPMethod) {
      parameterType = _HTTPControllerMissingParameterType.header;
      value = headers[mapper.httpParameter.externalName];
    }

    if (value != null) {
      m[sym] = _convertParameterListWithMirror(value, mapper.typeMirror);
    } else if (mapper.httpParameter.isRequired) {
      m[sym] = new _HTTPControllerMissingParameter(parameterType, mapper.httpParameter.externalName);
    }

    return m;
  });
}

dynamic _convertParameterListWithMirror(List<String> parameterValues, TypeMirror typeMirror) {
  if (parameterValues == null) {
    return null;
  }

  if (typeMirror.isSubtypeOf(reflectType(List))) {
    return parameterValues.map((str) => _convertParameterWithMirror(str, typeMirror.typeArguments.first)).toList();
  } else {
    return _convertParameterWithMirror(parameterValues.first, typeMirror);
  }
}

dynamic _convertParameterWithMirror(String parameterValue, TypeMirror typeMirror) {
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
    var parseDecl = typeMirror.declarations[new Symbol("parse")];
    if (parseDecl != null) {
      try {
        var reflValue = typeMirror.invoke(parseDecl.simpleName, [parameterValue]);
        return reflValue.reflectee;
      } catch (e) {
        throw new _InternalControllerException("Invalid value for parameter type", HttpStatus.BAD_REQUEST, responseMessage: "URI parameter is wrong type");
      }
    }
  }

  // If we get here, then it wasn't a string and couldn't be parsed, and we should throw?
  throw new _InternalControllerException("Invalid path parameter type, types must be String or implement parse", HttpStatus.INTERNAL_SERVER_ERROR, responseMessage: "URI parameter is wrong type");
}

