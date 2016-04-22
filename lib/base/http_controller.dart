part of monadart;

/// Base class for web service handlers.
///
/// Subclasses of this class can process and respond to an HTTP request.
abstract class HttpController extends RequestHandler {
  static ContentType _applicationWWWFormURLEncodedContentType = new ContentType("application", "x-www-form-urlencoded");

  /// An optional exception handler for this controller that generates an HTTP error response.
  ///
  /// By default, this handler is null. Exceptions will be handled by the default implementation
  /// of [RequestHandler]. You may provide another exception handler to override the default behavior.
  /// This exception handler MUST return a [Response] object, no matter what.
  Function get exceptionHandler => _exceptionHandler;
  void set exceptionHandler(Response handler(ResourceRequest resourceRequest, dynamic exceptionOrError, StackTrace stacktrace)) {
    _exceptionHandler = handler;
  }

  Function _exceptionHandler = null;

  /// The request being processed by this [HttpController].
  ///
  /// It is this [HttpController]'s responsibility to return a [Response] object for this request.
  ResourceRequest request;

  CORSPolicy policy = new CORSPolicy();

  /// Parameters parsed from the URI of the request, if any exist.
  Map<String, String> get pathVariables => request.path.variables;

  /// Types of content this [HttpController] will accept.
  ///
  /// By default, a resource controller will accept 'application/json' requests.
  /// If a request is sent to an instance of [HttpController] and has an HTTP request body,
  /// but the Content-Type of the request isn't within this list, the [HttpController]
  /// will automatically respond with an Unsupported Media Type response.
  List<ContentType> acceptedContentTypes = [ContentType.JSON, _applicationWWWFormURLEncodedContentType];

  /// The content type of responses from this [HttpController].
  ///
  /// This type will automatically be written to this response's
  /// HTTP header. Defaults to "application/json". Set with [setResponseEncoder].
  ContentType get responseContentType => _responseContentType;
  ContentType _responseContentType = ContentType.JSON;

  /// Encodes the [Response] body to a suitable format for transmission.
  ///
  /// Encodes the HTTP response body object that is part of the [Response] returned from this request handler methods.
  /// Must have the signature (dynamic) => dynamic. Use [setResponseEncoder] to set this value.
  ///
  /// By default, this encoder will convert the response body as JSON.
  Function get responseBodyEncoder => _responseBodyEncoder;
  Function _responseBodyEncoder = (body) => JSON.encode(body);

  /// Sets the [responseContentType] and [responseBodyEncoder].
  ///
  /// This method is the only way to set [responseContentType] and [responseBodyEncoder] and ensures
  /// that both are set simultaneously since they are dependent on one another.
  void setResponseEncoder(ContentType contentType, dynamic encoder(dynamic value)) {
    _responseContentType = contentType;
    _responseBodyEncoder = encoder;
  }

  /// The HTTP request body object, after being decoded.
  ///
  /// This object will be decoded according to the this request's content type. If there was no body, this value will be null.
  /// If this resource controller does not support the content type of the body, the controller will automatically
  /// respond with a Unsupported Media Type HTTP response.
  dynamic requestBody;

  // Callbacks
  /// Executed prior to handling a request, but after the [resourceRequest] has been set.
  ///
  /// This method is used to do pre-process setup and filtering. The [resourceRequest] will be set, but its body will not be decoded
  /// nor will the appropriate handler method be selected yet. By default, returns the request. If this method returns a [Response], this
  /// controller will stop processing the request and immediately return the [Response] to the HTTP client.
  Future<RequestHandlerResult> willProcessRequest(ResourceRequest req) async {
    return req;
  }

  /// Executed prior to request being handled, but after the body has been processed.
  ///
  /// This method is called after the body has been processed by the decoder, but prior to the request being
  /// handled by the appropriate handler method.
  void didDecodeRequestBody(dynamic decodedObject) {}

  /// Executed prior to [response] being sent, but after the handler method has been executed.
  ///
  /// This method is used to post-process a response before it is finally sent. By default, does nothing.
  void willSendResponse(Response response) {}

  Symbol _routeMethodSymbolForRequest(ResourceRequest req) {
    var symbol = null;

    var decls = reflect(this).type.declarations;
    for (var key in decls.keys) {
      var decl = decls[key];
      if (decl is MethodMirror) {
        var methodAttrs = decl.metadata.firstWhere((attr) => attr.reflectee is HttpMethod, orElse: () => null);

        if (methodAttrs != null) {
          var params = (decl as MethodMirror).parameters.where((pm) => !pm.isOptional).map((pm) => MirrorSystem.getName(pm.simpleName)).toList();

          HttpMethod r = new HttpMethod._fromMethod(methodAttrs.reflectee, params);

          if (r.matchesRequest(req)) {
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

  dynamic _readRequestBodyForRequest(ResourceRequest req) async {
    if (request.innerRequest.contentLength > 0) {
      var incomingContentType = request.innerRequest.headers.contentType;
      var matchingContentType = acceptedContentTypes.firstWhere((ct) {
        return ct.primaryType == incomingContentType.primaryType && ct.subType == incomingContentType.subType;
      }, orElse: () => null);

      if (matchingContentType != null) {
        try {
          return (await HttpBodyHandler.processRequest(request.innerRequest)).body;
        } catch (e) {
          throw new _InternalIgnoreBullshitException();
        }
      } else {
        throw new _InternalControllerException("Unsupported Content-Type", HttpStatus.UNSUPPORTED_MEDIA_TYPE);
      }
    }

    return null;
  }

  dynamic _convertParameterWithMirror(String parameterValue, ParameterMirror parameterMirror) {
    var typeMirror = parameterMirror.type;
    if (typeMirror.isSubtypeOf(reflectType(String))) {
      return parameterValue;
    }

    if (typeMirror is ClassMirror) {
      var cm = (typeMirror as ClassMirror);
      var parseDecl = cm.declarations[new Symbol("parse")];
      if (parseDecl != null) {
        try {
          var reflValue = cm.invoke(parseDecl.simpleName, [parameterValue]);
          return reflValue.reflectee;
        } catch (e) {
          throw new _InternalControllerException("Invalid value for parameter type", HttpStatus.BAD_REQUEST, responseMessage: "URI parameter is wrong type");
        }
      }
    }

    // If we get here, then it wasn't a string and couldn't be parsed, and we should throw?
    throw new _InternalControllerException("Invalid path parameter type, types must be String or implement parse", HttpStatus.INTERNAL_SERVER_ERROR,
        responseMessage: "URI parameter is wrong type");
    return null;
  }

  List<dynamic> _parametersForRequest(ResourceRequest req, Symbol handlerMethodSymbol) {
    var handlerMirror = reflect(this).type.declarations[handlerMethodSymbol] as MethodMirror;

    return handlerMirror.parameters.where((methodParmeter) => !methodParmeter.isOptional).map((methodParameter) {
      var value = this.request.path.variables[MirrorSystem.getName(methodParameter.simpleName)];

      return _convertParameterWithMirror(value, methodParameter);
    }).toList();
  }

  Map<Symbol, dynamic> _queryParametersForRequest(ResourceRequest req, dynamic body, Symbol handlerMethodSymbol) {
    Map<String, String> queryParams = {};

    var contentTypeString = req.innerRequest.headers.value(HttpHeaders.CONTENT_TYPE);
    var contentType = null;
    if (contentTypeString != null) {
      contentType = ContentType.parse(contentTypeString);
    }

    if (contentType != null &&
        contentType.primaryType == _applicationWWWFormURLEncodedContentType.primaryType &&
        contentType.subType == _applicationWWWFormURLEncodedContentType.subType) {
      queryParams = requestBody ?? {};
    } else {
      queryParams = req.innerRequest.uri.queryParameters;
    }

    if (queryParams.length == 0) {
      return null;
    }

    var optionalParams =
        (reflect(this).type.declarations[handlerMethodSymbol] as MethodMirror).parameters.where((methodParameter) => methodParameter.isOptional).toList();

    var retMap = {};
    queryParams.forEach((k, v) {
      var keySymbol = new Symbol(k);
      var matchingParameter = optionalParams.firstWhere((p) => p.simpleName == keySymbol, orElse: () => null);
      if (matchingParameter != null) {
        retMap[keySymbol] = _convertParameterWithMirror(v, matchingParameter);
      }
    });

    return retMap;
  }

  dynamic encodedResponseBody(dynamic initialResponseBody) {
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

    return responseBodyEncoder(serializedBody ?? initialResponseBody);

  }

  Future<Response> _process() async {
    var methodSymbol = _routeMethodSymbolForRequest(request);
    var handlerParameters = _parametersForRequest(request, methodSymbol);

    requestBody = await _readRequestBodyForRequest(request);
    var handlerQueryParameters = _queryParametersForRequest(request, requestBody, methodSymbol);

    if (requestBody != null) {
      didDecodeRequestBody(requestBody);
    }

    Future<Response> eventualResponse = reflect(this).invoke(methodSymbol, handlerParameters, handlerQueryParameters).reflectee;
    var response = await eventualResponse;

    willSendResponse(response);

    response.body = encodedResponseBody(response.body);
    response.headers[HttpHeaders.CONTENT_TYPE] = responseContentType.toString();

    return response;
  }

  @override
  Future<RequestHandlerResult> processRequest(ResourceRequest req) async {
    try {
      request = req;

      var corsHeaders = null;
      if (request.innerRequest.headers.value("origin") != null) {
        if (policy != null) {
          if (!policy.isRequestOriginAllowed(request.innerRequest)) {
            return new Response.forbidden();
          }

          if (request.innerRequest.method == "OPTIONS") {
            // Preflight request
            return policy.preflightResponse(req);
          } else {
            // Normal request
            corsHeaders = policy.headersForRequest(request);
          }
        }
      }

      var preprocessedResult = await willProcessRequest(req);
      Response response = null;
      if (preprocessedResult is ResourceRequest) {
        response = await _process();
      } else if (preprocessedResult is Response) {
        response = preprocessedResult;
      } else {
        throw new _InternalControllerException("Preprocessing request did not yield result", 500);
      }

      if (corsHeaders != null) {
        if (response.headers != null) {
          response.headers.addAll(corsHeaders);
        } else {
          response.headers = corsHeaders;
        }
      }

      return response;
    } on HttpResponseException catch (e) {
      return e.response();
    } on _InternalIgnoreBullshitException {
      return null;
    } on _InternalControllerException catch (e) {
      logger.info("Request (${request.toDebugString()}) failed: ${e.message}.");
      var response = new Response(e.statusCode, {}, null);

      request.response.statusCode = e.statusCode;

      if (e.additionalHeaders != null) {
        e.additionalHeaders.forEach((name, values) {
          response.headers[name] = values;
        });
      }

      if (e.responseMessage != null) {
        response.body = {"error": e.responseMessage};
      }

      return response;
    } catch (e, stacktrace) {
      logger.severe("HttpController: Uncaught error in request (${request.toDebugString()}): ${e}\n $stacktrace.");
      if (_exceptionHandler != null) {
        var response = _exceptionHandler(this.request, e, stacktrace);
        return response;
      } else {
        return new Response.serverError();
      }
    }
  }

  @override
  List<APIDocumentItem> document(PackagePathResolver resolver) {
    var handlerMethodMirrors = reflect(this).type.declarations.values
        .where((dm) => dm is MethodMirror)
        .where((mm) {
          return mm.metadata.firstWhere((im) => im.reflectee is HttpMethod, orElse: () => null) != null;
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

      var httpMethod = mm.metadata.firstWhere((im) => im.reflectee is HttpMethod).reflectee;

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

class _InternalIgnoreBullshitException {
  _InternalIgnoreBullshitException();
}
class _InternalControllerException {
  final String message;
  final int statusCode;
  final HttpHeaders additionalHeaders;
  final String responseMessage;

  _InternalControllerException(this.message, this.statusCode, {HttpHeaders additionalHeaders: null, String responseMessage: null})
      : this.additionalHeaders = additionalHeaders,
        this.responseMessage = responseMessage;
}
