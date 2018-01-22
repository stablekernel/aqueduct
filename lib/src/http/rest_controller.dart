import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

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
      throw new StateError("Invalid controller. Controller '${runtimeType
          .toString()}' has ambiguous operations. Offending operating methods: $opNames.");
    }

    final unsatisfiableOperations = binder.unsatisfiableOperations;
    if (unsatisfiableOperations.length > 0) {
      final opNames = unsatisfiableOperations.map((s) => "'$s'").join(", ");
      throw new StateError("Invalid controller. Controller '${runtimeType.toString()}' has operations where "
          "parameter is bound with @Bind.path(), but path variable is not declared in @Operation(). Offending operation methods: $opNames");
    }

    RESTControllerBinder.addBinder(binder);
    super.prepare();
  }

  @override
  FutureOr<RequestOrResponse> handle(Request req) async {
    request = req;

    var preprocessedResult = await willProcessRequest(req);
    if (preprocessedResult is Request) {
      return _process();
    } else if (preprocessedResult is Response) {
      return preprocessedResult;
    }

    throw new StateError(
        "'$runtimeType' returned invalid object from 'willProcessRequest'. Must return 'Request' or 'Response'.");
  }

  List<APIParameter> documentOperationParameters(APIDocumentContext context, Operation operation) {
    final binder = RESTControllerBinder.binderForType(runtimeType);

    bool usesFormEncodedData = operation.method == "POST" &&
        acceptedContentTypes.any((ct) => ct.primaryType == "application" && ct.subType == "x-www-form-urlencoded");

    return binder
        .parametersForOperation(operation)
        .map((param) {
          if (param.binding is HTTPBody) {
            return null;
          }
          if (usesFormEncodedData && param.binding is HTTPQuery) {
            return null;
          }

          return _documentParameter(context, operation, param);
        })
        .where((p) => p != null)
        .toList();
  }

  String documentOperationSummary(APIDocumentContext context, Operation operation) {
    return null;
  }

  String documentOperationDescription(APIDocumentContext context, Operation operation) {
    return null;
  }

  APIRequestBody documentOperationRequestBody(APIDocumentContext context, Operation operation) {
    final binder = _binderForOperation(operation);
    final usesFormEncodedData = operation.method == "POST" &&
        acceptedContentTypes.any((ct) => ct.primaryType == "application" && ct.subType == "x-www-form-urlencoded");
    final boundBody = binder.positionalParameters.firstWhere((p) => p.binding is HTTPBody, orElse: () => null) ??
        binder.optionalParameters.firstWhere((p) => p.binding is HTTPBody, orElse: () => null);

    if (boundBody != null) {
      final type = boundBody.boundValueType.reflectedType;

      return new APIRequestBody.schema(context.schema.getObjectWithType(type),
          contentTypes: acceptedContentTypes.map((ct) => ct.toString()), required: boundBody.isRequired);
    } else if (usesFormEncodedData) {
      final controller = RESTControllerBinder.binderForType(runtimeType);
      final props = controller
          .parametersForOperation(operation)
          .where((p) => p.binding is HTTPQuery)
          .map((param) => _documentParameter(context, operation, param))
          .fold(<String, APISchemaObject>{}, (prev, elem) {
        prev[elem.name] = elem.schema;
        return prev;
      });

      return new APIRequestBody.schema(new APISchemaObject.object(props),
          contentTypes: ["application/x-www-form-urlencoded"], required: true);
    }

    return null;
  }

  Map<String, APIResponse> documentOperationResponses(APIDocumentContext context, Operation operation) {
    return {};
  }

  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext context, APIPath path) {
    final operations = RESTControllerBinder
        .binderForType(runtimeType)
        .methodBinders
        .where((method) => path.containsPathParameters(method.pathVariables));

    return operations.fold(<String, APIOperation>{}, (prev, method) {
      final operation = firstMetadataOfType(Operation, reflect(this).type.instanceMembers[method.methodSymbol]);

      final op = new APIOperation(
          MirrorSystem.getName(method.methodSymbol), documentOperationResponses(context, operation),
          summary: documentOperationSummary(context, operation),
          description: documentOperationDescription(context, operation),
          parameters: documentOperationParameters(context, operation),
          requestBody: documentOperationRequestBody(context, operation));

      if (op.summary == null) {
        context.defer(() async {
          final binder = _binderForOperation(operation);

          final type = await DocumentedElement.get(this.runtimeType);
          op.summary = type[binder.methodSymbol].summary;
        });
      }

      if (op.description == null) {
        context.defer(() async {
          final binder = _binderForOperation(operation);
          final type = await DocumentedElement.get(this.runtimeType);
          op.description = type[binder.methodSymbol].description;
        });
      }

      prev[method.httpMethod.toLowerCase()] = op;
      return prev;
    });
  }

  APIParameter _documentParameter(
      APIDocumentContext context, Operation operation, RESTControllerParameterBinder param) {
    final schema = APIComponentDocumenter.documentType(context, param.boundValueType);
    final documentedParameter = new APIParameter(param.name, param.binding.location,
        schema: schema, required: param.isRequired, allowEmptyValue: schema.type == APIType.boolean);

    context.defer(() async {
      final controllerDocs = await DocumentedElement.get(runtimeType);
      final operationDocs = controllerDocs[_binderForOperation(operation).methodSymbol];
      final documentation = controllerDocs[param.symbol] ?? operationDocs[param.symbol];
      if (documentation != null) {
        documentedParameter.description = "${documentation.summary ?? ""} ${documentation.description ?? ""}";
      }
    });

    return documentedParameter;
  }

  RESTControllerMethodBinder _binderForOperation(Operation operation) {
    return RESTControllerBinder.binderForType(runtimeType).methodBinders.firstWhere((m) {
      if (m.httpMethod != operation.method) {
        return false;
      }

      if (m.pathVariables.length != operation.pathVariables.length) {
        return false;
      }

      if (!operation.pathVariables.every((p) => m.pathVariables.contains(p))) {
        return false;
      }

      return true;
    });
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
}
