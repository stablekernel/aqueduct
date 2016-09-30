part of aqueduct;

/// Parent class for annotations used for optional parameters in controller methods
abstract class _HTTPParameter {
  const _HTTPParameter(this.externalName);

  /// The name of the variable in the HTTP request.
  final String externalName;
}

/// Marks a controller HTTPHeader or HTTPQuery property as required.
const HTTPRequiredParameter requiredHTTPParameter = const HTTPRequiredParameter();
class HTTPRequiredParameter {
  const HTTPRequiredParameter();
}

/// Specifies the route path variable for the associated controller method argument.
class HTTPPath extends _HTTPParameter {
  const HTTPPath(String segment) : super(segment);
}

/// Metadata indicating a parameter to a controller's method should be set from
/// the HTTP header indicated by the [header] field. The [header] value is case-
/// insensitive.
class HTTPHeader extends _HTTPParameter {
  const HTTPHeader(String header) : super(header);
}

/// Metadata indicating a parameter to a controller's method should be set from
/// the query value (or form-encoded body) from the indicated [key]. The [key]
/// value is case-sensitive.
class HTTPQuery extends _HTTPParameter {
  const HTTPQuery(String key) : super(key);
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
        .forEach((decl) {
          _HTTPControllerCachedParameter param;
          var isRequired = allDeclarations[decl.simpleName].metadata.any((im) => im.reflectee is HTTPRequiredParameter);
          if (isRequired) {
            hasControllerRequiredParameter = true;
            param = new _HTTPControllerCachedParameter(decl, isRequired: true);
          } else {
            param = new _HTTPControllerCachedParameter(decl, isRequired: false);
          }

          propertyCache[param.symbol] = param;
        });

    allDeclarations.values
        .where((decl) => decl is MethodMirror)
        .where((decl) => decl.metadata.any((im) => im.reflectee is HTTPMethod))
        .map((decl) => new _HTTPControllerCachedMethod(decl))
        .forEach((_HTTPControllerCachedMethod method) {
          var key = _HTTPControllerCachedMethod.generateRequestMethodKey(method.httpMethod.method, method.pathParameters.length);

          methodCache[key] = method;
        });
  }

  Map<String, _HTTPControllerCachedMethod> methodCache = {};
  Map<Symbol, _HTTPControllerCachedParameter> propertyCache = {};
  bool hasControllerRequiredParameter = false;

  bool hasRequiredParametersForMethod(MethodMirror mm) {
    if (hasControllerRequiredParameter) {
      return true;
    }

    if (mm is MethodMirror && mm.metadata.any((im) => im.reflectee is HTTPMethod)) {
      _HTTPControllerCachedMethod method = new _HTTPControllerCachedMethod(mm);
      var key = _HTTPControllerCachedMethod.generateRequestMethodKey(method.httpMethod.method, method.pathParameters.length);

      return methodCache[key].positionalParameters.any((p) => p.httpParameter is! HTTPPath && p.isRequired);
    }

    return false;
  }

  _HTTPControllerCachedMethod mapperForRequest(Request req) {
    var key = _HTTPControllerCachedMethod.generateRequestMethodKey(req.innerRequest.method, req.path.orderedVariableNames.length);

    return methodCache[key];
  }

  Map<Symbol, dynamic> propertiesFromRequest(HttpHeaders headers, Map<String, List<String>> queryParameters) {
    return _parseParametersFromRequest(propertyCache, headers, queryParameters);
  }
}

class _HTTPControllerCachedMethod {
  static String generateRequestMethodKey(String httpMethod, int arity) {
    return "${httpMethod.toLowerCase()}/$arity";
  }

  _HTTPControllerCachedMethod(MethodMirror mirror) {
    httpMethod = mirror.metadata.firstWhere((m) => m.reflectee is HTTPMethod).reflectee;
    methodSymbol = mirror.simpleName;
    positionalParameters = mirror.parameters
        .where((pm) => !pm.isOptional)
        .map((pm) => new _HTTPControllerCachedParameter(pm, isRequired: true))
        .toList();
    optionalParameters = new Map.fromIterable(mirror.parameters.where((pm) => pm.isOptional).map((pm) => new _HTTPControllerCachedParameter(pm, isRequired: false)),
        key: (_HTTPControllerCachedParameter p) => p.symbol,
        value: (p) => p);
  }

  Symbol methodSymbol;
  HTTPMethod httpMethod;
  List<_HTTPControllerCachedParameter> positionalParameters = [];
  Map<Symbol, _HTTPControllerCachedParameter> optionalParameters = {};
  List<_HTTPControllerCachedParameter> get pathParameters => positionalParameters.where((p) => p.httpParameter is HTTPPath).toList();

  List<dynamic> positionalParametersFromRequest(Request req, Map<String, List<String>> queryParameters) {
    return positionalParameters.map((param) {
      if (param.httpParameter is HTTPPath) {
        return _convertParameterWithMirror(req.path.variables[param.name], param.typeMirror);
      } else if (param.httpParameter is HTTPQuery) {
        return _convertParameterListWithMirror(queryParameters[param.name], param.typeMirror)
          ?? new _HTTPControllerMissingParameter(_HTTPControllerMissingParameterType.query, param.name);
      } else if (param.httpParameter is HTTPHeader) {
        return _convertParameterListWithMirror(req.innerRequest.headers[param.name], param.typeMirror)
          ?? new _HTTPControllerMissingParameter(_HTTPControllerMissingParameterType.header, param.name);
      }
    })
    .toList();
  }

  Map<Symbol, dynamic> optionalParametersFromRequest(HttpHeaders headers, Map<String, List<String>> queryParameters) {
    return _parseParametersFromRequest(optionalParameters, headers, queryParameters);
  }
}

class _HTTPControllerCachedParameter {
  _HTTPControllerCachedParameter(VariableMirror mirror, {this.isRequired: false}) {
    symbol = mirror.simpleName;
    httpParameter = mirror.metadata.firstWhere((im) => im.reflectee is _HTTPParameter, orElse: () => null)?.reflectee;
    typeMirror = mirror.type;
  }

  Symbol symbol;
  String get name => httpParameter.externalName;
  TypeMirror typeMirror;
  _HTTPParameter httpParameter;
  bool isRequired;
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
    List<String> value = null;
    var paramType = null;

    if (mapper.httpParameter is HTTPQuery) {
      paramType = _HTTPControllerMissingParameterType.query;
      value = queryParameters[mapper.httpParameter.externalName];
    } else if (mapper.httpParameter is HTTPHeader) {
      paramType = _HTTPControllerMissingParameterType.header;
      value = headers[mapper.httpParameter.externalName];
    }

    if (value != null) {
      m[sym] = _convertParameterListWithMirror(value, mapper.typeMirror);
    } else if (mapper.isRequired) {
      m[sym] = new _HTTPControllerMissingParameter(paramType, mapper.httpParameter.externalName);
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

