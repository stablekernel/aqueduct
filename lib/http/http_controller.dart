part of aqueduct;

/// Base class for HTTP web service controller.
///
/// Subclasses of this class can process and respond to an HTTP request. A new instance of this type
/// should be created for every request is processes. Subclasses of this type implement 'responder methods' to
/// handle HTTP requests of a specified HTTP method and path. Responder methods must have [HTTPMethod] metadata and return
/// a [Future] that completes with [Response]. Responder methods may also have [HTTPPath], [HTTPHeader], [HTTPQuery]
/// parameters. An [HTTPController] evaluates a [Request] and finds a responder method that has a matching [HTTPMethod],
/// [HTTPPath], [HTTPHeader], [HTTPQuery] values.
///
/// Instances of this class may also declare properties that are marked with [HTTPHeader] and [HTTPQuery], in which case
/// all responder methods accept those header and query values.
///
///       class UserController extends RequestController {
///         @httpGet getUser(@HTTPPath ("id") int userID) async {
///           return new Response.ok(await _userWithID(userID));
///         }
///       }
@cannotBeReused
abstract class HTTPController extends RequestController {
  static ContentType _applicationWWWFormURLEncodedContentType =
      new ContentType("application", "x-www-form-urlencoded");

  /// The request being processed by this [HTTPController].
  ///
  /// It is this [HTTPController]'s responsibility to return a [Response] object for this request. Responder methods
  /// may access this request to determine how to respond to it.
  Request request;

  /// Parameters parsed from the URI of the request, if any exist.
  ///
  /// These values are attached by a [Router] instance that precedes this [RequestController]. Is null
  /// if no [Router] preceded the controller and is the empty map if there are no values. The keys
  /// are the case-sensitive name of the path variables as defined by the [route].
  Map<String, String> get pathVariables => request.path?.variables;

  /// Types of content this [HTTPController] will accept.
  ///
  /// By default, a resource controller will accept 'application/json' and 'application/x-www-form-urlencoded' requests.
  /// If a request is sent to an instance of [HTTPController] and has an HTTP request body,
  /// but the Content-Type of the request isn't within this list, the [HTTPController]
  /// will automatically respond with an Unsupported Media Type response.
  List<ContentType> acceptedContentTypes = [
    ContentType.JSON,
    _applicationWWWFormURLEncodedContentType
  ];

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
  /// nor will the appropriate responder method be selected yet. By default, returns the request. If this method returns a [Response], this
  /// controller will stop processing the request and immediately return the [Response] to the HTTP client.
  Future<RequestControllerEvent> willProcessRequest(Request req) async {
    return req;
  }

  /// Executed prior to a responder method being executed, but after the body has been processed.
  ///
  /// This method is called after the body has been processed by the decoder, but prior to the request being
  /// handled by the appropriate responder method.
  void didDecodeRequestBody(dynamic decodedObject) {}

  /// Executed prior to [Response] being sent, but after the responder method has been executed.
  ///
  /// This method is used to post-process a response before it is finally sent. By default, does nothing.
  /// This method will have no impact on when or how the [Response] is sent, is is simply informative.
  void willSendResponse(Response response) {}

  bool _requestContentTypeIsSupported(Request req) {
    var incomingContentType = request.innerRequest.headers.contentType;
    return acceptedContentTypes.firstWhere((ct) {
          return ct.primaryType == incomingContentType.primaryType &&
              ct.subType == incomingContentType.subType;
        }, orElse: () => null) !=
        null;
  }

  Future<Response> _process() async {
    var controllerCache = _HTTPControllerCache.cacheForType(runtimeType);
    var mapper = controllerCache.mapperForRequest(request);
    if (mapper == null) {
      return new Response(
          405,
          {
            "Allow": controllerCache
                .allowedMethodsForArity(pathVariables?.length ?? 0)
          },
          null);
    }

    if (request.innerRequest.contentLength > 0) {
      if (_requestContentTypeIsSupported(request)) {
        await request.decodeBody();
      } else {
        return new Response(HttpStatus.UNSUPPORTED_MEDIA_TYPE, null, null);
      }
    }

    if (requestBody != null) {
      didDecodeRequestBody(requestBody);
    }

    var queryParameters = request.innerRequest.uri.queryParametersAll;
    var contentType = request.innerRequest.headers.contentType;
    if (contentType != null &&
        contentType.primaryType ==
            HTTPController
                ._applicationWWWFormURLEncodedContentType.primaryType &&
        contentType.subType ==
            HTTPController._applicationWWWFormURLEncodedContentType.subType) {
      queryParameters = requestBody as Map<String, List<String>> ?? {};
    }

    var orderedParameters =
        mapper.positionalParametersFromRequest(request, queryParameters);
    var controllerProperties = controllerCache.propertiesFromRequest(
        request.innerRequest.headers, queryParameters);
    var missingParameters = [orderedParameters, controllerProperties.values]
        .expand((p) => p)
        .where((p) => p is _HTTPControllerMissingParameter)
        .map((p) => p as _HTTPControllerMissingParameter)
        .toList();
    if (missingParameters.length > 0) {
      return _missingRequiredParameterResponseIfNecessary(missingParameters);
    }

    controllerProperties
        .forEach((sym, value) => reflect(this).setField(sym, value));

    Future<Response> eventualResponse = reflect(this)
        .invoke(
            mapper.methodSymbol,
            orderedParameters,
            mapper.optionalParametersFromRequest(
                request.innerRequest.headers, queryParameters))
        .reflectee as Future<Response>;

    var response = await eventualResponse;
    if (!response.hasExplicitlySetContentType) {
      response.contentType = responseContentType;
    }

    willSendResponse(response);

    return response;
  }

  @override
  Future<RequestControllerEvent> processRequest(Request req) async {
    try {
      request = req;

      var preprocessedResult = await willProcessRequest(req);
      Response response = null;
      if (preprocessedResult is Request) {
        response = await _process();
      } else if (preprocessedResult is Response) {
        response = preprocessedResult;
      } else {
        response = new Response.serverError(
            body: {"error": "Preprocessing request did not yield result"});
      }

      return response;
    } on _InternalControllerException catch (e) {
      return e.response;
    }
  }

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) {
    var controllerCache = _HTTPControllerCache.cacheForType(runtimeType);
    var reflectedType = reflect(this).type;
    var uri = reflectedType.location.sourceUri;
    var fileUnit = parseDartFile(resolver.resolve(uri));
    var classUnit = fileUnit.declarations
        .where((u) => u is ClassDeclaration)
        .map((cu) => cu as ClassDeclaration)
        .firstWhere((ClassDeclaration classDecl) {
      return classDecl.name.token.lexeme ==
          MirrorSystem.getName(reflectedType.simpleName);
    });

    Map<Symbol, MethodDeclaration> methodMap = {};
    classUnit.childEntities.forEach((child) {
      if (child is MethodDeclaration) {
        methodMap[new Symbol(child.name.token.lexeme)] = child;
      }
    });

    return controllerCache.methodCache.values.map((cachedMethod) {
      var op = new APIOperation();
      op.id = APIOperation.idForMethod(this, cachedMethod.methodSymbol);
      op.method = cachedMethod.httpMethod.method;
      op.consumes = acceptedContentTypes;
      op.produces = [responseContentType];
      op.responses = documentResponsesForOperation(op);
      op.requestBody = documentRequestBodyForOperation(op);

      // Add documentation comments
      var methodDeclaration = methodMap[cachedMethod.methodSymbol];
      if (methodDeclaration != null) {
        var comment = methodDeclaration.documentationComment;
        var tokens = comment?.tokens ?? [];
        var lines =
            tokens.map((t) => t.lexeme.trimLeft().substring(3).trim()).toList();
        if (lines.length > 0) {
          op.summary = lines.first;
        }

        if (lines.length > 1) {
          op.description = lines.sublist(1, lines.length).join("\n");
        }
      }

      bool usesFormEncodedData = op.method.toLowerCase() == "post" &&
          acceptedContentTypes.any((ct) =>
              ct.primaryType == "application" &&
              ct.subType == "x-www-form-urlencoded");

      op.parameters = [
        cachedMethod.positionalParameters,
        cachedMethod.optionalParameters.values,
        controllerCache.propertyCache.values
      ].expand((i) => i.toList()).map((param) {
        var paramLocation = APIParameter
            ._parameterLocationFromHTTPParameter(param.httpParameter);
        if (usesFormEncodedData &&
            paramLocation == APIParameterLocation.query) {
          paramLocation = APIParameterLocation.formData;
        }

        return new APIParameter()
          ..name = param.name
          ..required = param.isRequired
          ..parameterLocation = paramLocation
          ..schemaObject =
              (new APISchemaObject.fromTypeMirror(param.typeMirror));
      }).toList();

      return op;
    }).toList();
  }

  @override
  List<APIResponse> documentResponsesForOperation(APIOperation operation) {
    List<APIResponse> responses = [
      new APIResponse()
        ..statusCode = 500
        ..description = "Something went wrong"
        ..schema = new APISchemaObject(
            properties: {"error": new APISchemaObject.string()})
    ];

    var symbol = APIOperation.symbolForID(operation.id, this);
    if (symbol != null) {
      var controllerCache = _HTTPControllerCache.cacheForType(runtimeType);
      var methodMirror = reflect(this).type.declarations[symbol];

      if (controllerCache.hasRequiredParametersForMethod(methodMirror)) {
        responses.add(new APIResponse()
          ..statusCode = HttpStatus.BAD_REQUEST
          ..description = "Missing required query and/or header parameter(s)."
          ..schema = new APISchemaObject(
              properties: {"error": new APISchemaObject.string()}));
      }
    }

    return responses;
  }
}

class _InternalControllerException implements Exception {
  final String message;
  final int statusCode;
  final HttpHeaders additionalHeaders;
  final String responseMessage;

  _InternalControllerException(this.message, this.statusCode,
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

Response _missingRequiredParameterResponseIfNecessary(
    List<_HTTPControllerMissingParameter> params) {
  var missingHeaders = params
      .where((p) => p.type == _HTTPControllerMissingParameterType.header)
      .map((p) => p.externalName)
      .toList();
  var missingQueryParameters = params
      .where((p) => p.type == _HTTPControllerMissingParameterType.query)
      .map((p) => p.externalName)
      .toList();

  StringBuffer missings = new StringBuffer();
  if (missingQueryParameters.isNotEmpty) {
    var missingQueriesString =
        missingQueryParameters.map((p) => "'${p}'").join(", ");
    missings.write("Missing query value(s): ${missingQueriesString}.");
  }
  if (missingQueryParameters.isNotEmpty && missingHeaders.isNotEmpty) {
    missings.write(" ");
  }
  if (missingHeaders.isNotEmpty) {
    var missingHeadersString = missingHeaders.map((p) => "'${p}'").join(", ");
    missings.write("Missing header(s): ${missingHeadersString}.");
  }

  return new Response.badRequest(body: {"error": missings.toString()});
}
