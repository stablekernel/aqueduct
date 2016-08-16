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
          propertyCache[new Symbol(param.name)] = param;
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
}

class _HTTPMethodParameterTemplate {

  HTTPController _controller;
  Request _request;
  Symbol _methodSymbol;

  Map<String, List<String>> _queryParameters = {};
  List<String> _missingQueries = [];

  HttpHeaders _headerParameters;
  List<String> _missingHeaders = [];

  _HTTPMethodParameterTemplate._internal(this._controller, this._request, this._methodSymbol);

  _HTTPControllerInvocation parseRequest() {
    var parameterValues = new _HTTPControllerInvocation()
      ..methodSymbolForRequest = _methodSymbol;

    _parseOrderedParameters(parameterValues);
    _parseOptionalParameters();
    _symbolicateControllerParameterValues(parameterValues);
    _symbolicateOptionalParameterValues(parameterValues);

    return parameterValues;
  }

  void _parseOrderedParameters(_HTTPControllerInvocation values) {
    var key = generateHandlerMethodKey(_request.innerRequest.method, _request.path.orderedVariableNames);
    var method = _methodCache[_controller.runtimeType][key];
    values.orderedParametersForRequest = method
        .orderedPathParameters
        .map((param) => _convertParameterWithMirror(_request.path.variables[param.name], param.typeMirror))
        .toList();
  }

  void _parseOptionalParameters() {
    var contentType = _request.innerRequest.headers.contentType;
    if (contentType != null
        &&  contentType.primaryType == _applicationWWWFormURLEncodedContentType.primaryType
        &&  contentType.subType == _applicationWWWFormURLEncodedContentType.subType) {
      _queryParameters = _controller.requestBody ?? {};
    } else {
      _queryParameters = _request.innerRequest.uri.queryParametersAll;
    }

    _headerParameters = _request.innerRequest.headers;
  }

  void _symbolicateControllerParameterValues(_HTTPControllerInvocation values) {
    _symbolicateParameterValues(_controllerLevelParameters[_controller.runtimeType], values.controllerParametersForRequest, values._missingQueries, values._missingHeaders);
  }

  void _symbolicateOptionalParameterValues(_HTTPControllerInvocation values) {
    var key = generateHandlerMethodKey(_request.innerRequest.method, _request.path.orderedVariableNames);
    var method = _methodCache[_controller.runtimeType][key];

    var symbolizedCachedParameters = {};
    method.optionalParameters.forEach((name, param) => symbolizedCachedParameters[new Symbol(name)] = param);
    _symbolicateParameterValues(symbolizedCachedParameters, values.optionalParametersForRequest, values._missingQueries, values._missingHeaders);
  }

  void _symbolicateParameterValues(Map<Symbol, _HTTPControllerCachedParameter> parameters, Map<Symbol, dynamic> symbolicatedParameterValues, List<String> missingQueries, List<String> missingHeaders) {
    parameters.forEach((sym, param) {
      var externalName = param.httpParameter.externalName;
      List<String> value;
      if (param.httpParameter is HTTPQuery) {
        value = _queryParameters[externalName];

        if (value == null && param.httpParameter.isRequired) {
          missingQueries.add(externalName);
        }
      } else if (param.httpParameter is HTTPHeader) {
        value = _headerParameters[externalName.toLowerCase()];

        if (value == null && param.httpParameter.isRequired) {
          missingHeaders.add(externalName);
        }
      }

      if (value != null) {
        symbolicatedParameterValues[sym] = _convertParameterListWithMirror(value, param.typeMirror);
      }
    });
  }

  dynamic _convertParameterListWithMirror(List<String> parameterValues, TypeMirror typeMirror) {
    if (typeMirror.isSubtypeOf(reflectType(List))) {
      return parameterValues.map((str) => _convertParameterWithMirror(str, typeMirror.typeArguments.first)).toList();
    } else {
      return _convertParameterWithMirror(parameterValues.first, typeMirror);
    }
  }

  dynamic _convertParameterWithMirror(String parameterValue, TypeMirror typeMirror) {
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
          var reflValue = typeMirror.invoke(
              parseDecl.simpleName, [parameterValue]);
          return reflValue.reflectee;
        } catch (e) {
          throw new _InternalControllerException(
              "Invalid value for parameter type", HttpStatus.BAD_REQUEST,
              responseMessage: "URI parameter is wrong type");
        }
      }
    }

    // If we get here, then it wasn't a string and couldn't be parsed, and we should throw?
    throw new _InternalControllerException(
        "Invalid path parameter type, types must be String or implement parse",
        HttpStatus.INTERNAL_SERVER_ERROR,
        responseMessage: "URI parameter is wrong type");
  }
}

class _HTTPControllerInvocation {
  Symbol methodSymbolForRequest;

  Map<Symbol, dynamic> controllerParametersForRequest = {};
  List<dynamic> orderedParametersForRequest = [];
  Map<Symbol, dynamic> optionalParametersForRequest = {};

  List<String> _missingQueries = [];
  List<String> _missingHeaders = [];

  bool get isMissingRequiredParameters => _missingQueries.isNotEmpty || _missingHeaders.isNotEmpty;
  String get missingParametersString {
    if (!isMissingRequiredParameters) {
      return null;
    }

    StringBuffer missings = new StringBuffer();
    if (_missingQueries.isNotEmpty) {
      var missingQueriesString = _missingQueries
          .map((p) => "'${p}'")
          .join(", ");
      missings.write("Missing query value(s): ${missingQueriesString}.");
    }
    if (_missingQueries.isNotEmpty && _missingHeaders.isNotEmpty) {
      missings.write(" ");
    }
    if (_missingHeaders.isNotEmpty) {
      var missingHeadersString = _missingHeaders
          .map((p) => "'${p}'")
          .join(", ");
      missings.write("Missing header(s): ${missingHeadersString}.");
    }

    return missings.toString();
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

    var optionalParameters = new Map.fromIterable(optionalParams, key: (p) => p.name, value: (p) => p);

    httpMethod = mirror.metadata.firstWhere((m) => m is HTTPMethod).reflectee;
    methodSymbol = mirror.simpleName;
    orderedPathParameters = params;
    optionalParameters = optionalParameters;
  }

  Symbol methodSymbol;
  HTTPMethod httpMethod;
  List<_HTTPControllerCachedParameter> orderedPathParameters = [];
  Map<String, _HTTPControllerCachedParameter> optionalParameters = {};
}

class _HTTPControllerCachedParameter {
  _HTTPControllerCachedParameter(VariableMirror mirror) {
    name = MirrorSystem.getName(mirror.simpleName);
    httpParameter = mirror.metadata.firstWhere((im) => im.reflectee is _HTTPParameter, orElse: () => null)?.reflectee;
    typeMirror = mirror.type;
  }

  String name;
  TypeMirror typeMirror;
  _HTTPParameter httpParameter;
}