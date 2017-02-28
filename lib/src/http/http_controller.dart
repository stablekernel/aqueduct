import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:analyzer/analyzer.dart';

import 'http.dart';
import 'http_controller_internal.dart';

/// Base class for grouping response logic for a group of endpoints.
///
/// Instances of this class respond to HTTP requests. This class must be subclassed to provide any behavior.
/// Instances are typically the last [RequestController] in a series of controllers. A new [HTTPController] instance must be created for each [Request],
/// therefore they must be added to a series of [RequestController]s with [generate]. A [Request] must have passed through a [Router]
/// prior to being delivered to an [HTTPController].
///
/// The primary responsibility of an [HTTPController] is receive [Request]s and map the [Request] to an individual 'responder method'
/// to generate a response. A responder method returns a [Response] wrapped in a [Future] and must have [HTTPMethod] metadata (e.g., [httpGet]
/// or [httpPost]). It may also have [HTTPPath], [HTTPQuery] and [HTTPHeader] parameters.
///
/// [Request]s sent to an [HTTPController] have already been routed according to their path by a [Router]. An [HTTPController] does further routing
/// based on the HTTP method and path variables of the [Request].
///
/// An [HTTPController] typically receives a group of routes from a [Router] that refer to a resource collection or individual resource. For example,
/// consider the following route:
///
///         router
///           .route("/users/[:id]")
///           .generate(() => new UserController());
///
/// The requests `/users` and `/users/1` are both routed to an instance of `UserController` (a subclass of `HTTPController`) in this example. Responder methods
/// would be implemented in `UserController` to handle both the collection (`/users`) and individual resource (`/users/1`) cases for each supported HTTP method the
/// controller wants to provide.
///
/// In the above example, a `UserController` would implement both `GET /users`, `GET /users/:id`, and `POST /users/` like so:
///
///         class UserController extends HTTPController {
///           // invoked for GET /users
///           @httpGet
///           Future<Response> getAllUsers() async
///             => new Response.ok(await fetchAllUsers());
///
///           // invoked for GET /users/[0-9]+
///           @httpGet
///           Future<Response> getOneUser(@HTTPPath("id") int id) async =>
///             new Response.ok(await fetchOneUser(id));
///
///           // invoked for POST /users
///           @httpPost
///           Future<Response> createUser() async =>
///             return new Response.ok(await createUserFromBody(request.body.asMap()));
///         }
///
/// The responder method is selected by first evaluating the HTTP method of the incoming [Request]. If no such method exists - here, for example, there
/// are not [httpPut] or [httpDelete] responder methods - a 405 status code is returned.
///
/// After evaluating the HTTP method, path variables (using the `:variableName` syntax in `Router`) are evaluated next.
/// If there are no path variables (e.g., `/users`), the responder method with no `HTTPPath` arguments is selected. Responder methods
/// with `HTTPPath` parameters must have the exact number and matching names for each path variable parsed in the request. In the above example,
/// the path variable is named `id` in [Router.route] and therefore the argument to [HTTPPath] is `id`.
///
/// If there is no responder method match for the incoming request's path variables, a 404 is returned and no responder method is invoked.
///
/// Responder methods may also have [HTTPHeader] and [HTTPQuery] parameters. Parameters in the positional parameters
/// of a responder method are required; if the header or query value is omitted from a request,
/// no responder method is selected and a 400 status code is returned.
///
/// [HTTPHeader] and [HTTPQuery] parameters in the optional part of a method signature are optional;
/// if the header or query value is omitted from the request, the responder method is still invoked
/// and those parameters are null. For example, the following requires that the request always contain
/// the header `X-Required`, which will be parsed to `int` and available in `requiredValue`. If it contains `email` in the query string,
/// that value will be available in `emailFilter` when this method is invoked. If it does not, the `emailFilter` is null.
///
///         class UserController extends HTTPController {
///           @httpGet
///           Future<Response> getAllUsers(
///             @HTTPHeader("X-Required") int requiredValue,
///             {@HTTPQuery("email") String emailFilter}) async {
///               ...
///           }
///         }
///
/// [HTTPController] subclasses may also declare properties that are marked with [HTTPHeader] and [HTTPQuery], in which case
/// all responder methods accept those header and query values.
///
///       class UserController extends RequestController {
///         @HTTPHeader("X-Opt") String optionalHeader;
///
///         @httpGet getUser(@HTTPPath ("id") int userID) async {
///           optionalHeader == request.innerRequest.headers["x-opt"]; // true
///
///           return new Response.ok(await userWithID(userID));
///         }
///       }
///
/// Properties are optional by default. [requiredHTTPParameter] will mark them as required for all responder methods.
///
/// An instance of this type will decode the [Request.body] prior to invoking a responder method.
///
/// See further documentation on https://stablekernel.github.io/aqueduct under HTTP guides.
///
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
  /// are the case-sensitive name of the path variables as defined by [Router.route].
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

  /// The default content type of responses from this [HTTPController].
  ///
  /// If the [Response.contentType] has not explicitly been set by a responder method in this controller, the controller will set
  /// that property with this value. Defaults to "application/json".
  ContentType responseContentType = ContentType.JSON;

  /// Executed prior to handling a request, but after the [request] has been set.
  ///
  /// This method is used to do pre-process setup and filtering. The [request] will be set, but its body will not be decoded
  /// nor will the appropriate responder method be selected yet. By default, returns the request. If this method returns a [Response], this
  /// controller will stop processing the request and immediately return the [Response] to the HTTP client.
  ///
  /// May not return any other [Request] than [req].
  Future<RequestOrResponse> willProcessRequest(Request req) async {
    return req;
  }

  /// Executed prior to a responder method being executed, but after the body has been processed.
  ///
  /// This method is called after the body has been processed by the decoder, but prior to the request being
  /// handled by the selected responder method. If there is no HTTP body in the request,
  /// this method is not called.
  void didDecodeRequestBody(HTTPBody decodedObject) {}

  /// Returns a [Response] for missing [HTTPParameter]s.
  ///
  /// This method is invoked by this instance when [HTTPParameter]s (like [HTTPQuery] or [HTTPHeader]s)
  /// are required, but not included in a request. The return value of this method will
  /// be sent back to the requesting client to signify the missing parameters.
  ///
  /// By default, this method returns a response with status code 400 and each missing header
  /// or query parameter is listed under the key "error" in a JSON object.
  ///
  /// This method can be overridden by subclasses to provide a different response.
  Response responseForMissingParameters(
      List<HTTPControllerMissingParameter> params) {
    var missingHeaders = params
        .where((p) => p.type == HTTPControllerMissingParameterType.header)
        .map((p) => p.externalName)
        .toList();
    var missingQueryParameters = params
        .where((p) => p.type == HTTPControllerMissingParameterType.query)
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

  bool _requestContentTypeIsSupported(Request req) {
    var incomingContentType = request.innerRequest.headers.contentType;
    return acceptedContentTypes.firstWhere((ct) {
          return ct.primaryType == incomingContentType.primaryType &&
              ct.subType == incomingContentType.subType;
        }, orElse: () => null) !=
        null;
  }

  Future<Response> _process() async {
    var controllerCache = HTTPControllerCache.cacheForType(runtimeType);
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
        await request.body.decodedData;
      } else {
        return new Response(HttpStatus.UNSUPPORTED_MEDIA_TYPE, null, null);
      }
    }

    if (request.body.hasContent != null) {
      didDecodeRequestBody(request.body);
    }

    var queryParameters = request.innerRequest.uri.queryParametersAll;
    var contentType = request.innerRequest.headers.contentType;
    if (contentType != null &&
        contentType.primaryType ==
            HTTPController
                ._applicationWWWFormURLEncodedContentType.primaryType &&
        contentType.subType ==
            HTTPController._applicationWWWFormURLEncodedContentType.subType) {
      queryParameters = request.body.asMap() as Map<String, List<String>> ?? {};
    }

    var orderedParameters =
        mapper.positionalParametersFromRequest(request, queryParameters);
    var controllerProperties = controllerCache.propertiesFromRequest(
        request.innerRequest.headers, queryParameters);
    var missingParameters = [orderedParameters, controllerProperties.values]
        .expand((p) => p)
        .where((p) => p is HTTPControllerMissingParameter)
        .map((p) => p as HTTPControllerMissingParameter)
        .toList();
    if (missingParameters.length > 0) {
      return responseForMissingParameters(missingParameters);
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

    return response;
  }

  @override
  Future<RequestOrResponse> processRequest(Request req) async {
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
    } on InternalControllerException catch (e) {
      var response = e.response;
      return response;
    }
  }

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) {
    var controllerCache = HTTPControllerCache.cacheForType(runtimeType);
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
        var paramLocation =
            _parameterLocationFromHTTPParameter(param.httpParameter);
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
      var controllerCache = HTTPControllerCache.cacheForType(runtimeType);
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

APIParameterLocation _parameterLocationFromHTTPParameter(HTTPParameter p) {
  if (p is HTTPPath) {
    return APIParameterLocation.path;
  } else if (p is HTTPQuery) {
    return APIParameterLocation.query;
  } else if (p is HTTPHeader) {
    return APIParameterLocation.header;
  }

  return null;
}
