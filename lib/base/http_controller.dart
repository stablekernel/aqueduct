part of aqueduct;

/// Base class for web service handlers.
///
/// Subclasses of this class can process and respond to an HTTP request.
@cannotBeReused
abstract class HTTPController extends RequestHandler {
  static Map<Type, Map<String, _HTTPControllerCachedMethod>> _methodCache = {};
  static ContentType _applicationWWWFormURLEncodedContentType = new ContentType("application", "x-www-form-urlencoded");

  /// The request being processed by this [HTTPController].
  ///
  /// It is this [HTTPController]'s responsibility to return a [Response] object for this request. Handler methods
  /// may access this request to determine how to respond to it.
  Request request;

  /// Parameters parsed from the URI of the request, if any exist.
  ///
  /// These values are attached by a [Router] instance that precedes this [RequestHandler]. Is [null]
  /// if no [Router] preceded the controller and is the empty map if there are no values. The keys
  /// are the case-sensitive name of the path variables as defined by the [route].
  Map<String, String> get pathVariables => request.path?.variables;

  /// Types of content this [HTTPController] will accept.
  ///
  /// By default, a resource controller will accept 'application/json' and 'application/x-www-form-urlencoded' requests.
  /// If a request is sent to an instance of [HTTPController] and has an HTTP request body,
  /// but the Content-Type of the request isn't within this list, the [HTTPController]
  /// will automatically respond with an Unsupported Media Type response.
  List<ContentType> acceptedContentTypes = [ContentType.JSON, _applicationWWWFormURLEncodedContentType];

  /// The content type of responses from this [HTTPController].
  ///
  /// This type will automatically be written to this response's
  /// HTTP header. Defaults to "application/json". This value determines how the body data returned from this controller
  /// in a [Response] is encoded.
  ContentType responseContentType = ContentType.JSON;

  /// The HTTP request body object, after being decoded.
  ///
  /// This object will be decoded according to the this request's content type. If there was no body, this value will be null.
  dynamic get requestBody => request.requestBodyObject;

  /// Executed prior to handling a request, but after the [request] has been set.
  ///
  /// This method is used to do pre-process setup and filtering. The [request] will be set, but its body will not be decoded
  /// nor will the appropriate handler method be selected yet. By default, returns the request. If this method returns a [Response], this
  /// controller will stop processing the request and immediately return the [Response] to the HTTP client.
  Future<RequestHandlerResult> willProcessRequest(Request req) async {
    return req;
  }

  /// Executed prior to request being handled, but after the body has been processed.
  ///
  /// This method is called after the body has been processed by the decoder, but prior to the request being
  /// handled by the appropriate handler method.
  void didDecodeRequestBody(dynamic decodedObject) {}

  /// Executed prior to [Response] being sent, but after the handler method has been executed.
  ///
  /// This method is used to post-process a response before it is finally sent. By default, does nothing.
  /// This method will have no impact on when or how the [Response] is sent, is is simply informative.
  void willSendResponse(Response response) {}

  bool _requestContentTypeIsSupported(Request req) {
    var incomingContentType = request.innerRequest.headers.contentType;
    return acceptedContentTypes.firstWhere((ct) {
      return ct.primaryType == incomingContentType.primaryType && ct.subType == incomingContentType.subType;
    }, orElse: () => null) != null;
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
          var reflValue = typeMirror.invoke(parseDecl.simpleName, [parameterValue]);
          return reflValue.reflectee;
        } catch (e) {
          throw new _InternalControllerException("Invalid value for parameter type", HttpStatus.BAD_REQUEST, responseMessage: "URI parameter is wrong type");
        }
      }
    }

    // If we get here, then it wasn't a string and couldn't be parsed, and we should throw?
    throw new _InternalControllerException("Invalid path parameter type, types must be String or implement parse",
        HttpStatus.INTERNAL_SERVER_ERROR,
        responseMessage: "URI parameter is wrong type");
  }

  Map<String, dynamic> _queryParametersFromRequest(Request req, dynamic body) {
    Map<String, dynamic> queryParams = {};

    var contentType = req.innerRequest.headers.contentType;

    if (contentType != null
    &&  contentType.primaryType == _applicationWWWFormURLEncodedContentType.primaryType
    &&  contentType.subType == _applicationWWWFormURLEncodedContentType.subType) {
      queryParams = requestBody ?? {};
    } else {
      queryParams = req.innerRequest.uri.queryParametersAll;
    }

    return queryParams;
  }

  Map<String, dynamic> _headerParametersFromRequest(Request request, _HTTPControllerCachedMethod cachedMethod) {
    Map<String, dynamic> headerParams = {};

    cachedMethod.headerParameters.forEach((name, param) {
      String headerName = param.externalName;
      if (headerName != null) {
        headerParams[name] = request.innerRequest.headers[headerName];
      }
    });

    return headerParams;
  }

  String _checkForRequiredParameters(_HTTPControllerCachedMethod cachedMethod, Map<String, dynamic> headerParameters) {
    List<String> missingHeaders = [];
    cachedMethod.headerParameters.forEach((name, param) {
      if (headerParameters[name] == null && param.isRequired) {
        missingHeaders.add("'${param.externalName}'");
      }
    });

    return missingHeaders.isEmpty ? null : missingHeaders.join(", ");
  }

  Map<Symbol, dynamic> _symbolicateAndConvertParameters(_HTTPControllerCachedMethod method, Map<String, dynamic> queryValues, Map<String, dynamic> headerValues) {
    var symbolicatedValues = {};

    var queryParameters = method.optionalParameters;
    queryValues.forEach((key, value) {
      var desired = queryParameters[key];
      if (desired != null) {
        if (value is List) {
          symbolicatedValues[new Symbol(key)] = _convertParameterListWithMirror(value, desired.typeMirror);
        } else {
          symbolicatedValues[new Symbol(key)] = _convertParameterWithMirror(value, desired.typeMirror);
        }
      }
    });

    var headerParameters = method.headerParameters;
    headerValues.forEach((key, value) {
      var desired = headerParameters[key];
      if (desired != null) {
        if (value is List) {
          symbolicatedValues[new Symbol(key)] = _convertParameterListWithMirror(value, desired.typeMirror);
        } else {
          symbolicatedValues[new Symbol(key)] = _convertParameterWithMirror(value, desired.typeMirror);
        }
      }
    });

    return symbolicatedValues;
  }

  dynamic _serializedResponseBody(dynamic initialResponseBody) {
    var serializedBody = null;
    if (initialResponseBody is Serializable) {
      serializedBody = (initialResponseBody as Serializable).asSerializable();
    } else if (initialResponseBody is List) {
      serializedBody = (initialResponseBody as List).map((value) {
        if (value is Serializable) {
          return value.asSerializable();
        } else {
          return value;
        }
      }).toList();
    }

    return serializedBody ?? initialResponseBody;
  }

  Future<Response> _process() async {
    var key = _generateHandlerMethodKey(request.innerRequest.method, request.path.orderedVariableNames);
    var cachedMethod = _methodCache[this.runtimeType][key];
    if (cachedMethod == null) {
      return new Response.notFound();
    }

    var methodSymbol = cachedMethod.methodSymbol;
    var handlerParameters = cachedMethod
        .orderedPathParameters
        .map((param) => _convertParameterWithMirror(this.request.path.variables[param.name], param.typeMirror))
        .toList();

    if (request.innerRequest.contentLength > 0) {
      if (_requestContentTypeIsSupported(request)) {
        await request.decodeBody();
      } else {
        return new Response(HttpStatus.UNSUPPORTED_MEDIA_TYPE, null, null);
      }
    }

    var queryParameterMap = _queryParametersFromRequest(request, requestBody);
    var headerParameterMap = _headerParametersFromRequest(request, cachedMethod);
    var missingHeaderString = _checkForRequiredParameters(cachedMethod, headerParameterMap);
    if (missingHeaderString != null) {
      return new Response.badRequest(body: {"error": "Missing header(s): ${missingHeaderString}."});
    }

    var symbolicatedOptionalParameters = _symbolicateAndConvertParameters(cachedMethod, queryParameterMap, headerParameterMap);

    if (requestBody != null) {
      didDecodeRequestBody(requestBody);
    }

    Future<Response> eventualResponse = reflect(this).invoke(methodSymbol, handlerParameters, symbolicatedOptionalParameters).reflectee;
    var response = await eventualResponse;

    willSendResponse(response);

    response.body = _serializedResponseBody(response.body);
    response.headers[HttpHeaders.CONTENT_TYPE] = responseContentType;

    return response;
  }

  @override
  Future<RequestHandlerResult> processRequest(Request req) async {
    _buildCachesIfNecessary();

    try {
      request = req;

      var preprocessedResult = await willProcessRequest(req);
      Response response = null;
      if (preprocessedResult is Request) {
        response = await _process();
      } else if (preprocessedResult is Response) {
        response = preprocessedResult;
      } else {
        response = new Response.serverError(body: {"error" : "Preprocessing request did not yield result"});
      }

      return response;
    } on _InternalControllerException catch (e) {
      return e.response;
    }
  }

  void _buildCachesIfNecessary() {
    if (_methodCache.containsKey(this.runtimeType)) {
      return;
    }

    var methodMap = {};
    var allDeclarations = reflect(this).type.declarations;
    allDeclarations.forEach((key, declaration) {
      if (declaration is MethodMirror) {
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
                  ..externalName = name
                  ..isRequired = true
                  ..typeMirror = pm.type;
            })
            .toList();

        Iterable<_HTTPControllerCachedParameter> optionalParams = (declaration as MethodMirror)
            .parameters
            .where((pm) => pm.isOptional && !pm.metadata.any((im) => im.reflectee is HTTPHeader))
            .map((pm) {
              var name = MirrorSystem.getName(pm.simpleName);
              return new _HTTPControllerCachedParameter()
                ..name = name
                ..externalName = name
                ..isRequired = false
                ..typeMirror = pm.type;
            });
        var optionalParameters = new Map.fromIterable(optionalParams, key: (p) => p.name, value: (p) => p);

        Iterable<_HTTPControllerCachedParameter> headerParams = (declaration as MethodMirror)
            .parameters
            .where((pm) => pm.isOptional && pm.metadata.any((im) => im.reflectee is HTTPHeader))
            .map((pm) {
              HTTPHeader httpHeader = pm.metadata.firstWhere((im) => im.reflectee is HTTPHeader).reflectee;
              return new _HTTPControllerCachedParameter()
                ..name = MirrorSystem.getName(pm.simpleName)
                ..externalName = httpHeader.header
                ..isRequired = httpHeader.isRequired
                ..typeMirror = pm.type;
            });
        var headerParameters = new Map.fromIterable(headerParams, key: (p) => p.name, value: (p) => p);

        var generatedKey = _generateHandlerMethodKey((methodAttrs.reflectee as HTTPMethod).method, params.map((p) => p.name).toList());
        var cachedMethod = new _HTTPControllerCachedMethod()
          ..methodSymbol = key
          ..orderedPathParameters = params
          ..optionalParameters = optionalParameters
          ..headerParameters = headerParameters;
        methodMap[generatedKey] = cachedMethod;
      }
    });

    _methodCache[this.runtimeType] = methodMap;
  }

  String _generateHandlerMethodKey(String httpMethod, List<String> params) {
    return "${httpMethod.toLowerCase()}-" + params.map((pathParam) => pathParam).join("-");
  }

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) {
    var handlerMethodMirrors = reflect(this).type.declarations.values
        .where((dm) => dm is MethodMirror)
        .where((mm) {
          return mm.metadata.firstWhere((im) => im.reflectee is HTTPMethod, orElse: () => null) != null;
        });

    var reflectedType = reflect(this).type;
    var uri = reflectedType.location.sourceUri;
    var fileUnit = parseDartFile(resolver.resolve(uri));

    var classUnit = fileUnit.declarations
        .where((u) => u is ClassDeclaration)
        .firstWhere((ClassDeclaration u) => u.name.token.lexeme == MirrorSystem.getName(reflectedType.simpleName));

    Map<String, MethodDeclaration> methodMap = {};
    classUnit.childEntities.forEach((child) {
      if (child is MethodDeclaration) {
        MethodDeclaration c = child;
        methodMap[c.name.token.lexeme] = child;
      }
    });

    return handlerMethodMirrors.map((MethodMirror mm) {
      var operation = new APIOperation();
      operation.id = "${MirrorSystem.getName(reflect(this).type.simpleName)}.${MirrorSystem.getName(mm.simpleName)}";

      var matchingMethodDeclaration = methodMap[MirrorSystem.getName(mm.simpleName)];

      if (matchingMethodDeclaration != null) {
        var comment = matchingMethodDeclaration.documentationComment;
        List tokens = comment?.tokens ?? [];
        var lines = tokens.map((t) => t.lexeme.trimLeft().substring(3).trim()).toList();
        if (lines.length > 0) {
          operation.summary = lines.first;
        }
        if (lines.length > 1) {
          operation.description = lines.sublist(1, lines.length).join("\n");
        }
      }

      HTTPMethod httpMethod = mm.metadata.firstWhere((im) => im.reflectee is HTTPMethod).reflectee;

      operation.method = httpMethod.method;

      operation.parameters = mm.parameters
          .where((pm) => !pm.isOptional)
          .map((pm) {
            return new APIParameter()
                ..name = MirrorSystem.getName(pm.simpleName)
                ..type = APIParameter.typeStringForVariableMirror(pm)
                ..parameterLocation = APIParameterLocation.path;
      }).toList();

      List<APIParameter> optionalParams = mm.parameters
          .where((pm) => pm.isOptional)
          .map((pm) {
            return new APIParameter()
              ..name = MirrorSystem.getName(pm.simpleName)
              ..description = ""
              ..type = APIParameter.typeStringForVariableMirror(pm)
              ..required = false;
          }).toList();

      if (operation.method.toLowerCase() == "post" && acceptedContentTypes.firstWhere((cm) => cm.primaryType == "application" && cm.subType == "x-www-form-urlencoded", orElse: () => null) != null) {
        optionalParams.forEach((param) {
          param.parameterLocation = APIParameterLocation.formData;
        });
      } else {
        optionalParams.forEach((param) {
          param.parameterLocation = APIParameterLocation.query;
        });
      }
      operation.parameters.addAll(optionalParams);

      operation.consumes = acceptedContentTypes.map((ct) => "${ct.primaryType}/${ct.subType}").toList();
      operation.produces = ["${responseContentType.primaryType}/${responseContentType.subType}"];

      return operation;
    }).toList();
  }
}

class _InternalControllerException implements Exception {
  final String message;
  final int statusCode;
  final HttpHeaders additionalHeaders;
  final String responseMessage;

  _InternalControllerException(this.message, this.statusCode, {HttpHeaders additionalHeaders: null, String responseMessage: null})
      : this.additionalHeaders = additionalHeaders,
        this.responseMessage = responseMessage;

  Response get response {
    var headerMap = {};
    additionalHeaders?.forEach((k, _) {
      headerMap[k] = additionalHeaders.value(k);
    });

    var bodyMap = null;
    if (responseMessage != null) {
      bodyMap = {"error" : responseMessage};
    }
    return new Response(statusCode, headerMap, bodyMap);
  }
}


class _HTTPControllerCachedMethod {
  Symbol methodSymbol;
  List<_HTTPControllerCachedParameter> orderedPathParameters = [];
  Map<String, _HTTPControllerCachedParameter> optionalParameters = {};
  Map<String, _HTTPControllerCachedParameter> headerParameters = {};
}

class _HTTPControllerCachedParameter {
  String name;
  String externalName;
  bool isRequired;
  TypeMirror typeMirror;
}