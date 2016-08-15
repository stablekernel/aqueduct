part of aqueduct;

/// Base class for web service handlers.
///
/// Subclasses of this class can process and respond to an HTTP request.
@cannotBeReused
abstract class HTTPController extends RequestHandler {
  static Map<Type, Map<String, _HTTPControllerCachedMethod>> _methodCache = {};
  static Map<Type, Map<Symbol, _HTTPControllerCachedParameter>> _controllerLevelParameters = {};
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
    var parametersTemplate = new _HTTPMethodParameterTemplate(this, request);
    if (parametersTemplate == null) {
      return new Response.notFound();
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
    
    var parametersValues = parametersTemplate.parseRequest();
    if (parametersValues.isMissingRequiredParameters) {
      return new Response.badRequest(body: {"error": parametersValues.missingParametersString});
    }

    parametersValues.controllerParametersForRequest.forEach((sym, value) => reflect(this).setField(sym, value));

    Future<Response> eventualResponse = reflect(this).invoke(
        parametersValues.methodSymbolForRequest,
        parametersValues.orderedParametersForRequest,
        parametersValues.optionalParametersForRequest
    ).reflectee;
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
        response = new Response.serverError(body: {"error" : "Preprocessing request did not yield result"});
      }

      return response;
    } on _InternalControllerException catch (e) {
      return e.response;
    }
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

      bool usesFormEncodedData = operation.method.toLowerCase() == "post" && acceptedContentTypes.any((ct) => ct.primaryType == "application" && ct.subType == "x-www-form-urlencoded");
      List<APIParameter> optionalParams = mm.parameters
          .where((pm) => pm.metadata.any((im) => im.reflectee is _HTTPParameter))
          .map((pm) {
            _HTTPParameter httpParameter = pm.metadata.firstWhere((im) => im.reflectee is _HTTPParameter).reflectee;
            APIParameterLocation pl;
            if (httpParameter is HTTPHeader) {
              pl = APIParameterLocation.header;
            } else if (usesFormEncodedData) {
              pl = APIParameterLocation.formData;
            } else {
              pl = APIParameterLocation.query;
            }
            return new APIParameter()
              ..name = MirrorSystem.getName(pm.simpleName)
              ..description = ""
              ..type = APIParameter.typeStringForVariableMirror(pm)
              ..required = httpParameter.isRequired
              ..parameterLocation = pl;
          }).toList();

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