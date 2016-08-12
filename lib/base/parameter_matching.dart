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

class _ParameterMatcher {
  static Map<Type, Map<String, _HTTPControllerCachedMethod>> _methodCache = {};
  static Map<Type, Map<Symbol, _HTTPControllerCachedParameter>> _controllerLevelParameters = {};
  static ContentType _applicationWWWFormURLEncodedContentType = new ContentType("application", "x-www-form-urlencoded");

  Symbol methodSymbolForRequest;
  Map<Symbol, dynamic> controllerParametersForRequest = {};
  List<dynamic> orderedParametersForRequest = [];
  Map<Symbol, dynamic> optionalParametersForRequest = {};

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

  Map<String, dynamic> _queryParameters = {};
  List<String> _missingQueries = [];

  Map<String, dynamic> _headerParameters = {};
  List<String> _missingHeaders = [];

  HTTPController _controller;
  Request _request;

  factory _ParameterMatcher(HTTPController con, Request req) {
    Type controllerType = con.runtimeType;
    _buildCachesIfNecessary(controllerType);

    var key = _generateHandlerMethodKey(req.innerRequest.method, req.path.orderedVariableNames);
    var matchingMethod = _methodCache[controllerType][key];
    if (matchingMethod == null) {
      return null;
    }

    return new _ParameterMatcher._internal(con, req, matchingMethod.methodSymbol);
  }

  _ParameterMatcher._internal(HTTPController con, Request req, Symbol methodSymbol)
      : _controller = con,
        _request = req,
        methodSymbolForRequest = methodSymbol;

  static void _buildCachesIfNecessary(Type controllerType) {
    if (_methodCache.containsKey(controllerType)) {
      return;
    }

    var controllerLevelMap = {};
    var methodMap = {};
    var allDeclarations = reflectClass(controllerType).declarations;
    allDeclarations.forEach((key, declaration) {
      if (declaration is VariableMirror) {
        _HTTPParameter httpParameter = declaration.metadata.firstWhere((im) => im.reflectee is _HTTPParameter, orElse: () => null)?.reflectee;
        if (httpParameter == null) { return; }

        controllerLevelMap[key] = new _HTTPControllerCachedParameter()
          ..name = MirrorSystem.getName(key)
          ..httpParameter = httpParameter
          ..typeMirror = declaration.type;
      } else if (declaration is MethodMirror) {
        var methodAttrs = declaration
            .metadata
            .firstWhere((attr) => attr.reflectee is HTTPMethod, orElse: () => null);

        if (methodAttrs == null) {
          return;
        }

        List<_HTTPControllerCachedParameter> params = (declaration as MethodMirror)
            .parameters
            .where((pm) => !pm.isOptional)
            .map((pm) {
          var name = MirrorSystem.getName(pm.simpleName);
          return new _HTTPControllerCachedParameter()
            ..name = name
            ..typeMirror = pm.type;
        })
            .toList();

        Iterable<_HTTPControllerCachedParameter> optionalParams = (declaration as MethodMirror)
            .parameters
            .where((pm) => pm.metadata.any((im) => im.reflectee is _HTTPParameter))
            .map((pm) {
          _HTTPParameter httpParameter = pm.metadata.firstWhere((im) => im.reflectee is _HTTPParameter).reflectee;
          return new _HTTPControllerCachedParameter()
            ..name = MirrorSystem.getName(pm.simpleName)
            ..httpParameter = httpParameter
            ..typeMirror = pm.type;
        });
        var optionalParameters = new Map.fromIterable(optionalParams, key: (p) => p.name, value: (p) => p);

        var generatedKey = _generateHandlerMethodKey((methodAttrs.reflectee as HTTPMethod).method, params.map((p) => p.name).toList());
        var cachedMethod = new _HTTPControllerCachedMethod()
          ..methodSymbol = key
          ..orderedPathParameters = params
          ..optionalParameters = optionalParameters;
        methodMap[generatedKey] = cachedMethod;
      }
    });

    _methodCache[controllerType] = methodMap;
    _controllerLevelParameters[controllerType] = controllerLevelMap;
  }

  static String _generateHandlerMethodKey(String httpMethod, List<String> params) {
    return "${httpMethod.toLowerCase()}-" + params.map((pathParam) => pathParam).join("-");
  }

  void parseParameters() {
    _parseOrderedParameters();
    _parseOptionalParameters();

    _symbolicateControllerParameters();
    _symbolicateOptionalParameters();
  }

  void _parseOrderedParameters() {
    var key = _generateHandlerMethodKey(_request.innerRequest.method, _request.path.orderedVariableNames);
    var method = _methodCache[_controller.runtimeType][key];
    orderedParametersForRequest = method
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

    _request.innerRequest.headers.forEach((k,v) => _headerParameters[k] = v);
  }

  void _symbolicateControllerParameters() {
    _controllerLevelParameters[_controller.runtimeType].forEach((sym, param) {
      var externalName = param.httpParameter.externalName;
      var value;
      if (param.httpParameter is HTTPQuery) {
        value = _queryParameters[externalName];

        if (value == null && param.httpParameter.isRequired) {
          _missingQueries.add(externalName);
        }
      } else if (param.httpParameter is HTTPHeader) {
        value = _headerParameters[externalName.toLowerCase()];

        if (value == null && param.httpParameter.isRequired) {
          _missingHeaders.add(externalName);
        }
      }

      if (value is List) {
        controllerParametersForRequest[sym] = _convertParameterListWithMirror(value, param.typeMirror);
      } else if (value != null) {
        controllerParametersForRequest[sym] = _convertParameterWithMirror(value, param.typeMirror);
      }
    });
  }

  void _symbolicateOptionalParameters() {
    var key = _generateHandlerMethodKey(_request.innerRequest.method, _request.path.orderedVariableNames);
    var method = _methodCache[_controller.runtimeType][key];
    method.optionalParameters.forEach((name, param) {
      var externalName = param.httpParameter.externalName;
      var value;
      if (param.httpParameter is HTTPHeader) {
        value = _headerParameters[externalName.toLowerCase()];

        if (value == null && param.httpParameter.isRequired) {
          _missingHeaders.add(externalName);
        }
      } else if (param.httpParameter is HTTPQuery) {
        value = _queryParameters[externalName];

        if (value == null && param.httpParameter.isRequired) {
          _missingQueries.add(externalName);
        }
      }

      if (value is List) {
        optionalParametersForRequest[new Symbol(name)] = _convertParameterListWithMirror(value, param.typeMirror);
      } else if (value != null) {
        optionalParametersForRequest[new Symbol(name)] = _convertParameterWithMirror(value, param.typeMirror);
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

class _HTTPControllerCachedMethod {
  Symbol methodSymbol;
  List<_HTTPControllerCachedParameter> orderedPathParameters = [];
  Map<String, _HTTPControllerCachedParameter> optionalParameters = {};
}

class _HTTPControllerCachedParameter {
  String name;
  TypeMirror typeMirror;
  _HTTPParameter httpParameter;
}