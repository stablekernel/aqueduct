import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

import 'http.dart';
import 'resource_controller_internal/internal.dart';

/// Controller for operating on an HTTP Resource.
///
/// [ResourceController]s provide a means to organize the logic for all operations on an HTTP resource. They also provide conveniences for handling these operations.
///
/// This class must be subclassed. Its instance methods handle operations on an HTTP resource. For example, the following
/// are operations: 'GET /employees', 'GET /employees/:id' and 'POST /employees'. An instance method is assigned to handle one of these operations. For example:
///
///         class EmployeeController extends ResourceController {
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
///         class EmployeeController extends ResourceController {
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
///         class EmployeeController extends ResourceController {
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
/// Bindings will automatically parse values into other types and validate that requests have the desired values. See [Bind] for all possible bindings and https://aqueduct.io/docs/http/resource_controller/ for more details.
///
/// To access the request directly, use [request]. Note that the [Request.body] of [request] will be decoded prior to invoking an operation method.
abstract class ResourceController extends Controller {
  /// The request being processed by this [ResourceController].
  ///
  /// It is this [ResourceController]'s responsibility to return a [Response] object for this request. Operation methods
  /// may access this request to determine how to respond to it.
  Request request;

  /// Parameters parsed from the URI of the request, if any exist.
  ///
  /// These values are attached by a [Router] instance that precedes this [Controller]. Is null
  /// if no [Router] preceded the controller and is the empty map if there are no values. The keys
  /// are the case-sensitive name of the path variables as defined by [Router.route].
  Map<String, String> get pathVariables => request.path?.variables;

  /// Types of content this [ResourceController] will accept.
  ///
  /// If a request is sent to this instance and has an HTTP request body and the Content-Type of the body is in this list,
  /// the request will be accepted and the body will be decoded according to that Content-Type.
  ///
  /// If the Content-Type of the request isn't within this list, the [ResourceController]
  /// will automatically respond with an Unsupported Media Type response.
  ///
  /// By default, an instance will accept HTTP request bodies with 'application/json; charset=utf-8' encoding.
  List<ContentType> acceptedContentTypes = [ContentType.JSON];

  /// The default content type of responses from this [ResourceController].
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
    final bound = new BoundController(reflect(this).type.reflectedType);
    final conflictingOperations = bound.conflictingOperations;
    if (conflictingOperations.length > 0) {
      final opNames = conflictingOperations.map((s) => "'$s'").join(", ");
      throw new StateError("Invalid controller. Controller '${runtimeType
          .toString()}' has ambiguous operations. Offending operating methods: $opNames.");
    }

    final unsatisfiableOperations = bound.unsatisfiableOperations;
    if (unsatisfiableOperations.length > 0) {
      final opNames = unsatisfiableOperations.map((s) => "'$s'").join(", ");
      throw new StateError("Invalid controller. Controller '${runtimeType.toString()}' has operations where "
          "parameter is bound with @Bind.path(), but path variable is not declared in @Operation(). Offending operation methods: $opNames");
    }

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

  /// Returns a documented list of [APIParameter] for [operation].
  ///
  /// This method will automatically create [APIParameter]s for any bound properties and operation method arguments.
  /// If an operation method requires additional parameters that cannot be bound using [Bind] annotations, override
  /// this method. When overriding this method, call the superclass' implementation and add the additional parameters
  /// to the returned list before returning the combined list.
  List<APIParameter> documentOperationParameters(APIDocumentContext context, Operation operation) {
    final bound = new BoundController(runtimeType);

    bool usesFormEncodedData = operation.method == "POST" &&
        acceptedContentTypes.any((ct) => ct.primaryType == "application" && ct.subType == "x-www-form-urlencoded");

    return bound
        .parametersForOperation(operation)
        .map((param) {
          if (param.binding is BoundBody) {
            return null;
          }
          if (usesFormEncodedData && param.binding is BoundQueryParameter) {
            return null;
          }

          return _documentParameter(context, operation, param);
        })
        .where((p) => p != null)
        .toList();
  }

  /// Returns a documented summary for [operation].
  ///
  /// By default, this method returns null and the summary is derived from documentation comments
  /// above the operation method. You may override this method to manually add a summary to an operation.
  String documentOperationSummary(APIDocumentContext context, Operation operation) {
    return null;
  }

  /// Returns a documented description for [operation].
  ///
  /// By default, this method returns null and the description is derived from documentation comments
  /// above the operation method. You may override this method to manually add a description to an operation.
  String documentOperationDescription(APIDocumentContext context, Operation operation) {
    return null;
  }

  /// Returns a documented request body for [operation].
  ///
  /// If an operation method binds an [Bind.body] argument or accepts form data, this method returns a [APIRequestBody]
  /// that describes the bound body type. You may override this method to take an alternative approach or to augment the
  /// automatically generated request body documentation.
  APIRequestBody documentOperationRequestBody(APIDocumentContext context, Operation operation) {
    final binder = _boundMethodForOperation(operation);
    final usesFormEncodedData = operation.method == "POST" &&
        acceptedContentTypes.any((ct) => ct.primaryType == "application" && ct.subType == "x-www-form-urlencoded");
    final boundBody = binder.positionalParameters.firstWhere((p) => p.binding is BoundBody, orElse: () => null) ??
        binder.optionalParameters.firstWhere((p) => p.binding is BoundBody, orElse: () => null);

    if (boundBody != null) {
      final type = boundBody.boundValueType.reflectedType;
      return new APIRequestBody.schema(context.schema.getObjectWithType(type),
          contentTypes: acceptedContentTypes.map((ct) => "${ct.primaryType}/${ct.subType}"),
          required: boundBody.isRequired);
    } else if (usesFormEncodedData) {
      final boundController = new BoundController(runtimeType);
      final props = boundController
          .parametersForOperation(operation)
          .where((p) => p.binding is BoundQueryParameter)
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

  /// Returns a map of possible responses for [operation].
  ///
  /// To provide documentation for an operation, you must override this method and return a map of
  /// possible responses. The key is a [String] representation of a status code (e.g., "200") and the value
  /// is an [APIResponse] object.
  Map<String, APIResponse> documentOperationResponses(APIDocumentContext context, Operation operation) {
    return {"200": new APIResponse("Successful response.")};
  }

  /// Returns a list of tags for [operation].
  ///
  /// By default, this method will return the name of the class. This groups each operation
  /// defined by this controller in the same tag. You may override this method
  /// to provide additional tags. You should call the superclass' implementation to retain
  /// the controller grouping tag.
  List<String> documentOperationTags(APIDocumentContext context, Operation operation) {
    final tag = "$runtimeType".replaceAll("Controller", "");
    return [tag];
  }

  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext context, String route, APIPath path) {
    final operations = new BoundController(runtimeType)
        .methods
        .where((method) => path.containsPathParameters(method.pathVariables));

    return operations.fold(<String, APIOperation>{}, (prev, method) {
      final operation = firstMetadataOfType(Operation, reflect(this).type.instanceMembers[method.methodSymbol]);

      final op = new APIOperation(
          MirrorSystem.getName(method.methodSymbol), documentOperationResponses(context, operation),
          summary: documentOperationSummary(context, operation),
          description: documentOperationDescription(context, operation),
          parameters: documentOperationParameters(context, operation),
          requestBody: documentOperationRequestBody(context, operation),
          tags: documentOperationTags(context, operation));

      if (op.summary == null) {
        context.defer(() async {
          final binder = _boundMethodForOperation(operation);

          final type = await DocumentedElement.get(this.runtimeType);
          op.summary = type[binder.methodSymbol].summary;
        });
      }

      if (op.description == null) {
        context.defer(() async {
          final binder = _boundMethodForOperation(operation);
          final type = await DocumentedElement.get(this.runtimeType);
          op.description = type[binder.methodSymbol].description;
        });
      }

      prev[method.httpMethod.toLowerCase()] = op;
      return prev;
    });
  }

  @override
  void documentComponents(APIDocumentContext context) {
    final binders = new BoundController(runtimeType).methods;
    binders.forEach((b) {
      [b.positionalParameters, b.optionalParameters]
          .expand((b) => b)
          .where((b) => b.binding is BoundBody)
          .map((b) => b.boundValueType)
          .forEach((b) {
            final type = b.reflectedType;
            if (!context.schema.hasRegisteredType(type)) {
              context.schema.register(MirrorSystem.getName(b.simpleName), HTTPSerializable.document(context, type), representation: type);
            }
      });
    });
  }

  APIParameter _documentParameter(
      APIDocumentContext context, Operation operation, BoundParameter param) {
    final schema = APIComponentDocumenter.documentType(context, param.boundValueType);
    final documentedParameter = new APIParameter(param.name, param.binding.location,
        schema: schema, required: param.isRequired, allowEmptyValue: schema.type == APIType.boolean);

    context.defer(() async {
      final controllerDocs = await DocumentedElement.get(runtimeType);
      final operationDocs = controllerDocs[_boundMethodForOperation(operation).methodSymbol];
      final documentation = controllerDocs[param.symbol] ?? operationDocs[param.symbol];
      if (documentation != null) {
        documentedParameter.description = "${documentation.summary ?? ""} ${documentation.description ?? ""}";
      }
    });

    return documentedParameter;
  }

  BoundMethod _boundMethodForOperation(Operation operation) {
    return new BoundController(runtimeType).methods.firstWhere((m) {
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

    var binding = await BoundController.bindRequestToOperation(this, request);
    var response = await binding.invoke(reflect(this));
    if (!response.hasExplicitlySetContentType) {
      response.contentType = responseContentType;
    }

    return response;
  }
}
