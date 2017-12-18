import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:analyzer/analyzer.dart';

import 'http.dart';
import 'rest_controller_internal/internal.dart';


/// Controller for operating on an HTTP Resource.
///
/// [RESTController]s provide a means to organize the logic for all operations on an HTTP resource. They also provide conveniences for handling these operations.
///
/// This class must be subclassed. Its instance methods handle operations on an HTTP resource. For example, the following
/// are operations: 'GET /employees', 'GET /employees/:id' and 'POST /employees'. An instance method is assigned to handle one of these operations. For example:
///
///         class EmployeeController extends RESTController {
///            @Operation.post()
///            Future<Response> createEmployee(...) async => new Response.ok(null);
///         }
///
/// Instance methods must have [Operation] annotation to respond to a request (see also [Operation.get], [Operation.post], [Operation.put] and [Operation.delete]). These
/// methods are called *operation methods*. Operation methods also take a variable list of path variables. An operation method is called if the incoming request's method and
/// present path variables match the operation annotation.
///
/// For example, the route `/employees/[:id]` contains an optional route variable named `id`.
/// A subclass can implement two operation methods, one for when `id` was present and the other for when it was not:
///
///         class EmployeeController extends RESTController {
///            // This method gets invoked when the path is '/employees'
///            @Operation.get()
///            Future<Response> getEmployees() async {
///             return new Response.ok(employees);
///            }
///
///            // This method gets invoked when the path is '/employees/id'
///            @Operation.get('id')
///            Future<Response> getEmployees(@Bind.path("id") int id) async {
///             return new Response.ok(employees[id]);
///            }
///         }
///
/// If there isn't an operation method for a request, an 405 Method Not Allowed error response is sent to the client and no operation methods are called.
///
/// For operation methods to correctly function, a request must have previously been handled by a [Router] to parse path variables.
///
/// Values from a request may be bound to operation method parameters. Parameters must be annotated with [Bind.path], [Bind.query], [Bind.header], or [Bind.body].
/// For example, the following binds an optional query string parameter 'name' to the 'name' argument:
///
///         class EmployeeController extends RESTController {
///           @Operation.get()
///           Future<Response> getEmployees({@Bind.query("name") String name}) async {
///             if (name == null) {
///               return new Response.ok(employees);
///             }
///
///             return new Response.ok(employees.where((e) => e.name == name).toList());
///           }
///         }
///
/// Bindings will automatically parse values into other types and validate that requests have the desired values. See [Bind] for all possible bindings and https://aqueduct.io/docs/http/rest_controller/ for more details.
///
/// To access the request directly, use [request]. Note that the [Request.body] of [request] will be decoded prior to invoking an operation method.
@cannotBeReused
abstract class RESTController extends Controller {
  /// The request being processed by this [RESTController].
  ///
  /// It is this [RESTController]'s responsibility to return a [Response] object for this request. Operation methods
  /// may access this request to determine how to respond to it.
  Request request;

  /// Parameters parsed from the URI of the request, if any exist.
  ///
  /// These values are attached by a [Router] instance that precedes this [Controller]. Is null
  /// if no [Router] preceded the controller and is the empty map if there are no values. The keys
  /// are the case-sensitive name of the path variables as defined by [Router.route].
  Map<String, String> get pathVariables => request.path?.variables;

  /// Types of content this [RESTController] will accept.
  ///
  /// If a request is sent to this instance and has an HTTP request body and the Content-Type of the body is in this list,
  /// the request will be accepted and the body will be decoded according to that Content-Type.
  ///
  /// If the Content-Type of the request isn't within this list, the [RESTController]
  /// will automatically respond with an Unsupported Media Type response.
  ///
  /// By default, an instance will accept HTTP request bodies with 'application/json; charset=utf-8' encoding.
  List<ContentType> acceptedContentTypes = [ContentType.JSON];

  /// The default content type of responses from this [RESTController].
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
    final binder = new RESTControllerBinder(reflect(this).type.reflectedType);
    final conflictingOperations = binder.conflictingOperations;
    if (conflictingOperations.length > 0) {
      final opNames = conflictingOperations.map((s) => "'$s'").join(", ");
      throw new RESTControllerException("${runtimeType.toString()} has ambiguous operations: $opNames");
    }

    final unsatisfiableOperations = binder.unsatisfiableOperations;
    if (unsatisfiableOperations.length > 0) {
      final opNames = unsatisfiableOperations.map((s) => "'$s'").join(", ");
      throw new RESTControllerException("${runtimeType
          .toString()} has has operations where @Bind.path() is used on a path variable not in @Operation(): $opNames");
    }

    RESTControllerBinder.addBinder(binder);
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

    var binding = await RESTControllerBinder.bindRequest(this, request);
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
    var controllerCache = RESTControllerBinder.binderForType(runtimeType);
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

    return controllerCache.methodBinders.map((cachedMethod) {
      var op = new APIOperation();
      op.id = APIOperation.idForMethod(this, cachedMethod.methodSymbol);
      op.method = cachedMethod.httpMethod.toLowerCase();
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

      op.parameters = <List<RESTControllerParameterBinder>>[
        cachedMethod.positionalParameters,
        cachedMethod.optionalParameters,
        controllerCache.propertyBinders
      ].expand((i) => i).where((p) => p.binding is! HTTPPath).map((param) {
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

      final pathParameters = cachedMethod.pathVariables.map((pathVar) {
        final furtherQualifiedPathVar = cachedMethod.positionalParameters
            .firstWhere((p) => p.binding is HTTPPath && p.binding.externalName == pathVar, orElse: () => null);
        final varType = furtherQualifiedPathVar?.boundValueType ?? reflectType(String);

        return new APIParameter()
            ..name = pathVar
            ..required = true
            ..parameterLocation = APIParameterLocation.path
            ..schemaObject = (new APISchemaObject.fromTypeMirror(varType));
      });

      op.parameters.addAll(pathParameters);

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
      var controllerCache = RESTControllerBinder.binderForType(runtimeType);
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

class RESTControllerException implements Exception {
  RESTControllerException(this.message);

  final String message;

  @override
  String toString() => "RESTControllerException: $message";
}
