part of monadart;

/// A 'GET' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle GET requests must be annotated with this.
const HttpMethod httpGet = const HttpMethod("get");

/// A 'PUT' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle PUT requests must be annotated with this.
const HttpMethod httpPut = const HttpMethod("put");

/// A 'POST' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle POST requests must be annotated with this.
const HttpMethod httpPost = const HttpMethod("post");

/// A 'DELETE' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle DELETE requests must be annotated with this.
const HttpMethod httpDelete = const HttpMethod("delete");

/// A 'PATCH' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle PATCH requests must be annotated with this.
const HttpMethod httpPatch = const HttpMethod("patch");

/// Resource controller handler method metadata for indicating the HTTP method the controller method corresponds to.
///
/// Each [HttpController] method that is the entry point for an HTTP request must be decorated with an instance
/// of [HttpMethod]. See [httpGet], [httpPut], [httpPost] and [httpDelete] for concrete examples.
class HttpMethod {
  /// The method that the annotated request handler method corresponds to.
  ///
  /// Case-insensitive.
  final String method;

  final List<String> _parameters;

  const HttpMethod(this.method) : this._parameters = null;

  HttpMethod._fromMethod(HttpMethod m, List<String> parameters)
  : this.method = m.method,
  this._parameters = parameters;

  /// Returns whether or not this [HttpMethod] matches a [ResourceRequest].
  bool matchesRequest(ResourceRequest req) {
    if (req.request.method.toLowerCase() != this.method.toLowerCase()) {
      return false;
    }

    if (req.pathParameters == null) {
      if (this._parameters.length == 0) {
        return true;
      }
      return false;
    }

    if (req.pathParameters.length != this._parameters.length) {
      return false;
    }

    for (var id in this._parameters) {
      if (req.pathParameters[id] == null) {
        return false;
      }
    }

    return true;
  }
}

/// Base class for web service handlers.
///
/// Subclasses of this class can process and respond to an HTTP request.
abstract class HttpController implements RequestHandler {

  /// The exception handler for a request handler method that generates an HTTP error response.
  ///
  /// The default handler will always respond to the HTTP request with a 500 status code.
  /// There are other exception handlers involved in the process of handling a request,
  /// but once execution enters a handler method (one decorated with [HttpMethod]), this exception handler
  /// is in place.
  Function get exceptionHandler => _exceptionHandler;

  void set exceptionHandler(Response handler(ResourceRequest resourceRequest, dynamic exceptionOrError, StackTrace stacktrace)) {
    _exceptionHandler = handler;
  }

  Function _exceptionHandler = _defaultExceptionHandler;

  /// The request being processed by this [HttpController].
  ///
  /// It is this [HttpController]'s responsibility to return a [Response] object for this request.
  ResourceRequest resourceRequest;

  /// Parameters parsed from the URI of the request, if any exist.
  Map<String, String> get pathParameters => resourceRequest.pathParameters;

  /// Types of content this [HttpController] will accept.
  ///
  /// By default, a resource controller will accept 'application/json' requests.
  /// If a request is sent to an instance of [HttpController] and has an HTTP request body,
  /// but the Content-Type of the request isn't within this list, the [HttpController]
  /// will automatically respond with an Unsupported Media Type response.
  List<ContentType> acceptedContentTypes = [ContentType.JSON];

  /// The content type of responses from this [HttpController].
  ///
  /// Defaults to "application/json". This type will automatically be written to this response's
  /// HTTP header.
  ContentType responseContentType = ContentType.JSON;

  /// Encodes the HTTP response body object that is part of the [Response] returned from this request handler methods.
  ///
  /// By default, this encoder will convert the body object as JSON.
  dynamic responseBodyEncoder = (body) => JSON.encode(body);

  /// The HTTP request body object, after being decoded.
  ///
  /// This object will be decoded according to the request's content type. If there was no body, this value will be null.
  /// If this resource controller does not support the content type of the body, the controller will automatically
  /// respond with a Unsupported Media Type HTTP response.
  dynamic requestBody;

  Symbol _routeMethodSymbolForRequest(ResourceRequest req) {
    var symbol = null;

    var decls = reflect(this).type.declarations;
    for (var key in decls.keys) {
      var decl = decls[key];
      if (decl is MethodMirror) {
        var methodAttrs = decl.metadata.firstWhere(
                (attr) => attr.reflectee is HttpMethod, orElse: () => null);

        if (methodAttrs != null) {
          var params = (decl as MethodMirror).parameters
          .where((pm) => !pm.isOptional)
          .map((pm) => MirrorSystem.getName(pm.simpleName))
          .toList();

          HttpMethod r = new HttpMethod._fromMethod(methodAttrs.reflectee, params);

          if (r.matchesRequest(req)) {
            symbol = key;
            break;
          }
        }
      }
    }

    if (symbol == null) {
      throw new _InternalControllerException(
          "No handler for request method and parameters available.", HttpStatus.NOT_FOUND);
    }

    return symbol;
  }

  dynamic _readRequestBodyForRequest(ResourceRequest req) async
  {
    if (resourceRequest.request.contentLength > 0) {
      var incomingContentType = resourceRequest.request.headers.contentType;
      var matchingContentType = acceptedContentTypes.firstWhere((ct) {
        return ct.primaryType == incomingContentType.primaryType &&
        ct.subType == incomingContentType.subType;
      }, orElse: () => null);

      if (matchingContentType != null) {
        return (await HttpBodyHandler
        .processRequest(resourceRequest.request)).body;
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
          throw new _InternalControllerException("Invalid value for parameter type",
          HttpStatus.BAD_REQUEST,
          responseMessage: "URI parameter is wrong type");
        }
      }
    }

    // If we get here, then it wasn't a string and couldn't be parsed, and we should throw?
    throw new _InternalControllerException("Invalid path parameter type, types must be String or implement parse",
    HttpStatus.INTERNAL_SERVER_ERROR,
    responseMessage: "URI parameter is wrong type");
    return null;
  }

  List<dynamic> _parametersForRequest(ResourceRequest req, Symbol handlerMethodSymbol) {
    var handlerMirror =
    reflect(this).type.declarations[handlerMethodSymbol] as MethodMirror;

    return handlerMirror.parameters
    .where((methodParmeter) => !methodParmeter.isOptional)
    .map((methodParameter) {
      var value = this.resourceRequest.pathParameters[MirrorSystem.getName(methodParameter.simpleName)];

      return _convertParameterWithMirror(value, methodParameter);
    }).toList();
  }

  Map<Symbol, dynamic> _queryParametersForRequest(ResourceRequest req, Symbol handlerMethodSymbol) {
    var queryParams = req.request.uri.queryParameters;
    if (queryParams.length == 0) {
      return null;
    }

    var optionalParams = (reflect(this).type.declarations[handlerMethodSymbol] as MethodMirror)
    .parameters.where((methodParameter) => methodParameter.isOptional).toList();

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

  /// Executes the appropriate handler method for this controller's request.
  ///
  /// Will find an appropriate handler method to execute and send its [Response]
  /// to this controller's [resourceRequest] via [respond]. If no appropriate handler
  /// method is found, responds to [resourceRequest] with a 404. All handler methods
  /// are wrapped in an exception handler that is monitored by an internal mechanism
  /// and by this controller's [exceptionHandler].
  ///

  Future process() async {
    try {
      var methodSymbol = _routeMethodSymbolForRequest(resourceRequest);
      var handlerParameters = _parametersForRequest(resourceRequest, methodSymbol);
      var handlerQueryParameters = _queryParametersForRequest(resourceRequest, methodSymbol);

      requestBody = await _readRequestBodyForRequest(resourceRequest);

      Future<Response> eventualResponse =
      reflect(this).invoke(methodSymbol, handlerParameters, handlerQueryParameters).reflectee;

      var response = await eventualResponse;

      response.body = responseBodyEncoder(response.body);
      response.headers[HttpHeaders.CONTENT_TYPE] = responseContentType.toString();

      resourceRequest.respond(response);
    } on _InternalControllerException catch (e) {
      resourceRequest.response.statusCode = e.statusCode;

      if (e.additionalHeaders != null) {
        e.additionalHeaders.forEach((name, values) {
          resourceRequest.response.headers.add(name, values);
        });
      }

      if (e.responseMessage != null) {
        resourceRequest.response.writeln(e.responseMessage);
      }

      resourceRequest.response.close();
    } catch (e, stacktrace) {
      var response = _exceptionHandler(this.resourceRequest, e, stacktrace);
      resourceRequest.respond(response);
    }
  }

  static Response _defaultExceptionHandler(ResourceRequest resourceRequest, dynamic exceptionOrError, StackTrace stacktrace) {
    print(
        "Path: ${resourceRequest.request.uri}\nError: $exceptionOrError\n $stacktrace");

    return new Response.serverError();
  }


  void handleRequest(ResourceRequest req) {
    resourceRequest = req;
    process();
  }
}

class _InternalControllerException {
  final String message;
  final int statusCode;
  final HttpHeaders additionalHeaders;
  final String responseMessage;

  _InternalControllerException(this.message, this.statusCode,
                               {HttpHeaders additionalHeaders: null,
                               String responseMessage: null}) : this.additionalHeaders = additionalHeaders,
  this.responseMessage = responseMessage;
}
