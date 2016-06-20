part of aqueduct;

/// Base class for web service handlers.
///
/// Subclasses of this class can process and respond to an HTTP request.
@cannotBeReused
abstract class HTTPController extends RequestHandler {
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

  Symbol _routeMethodSymbolForRequest(Request req) {
    var symbol = null;

    var decls = reflect(this).type.declarations;
    for (var key in decls.keys) {
      var decl = decls[key];
      if (decl is MethodMirror) {
        var methodAttrs = decl.metadata.firstWhere((attr) => attr.reflectee is HTTPMethod, orElse: () => null);

        if (methodAttrs != null) {
          var params = (decl as MethodMirror).parameters.where((pm) => !pm.isOptional).map((pm) => MirrorSystem.getName(pm.simpleName)).toList();

          HTTPMethod r = new HTTPMethod._fromMethod(methodAttrs.reflectee, params);

          if (r._matchesRequest(req)) {
            symbol = key;
            break;
          }
        }
      }
    }

    if (symbol == null) {
      throw new _InternalControllerException("No handler for request method and parameters available.", HttpStatus.NOT_FOUND);
    }

    return symbol;
  }

  Future _readRequestBodyForRequest(Request req) async {
    if (request.innerRequest.contentLength > 0) {
      var incomingContentType = request.innerRequest.headers.contentType;
      var matchingContentType = acceptedContentTypes.firstWhere((ct) {
        return ct.primaryType == incomingContentType.primaryType && ct.subType == incomingContentType.subType;
      }, orElse: () => null);

      if (matchingContentType == null) {
        throw new _InternalControllerException("Unsupported Content-Type", HttpStatus.UNSUPPORTED_MEDIA_TYPE);
      }

      try {
        await req.decodeBodyWithDecoder((r) async {
          return (await HttpBodyHandler.processRequest(r)).body;
        });
      } catch (e) {
        throw new _InternalIgnoreBullshitException();
      }
    }
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

  List<dynamic> _parametersForRequest(Request req, Symbol handlerMethodSymbol) {
    var handlerMirror = reflect(this).type.declarations[handlerMethodSymbol] as MethodMirror;

    return handlerMirror.parameters.where((methodParmeter) => !methodParmeter.isOptional).map((methodParameter) {
      var value = this.request.path.variables[MirrorSystem.getName(methodParameter.simpleName)];

      return _convertParameterWithMirror(value, methodParameter.type);
    }).toList();
  }

  Map<Symbol, dynamic> _queryParametersForRequest(Request req, dynamic body, Symbol handlerMethodSymbol) {
    Map<String, dynamic> queryParams = {};

    var contentTypeString = req.innerRequest.headers.value(HttpHeaders.CONTENT_TYPE);
    var contentType = null;
    if (contentTypeString != null) {
      contentType = ContentType.parse(contentTypeString);
    }

    if (contentType != null
    &&  contentType.primaryType == _applicationWWWFormURLEncodedContentType.primaryType
    &&  contentType.subType == _applicationWWWFormURLEncodedContentType.subType) {
      queryParams = requestBody ?? {};
    } else {
      queryParams = req.innerRequest.uri.queryParametersAll;
    }

    if (queryParams.length == 0) {
      return null;
    }

    var optionalParams = (reflect(this).type.declarations[handlerMethodSymbol] as MethodMirror)
        .parameters
        .where((methodParameter) => methodParameter.isOptional)
        .toList();

    var retMap = {};
    queryParams.forEach((k, v) {
      var keySymbol = new Symbol(k);
      var matchingParameter = optionalParams.firstWhere((p) => p.simpleName == keySymbol, orElse: () => null);
      if (matchingParameter != null) {
        if (v is List) {
          retMap[keySymbol] = _convertParameterListWithMirror(v, matchingParameter.type);
        } else {
          retMap[keySymbol] = _convertParameterWithMirror(v, matchingParameter.type);
        }
      }
    });

    return retMap;
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
    var methodSymbol = _routeMethodSymbolForRequest(request);
    var handlerParameters = _parametersForRequest(request, methodSymbol);

    await _readRequestBodyForRequest(request);
    var handlerQueryParameters = _queryParametersForRequest(request, requestBody, methodSymbol);

    if (requestBody != null) {
      didDecodeRequestBody(requestBody);
    }

    Future<Response> eventualResponse = reflect(this).invoke(methodSymbol, handlerParameters, handlerQueryParameters).reflectee;
    var response = await eventualResponse;

    willSendResponse(response);

    response.body = _serializedResponseBody(response.body);
    response.headers[HttpHeaders.CONTENT_TYPE] = responseContentType;

    return response;
  }

  @override
  Future<RequestHandlerResult> processRequest(Request req) async {
    try {
      request = req;

      var preprocessedResult = await willProcessRequest(req);
      Response response = null;
      if (preprocessedResult is Request) {
        response = await _process();
      } else if (preprocessedResult is Response) {
        response = preprocessedResult;
      } else {
        throw new _InternalControllerException("Preprocessing request did not yield result", 500);
      }

      return response;
    } on _InternalIgnoreBullshitException {
      // If this happens, the JSON decoder decided to respond for us, which is a real dick move, so we have to return null here and
      // manually update the respondDate. Remove this code once we remove the dependency on HttpBodyParser.
      req.respondDate = new DateTime.now().toUtc();
      logger.info(req.toDebugString(includeHeaders: true, includeBody: true));

      return null;
    } on _InternalControllerException catch (e) {
      return e.response;
    }
  }

  @override
  List<APIDocumentItem> document(PackagePathResolver resolver) {
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
      var i = new APIDocumentItem();

      var matchingMethodDeclaration = methodMap[MirrorSystem.getName(mm.simpleName)];
      if (matchingMethodDeclaration != null) {
        var comment = matchingMethodDeclaration.documentationComment;
        var tokens = comment?.tokens ?? [];
        i.description = tokens.map((t) => t.lexeme.trimLeft().substring(3).trim()).join("\n");
      }

      var httpMethod = mm.metadata.firstWhere((im) => im.reflectee is HTTPMethod).reflectee;

      i.method = httpMethod.method;

      i.pathParameters = mm.parameters
          .where((pm) => !pm.isOptional)
          .map((pm) {
            return new APIParameter()
                ..key = MirrorSystem.getName(pm.simpleName)
                ..description = ""
                ..type = MirrorSystem.getName(pm.type.simpleName)
                ..required = true
                ..parameterLocation = APIParameterLocation.path;
      }).toList();

      i.queryParameters = mm.parameters
          .where((pm) => pm.isOptional)
          .map((pm) {
        return new APIParameter()
          ..key = MirrorSystem.getName(pm.simpleName)
          ..description = ""
          ..type = MirrorSystem.getName(pm.type.simpleName)
          ..required = false;
      }).toList();

      if (i.method.toLowerCase() == "post" && acceptedContentTypes.firstWhere((cm) => cm.primaryType == "application" && cm.subType == "x-www-form-urlencoded", orElse: () => null) != null) {
        i.queryParameters.forEach((param) {
          param.parameterLocation = APIParameterLocation.formData;
        });
      } else {
        i.queryParameters.forEach((param) {
          param.parameterLocation = APIParameterLocation.query;
        });
      }

      i.acceptedContentTypes = acceptedContentTypes.map((ct) => "${ct.primaryType}/${ct.subType}").toList();
      i.responseFormats = ["${responseContentType.primaryType}/${responseContentType.subType}"];

      return i;
    }).toList();
  }
}

class _InternalIgnoreBullshitException implements Exception {
  _InternalIgnoreBullshitException();
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
