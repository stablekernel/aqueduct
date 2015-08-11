part of monadart;

const Route httpGet = const Route("get");
const Route httpPut = const Route("put");
const Route httpPost = const Route("post");
const Route httpDelete = const Route("delete");

class Route {
  final String method;
  final List<String> parameters;

  const Route(this.method, {List<String> parameters: const []})
      : this.parameters = parameters;

  Route.fromRoute(Route annotatedRoute, List<String> parameters)
      : this.method = annotatedRoute.method,
        this.parameters = parameters;

  bool matchesRequest(ResourceRequest req) {
    if (req.request.method.toLowerCase() != this.method.toLowerCase()) {
      return false;
    }

    if (req.pathParameters == null) {
      if (this.parameters.length == 0) {
        return true;
      }
      return false;
    }

    if (req.pathParameters.length != this.parameters.length) {
      return false;
    }

    for (var id in this.parameters) {
      if (req.pathParameters[id] == null) {
        return false;
      }
    }

    return true;
  }
}

class ResourceController {
  Function _exceptionHandler = _defaultExceptionHandler();
  void set exceptionHandler(void handler(ResourceRequest resourceRequest, dynamic exceptionOrError, StackTrace stacktrace)) {
    _exceptionHandler = handler;
  }

  ResourceRequest resourceRequest;
  Map<String, String> get pathParameters => resourceRequest.pathParameters;

  List<ContentType> acceptedContentTypes = [ContentType.JSON];
  ContentType responseContentType = ContentType.JSON;
  dynamic responseBodyEncoder = (body) => JSON.encode(body);

  dynamic requestBody;

  Symbol routeMethodSymbolForRequest(ResourceRequest req) {
    var symbol = null;

    var decls = reflect(this).type.declarations;
    for (var key in decls.keys) {
      var decl = decls[key];
      if (decl is MethodMirror) {
        var routeAttrs = decl.metadata.firstWhere(
            (attr) => attr.reflectee is Route, orElse: () => null);
        if (routeAttrs != null) {
          var params = (decl as MethodMirror).parameters
              .map((pm) => MirrorSystem.getName(pm.simpleName))
              .toList();
          Route r = new Route.fromRoute(routeAttrs.reflectee, params);

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

  dynamic readRequestBodyForRequest(ResourceRequest req) async {
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

  List<dynamic> parametersForRequest(ResourceRequest req, Symbol handlerMethodSymbol) {
    var handlerMirror =
        reflect(this).type.declarations[handlerMethodSymbol] as MethodMirror;

    return handlerMirror.parameters
        .map((p) => this.resourceRequest.pathParameters[MirrorSystem.getName(p.simpleName)])
        .toList();
  }

  void processResponse(Response responseObject) {
    resourceRequest.response.statusCode = responseObject.statusCode;

    if (responseObject.headers != null) {
      responseObject.headers.forEach((k, v) {
        resourceRequest.response.headers.add(k, v);
      });
    }


    if (responseObject.body != null) {
      resourceRequest.response.headers.contentType = responseContentType;
      resourceRequest.response.write(responseBodyEncoder(responseObject.body));
    }

    resourceRequest.response.close();
  }

  Future process() async {
    try {
      var methodSymbol = routeMethodSymbolForRequest(this.resourceRequest);
      var handlerParameters = parametersForRequest(this.resourceRequest, methodSymbol);
      requestBody = await readRequestBodyForRequest(this.resourceRequest);

      Future<Response> response =
          reflect(this).invoke(methodSymbol, handlerParameters).reflectee;

      response.then((responseObject) {
        processResponse(responseObject);
      }).catchError((error, stacktrace) {
        print("Error in processing response: $error $stacktrace");
        resourceRequest.response.statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
        resourceRequest.response.close();
      });
    } on _InternalControllerException catch (e) {
      resourceRequest.response.statusCode = e.statusCode;

      if (e.additionalHeaders != null) {
        e.additionalHeaders.forEach((name, values) {
          resourceRequest.response.headers.add(name, values);
        });
      }

      if(e.responseMessage != null) {
        resourceRequest.response.writeln(e.responseMessage);
      }

      resourceRequest.response.close();
    } catch (e, stacktrace) {
      _exceptionHandler(this.resourceRequest, e, stacktrace);
    }
  }

  static _defaultExceptionHandler(ResourceRequest resourceRequest, dynamic exceptionOrError, StackTrace stacktrace) {
    print(
      "Path: ${resourceRequest.request.uri}\nError: $e\n $stacktrace");

    resourceRequest.response.statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
    resourceRequest.response.close();
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
