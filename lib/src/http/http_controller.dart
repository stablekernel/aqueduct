import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:analyzer/analyzer.dart';

import 'http.dart';
import 'http_controller_internal/internal.dart';

/// Base class for implementing REST endpoints.
///
/// This class must be subclassed. A new instance must be created for each request and that request must have passed through a [Router] earlier in the channel, e.g.:
///
///         router.route("/path").generate(() => new HTTPControllerSubclass());
///
/// Subclasses implement instance methods that will be invoked when a [Request] meets certain criteria. These criteria are established by
/// *binding* elements of the HTTP request to instance methods and their parameters. For example, an instance method
/// that is bound to the HTTP `POST` method will be invoked when this controller handles a `POST` request.
///
///         class EmployeeController extends HTTPController {
///            @Bind.method("post")
///            Future<Response> createEmployee(...) async => new Response.ok(null);
///         }
///
/// Instance methods must have [Bind.method] metadata to respond to a request (see also [Bind.get], [Bind.post], [Bind.put] and [Bind.delete]). These
/// methods are called *operation methods*. Parameters of a operation method may bind other elements of an HTTP request, such as query
/// variables, headers, the message body and path variables.
///
/// There may be multiple operation methods for a given HTTP method. If more than one operation method matches in this way, the arguments of the method
/// with [Bind.path] metadata are evaluated to 'break the tie'. For example, the route `/employees/[:id]` contains an optional route variable named `id`.
/// A subclass can implement two operation methods, one for when `id` was present and the other for when it was not:
///
///         class EmployeeController extends HTTPController {
///            // This method gets invoked when the path is '/employees'
///            @Bind.method("get")
///            Future<Response> getEmployees() async {
///             return new Response.ok(employees);
///            }
///
///            // This method gets invoked when the path is '/employees/id'
///            @Bind.method("get")
///            Future<Response> getEmployees(@Bind.path("id") int id) async {
///             return new Response.ok(employees[id]);
///            }
///         }
///
/// If no operation method is found that meets both the HTTP method and route variable criteria, an appropriate error response is returned to the client
/// and no operation methods are called. In other words, the selection of a operation method is determined by the HTTP method and path of the request.
///
/// For the other types of binding - [Bind.query], [Bind.header], and [Bind.body] - a operation method is selected prior to evaluating whether the request
/// fulfill these bindings. If a operation method is selected, but the request does not have values that fulfill query, header and body criteria, a 400 Bad Request
/// response is sent and no operation method is invoked.
///
/// Query, header and body bindings may be optional if they are in the optional arguments portion of the operation method signature. When optional and the
/// corresponding value doesn't exist in the incoming request, the operation method is successfully invoked and the associated variable is null. For example,
/// this method is called whether the query parameter `name` is present or not:
///
///         class EmployeeController extends HTTPController {
///           @Bind.method("get")
///           Future<Response> getEmployees({@Bind.query("name") String name}) async {
///             if (name == null) {
///               return new Response.ok(employees);
///             }
///
///             return new Response.ok(employees.where((e) => e.name == name).toList());
///           }
///         }
///
/// See [Bind] for all possible bindings and https://aqueduct.io/docs/http/http_controller/ for more details.
///
/// [Request.body] will always be decoded prior to invoking a operation method.
@cannotBeReused
abstract class HTTPController extends Controller {
  /// The request being processed by this [HTTPController].
  ///
  /// It is this [HTTPController]'s responsibility to return a [Response] object for this request. Operation methods
  /// may access this request to determine how to respond to it.
  Request request;

  /// Parameters parsed from the URI of the request, if any exist.
  ///
  /// These values are attached by a [Router] instance that precedes this [Controller]. Is null
  /// if no [Router] preceded the controller and is the empty map if there are no values. The keys
  /// are the case-sensitive name of the path variables as defined by [Router.route].
  Map<String, String> get pathVariables => request.path?.variables;

  /// Types of content this [HTTPController] will accept.
  ///
  /// If a request is sent to this instance and has an HTTP request body and the Content-Type of the body is in this list,
  /// the request will be accepted and the body will be decoded according to that Content-Type.
  ///
  /// If the Content-Type of the request isn't within this list, the [HTTPController]
  /// will automatically respond with an Unsupported Media Type response.
  ///
  /// By default, an instance will accept HTTP request bodies with 'application/json; charset=utf-8' encoding.
  List<ContentType> acceptedContentTypes = [ContentType.JSON];

  /// The default content type of responses from this [HTTPController].
  ///
  /// If the [Response.contentType] has not explicitly been set by a operation method in this controller, the controller will set
  /// that property with this value. Defaults to "application/json".
  ContentType responseContentType = ContentType.JSON;

  /// Executed prior to handling a request, but after the [request] has been set.
  ///
  /// This method is used to do pre-process setup and filtering. The [request] will be set, but its body will not be decoded
  /// nor will the appropriate operation method be selected yet. By default, returns the request. If this method returns a [Response], this
  /// controller will stop processing the request and immediately return the [Response] to the HTTP client.
  ///
  /// May not return any other [Request] than [req].
  FutureOr<RequestOrResponse> willProcessRequest(Request req) => req;

  /// Callback invoked prior to decoding a request body.
  ///
  /// This method is invoked prior to decoding the request body.
  void willDecodeRequestBody(HTTPRequestBody body) {}

  /// Callback to indicate when a request body has been processed.
  ///
  /// This method is called after the body has been processed by the decoder, but prior to the request being
  /// handled by the selected operation method. If there is no HTTP request body,
  /// this method is not called.
  void didDecodeRequestBody(HTTPRequestBody decodedObject) {}

  @override
  void prepare() {
    var type = reflect(this).type.reflectedType;
    HTTPControllerBinder.addBinder(new HTTPControllerBinder(type));
    super.prepare();
  }

  bool _requestContentTypeIsSupported(Request req) {
    var incomingContentType = request.raw.headers.contentType;
    return acceptedContentTypes.firstWhere((ct) {
          return ct.primaryType == incomingContentType.primaryType && ct.subType == incomingContentType.subType;
        }, orElse: () => null) !=
        null;
  }

  Future<Response> _process() async {
    if (!request.body.isEmpty) {
      if (!_requestContentTypeIsSupported(request)) {
        return new Response(HttpStatus.UNSUPPORTED_MEDIA_TYPE, null, null);
      }
    }

    var binding = await HTTPControllerBinder.bindRequest(this, request);
    var response = await binding.invoke(reflect(this));
    if (!response.hasExplicitlySetContentType) {
      response.contentType = responseContentType;
    }

    return response;
  }

  @override
  Future<RequestOrResponse> handle(Request req) async {
    try {
      request = req;

      var preprocessedResult = await willProcessRequest(req);
      Response response;
      if (preprocessedResult is Request) {
        response = await _process();
      } else if (preprocessedResult is Response) {
        response = preprocessedResult;
      } else {
        response = new Response.serverError(body: {"error": "Preprocessing request did not yield result"});
      }

      return response;
    } on InternalControllerException catch (e) {
      var response = e.response;
      return response;
    }
  }

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) {
    var controllerCache = HTTPControllerBinder.binderForType(runtimeType);
    var reflectedType = reflect(this).type;
    var uri = reflectedType.location.sourceUri;
    var fileUnit = parseDartFile(resolver.resolve(uri));
    var classUnit = fileUnit.declarations
        .where((u) => u is ClassDeclaration)
        .map((cu) => cu as ClassDeclaration)
        .firstWhere((ClassDeclaration classDecl) {
      return classDecl.name.token.lexeme == MirrorSystem.getName(reflectedType.simpleName);
    });

    Map<Symbol, MethodDeclaration> methodMap = {};
    classUnit.childEntities.forEach((child) {
      if (child is MethodDeclaration) {
        methodMap[new Symbol(child.name.token.lexeme)] = child;
      }
    });

    return controllerCache.methodBinders.contents.values.expand((methods) => methods.values).map((cachedMethod) {
      var op = new APIOperation();
      op.id = APIOperation.idForMethod(this, cachedMethod.methodSymbol);
      op.method = cachedMethod.httpMethod.externalName;
      op.consumes = acceptedContentTypes;
      op.produces = [responseContentType];
      op.responses = documentResponsesForOperation(op);
      op.requestBody = documentRequestBodyForOperation(op);

      // Add documentation comments
      var methodDeclaration = methodMap[cachedMethod.methodSymbol];
      if (methodDeclaration != null) {
        var comment = methodDeclaration.documentationComment;
        var tokens = comment?.tokens ?? [];
        var lines = tokens.map((t) => t.lexeme.trimLeft().substring(3).trim()).toList();
        if (lines.length > 0) {
          op.summary = lines.first;
        }

        if (lines.length > 1) {
          op.description = lines.sublist(1, lines.length).join("\n");
        }
      }

      bool usesFormEncodedData = op.method.toLowerCase() == "post" &&
          acceptedContentTypes.any((ct) => ct.primaryType == "application" && ct.subType == "x-www-form-urlencoded");

      op.parameters = [
        cachedMethod.positionalParameters,
        cachedMethod.optionalParameters,
        controllerCache.propertyBinders
      ].expand((i) => i.toList()).map((param) {
        var paramLocation = _parameterLocationFromHTTPParameter(param.binding);
        if (usesFormEncodedData && paramLocation == APIParameterLocation.query) {
          paramLocation = APIParameterLocation.formData;
        }

        return new APIParameter()
          ..name = param.name
          ..required = param.isRequired
          ..parameterLocation = paramLocation
          ..schemaObject = (new APISchemaObject.fromTypeMirror(param.boundValueType));
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
        ..schema = new APISchemaObject(properties: {"error": new APISchemaObject.string()})
    ];

    var symbol = APIOperation.symbolForID(operation.id, this);
    if (symbol != null) {
      var controllerCache = HTTPControllerBinder.binderForType(runtimeType);
      var methodMirror = reflect(this).type.declarations[symbol];

      if (controllerCache.hasRequiredBindingsForMethod(methodMirror)) {
        responses.add(new APIResponse()
          ..statusCode = HttpStatus.BAD_REQUEST
          ..description = "Missing required query and/or header parameter(s)."
          ..schema = new APISchemaObject(properties: {"error": new APISchemaObject.string()}));
      }
    }

    return responses;
  }
}

APIParameterLocation _parameterLocationFromHTTPParameter(HTTPBinding p) {
  if (p is HTTPPath) {
    return APIParameterLocation.path;
  } else if (p is HTTPQuery) {
    return APIParameterLocation.query;
  } else if (p is HTTPHeader) {
    return APIParameterLocation.header;
  }

  return null;
}
