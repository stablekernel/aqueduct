import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/auth/auth.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:runtime/runtime.dart';

import 'http.dart';

/// Controller for operating on an HTTP Resource.
///
/// [ResourceController]s provide a means to organize the logic for all operations on an HTTP resource. They also provide conveniences for handling these operations.
///
/// This class must be subclassed. Its instance methods handle operations on an HTTP resource. For example, the following
/// are operations: 'GET /employees', 'GET /employees/:id' and 'POST /employees'. An instance method is assigned to handle one of these operations. For example:
///
///         class EmployeeController extends ResourceController {
///            @Operation.post()
///            Future<Response> createEmployee(...) async => Response.ok(null);
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
///             return Response.ok(employees);
///            }
///
///            // This method gets invoked when the path is '/employees/id'
///            @Operation.get('id')
///            Future<Response> getEmployees(@Bind.path("id") int id) async {
///             return Response.ok(employees[id]);
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
///               return Response.ok(employees);
///             }
///
///             return Response.ok(employees.where((e) => e.name == name).toList());
///           }
///         }
///
/// Bindings will automatically parse values into other types and validate that requests have the desired values. See [Bind] for all possible bindings and https://aqueduct.io/docs/http/resource_controller/ for more details.
///
/// To access the request directly, use [request]. Note that the [Request.body] of [request] will be decoded prior to invoking an operation method.
abstract class ResourceController extends Controller
    implements Recyclable<Null> {
  ResourceController() {
    _runtime =
        (RuntimeContext.current.runtimes[runtimeType] as ControllerRuntime)
            ?.resourceController;
  }

  @override
  Null get recycledState => null;

  ResourceControllerRuntime _runtime;

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
  List<ContentType> acceptedContentTypes = [ContentType.json];

  /// The default content type of responses from this [ResourceController].
  ///
  /// If the [Response.contentType] has not explicitly been set by a operation method in this controller, the controller will set
  /// that property with this value. Defaults to "application/json".
  ContentType responseContentType = ContentType.json;

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
  void willDecodeRequestBody(RequestBody body) {}

  /// Callback to indicate when a request body has been processed.
  ///
  /// This method is called after the body has been processed by the decoder, but prior to the request being
  /// handled by the selected operation method. If there is no HTTP request body,
  /// this method is not called.
  void didDecodeRequestBody(RequestBody body) {}

  @override
  void restore(Null state) {
    /* no op - fetched from static cache in Runtime */
  }

  @override
  FutureOr<RequestOrResponse> handle(Request request) async {
    this.request = request;

    var preprocessedResult = await willProcessRequest(request);
    if (preprocessedResult is Request) {
      return _process();
    } else if (preprocessedResult is Response) {
      return preprocessedResult;
    }

    throw StateError(
        "'$runtimeType' returned invalid object from 'willProcessRequest'. Must return 'Request' or 'Response'.");
  }

  /// Returns a documented list of [APIParameter] for [operation].
  ///
  /// This method will automatically create [APIParameter]s for any bound properties and operation method arguments.
  /// If an operation method requires additional parameters that cannot be bound using [Bind] annotations, override
  /// this method. When overriding this method, call the superclass' implementation and add the additional parameters
  /// to the returned list before returning the combined list.
  @mustCallSuper
  List<APIParameter> documentOperationParameters(
      APIDocumentContext context, Operation operation) {
    return _runtime.documentOperationParameters(this, context, operation);
  }

  /// Returns a documented summary for [operation].
  ///
  /// By default, this method returns null and the summary is derived from documentation comments
  /// above the operation method. You may override this method to manually add a summary to an operation.
  String documentOperationSummary(
      APIDocumentContext context, Operation operation) {
    return null;
  }

  /// Returns a documented description for [operation].
  ///
  /// By default, this method returns null and the description is derived from documentation comments
  /// above the operation method. You may override this method to manually add a description to an operation.
  String documentOperationDescription(
      APIDocumentContext context, Operation operation) {
    return null;
  }

  /// Returns a documented request body for [operation].
  ///
  /// If an operation method binds an [Bind.body] argument or accepts form data, this method returns a [APIRequestBody]
  /// that describes the bound body type. You may override this method to take an alternative approach or to augment the
  /// automatically generated request body documentation.
  APIRequestBody documentOperationRequestBody(
      APIDocumentContext context, Operation operation) {
    return _runtime.documentOperationRequestBody(this, context, operation);
  }

  /// Returns a map of possible responses for [operation].
  ///
  /// To provide documentation for an operation, you must override this method and return a map of
  /// possible responses. The key is a [String] representation of a status code (e.g., "200") and the value
  /// is an [APIResponse] object.
  Map<String, APIResponse> documentOperationResponses(
      APIDocumentContext context, Operation operation) {
    return {"200": APIResponse("Successful response.")};
  }

  /// Returns a list of tags for [operation].
  ///
  /// By default, this method will return the name of the class. This groups each operation
  /// defined by this controller in the same tag. You may override this method
  /// to provide additional tags. You should call the superclass' implementation to retain
  /// the controller grouping tag.
  List<String> documentOperationTags(
      APIDocumentContext context, Operation operation) {
    final tag = "$runtimeType".replaceAll("Controller", "");
    return [tag];
  }

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext context, String route, APIPath path) {
    return _runtime.documentOperations(this, context, route, path);
  }

  @override
  void documentComponents(APIDocumentContext context) {
    _runtime.documentComponents(this, context);
  }

  bool _requestContentTypeIsSupported(Request req) {
    var incomingContentType = request.raw.headers.contentType;
    return acceptedContentTypes.firstWhere((ct) {
          return ct.primaryType == incomingContentType.primaryType &&
              ct.subType == incomingContentType.subType;
        }, orElse: () => null) !=
        null;
  }

  List<String> _allowedMethodsForPathVariables(Iterable<String> pathVariables) {
    return _runtime.operations
        .where((op) => op.isSuitableForRequest(null, pathVariables.toList()))
        .map((op) => op.method)
        .toList();
  }

  Future<Response> _process() async {
    if (!request.body.isEmpty) {
      if (!_requestContentTypeIsSupported(request)) {
        return Response(HttpStatus.unsupportedMediaType, null, null);
      }
    }

    final operation = _runtime.getOperationRuntime(
        request.raw.method, request.path.variables.keys.toList());
    if (operation == null) {
      throw Response(
          405,
          {
            "Allow":
                _allowedMethodsForPathVariables(request.path.variables.keys)
                    .join(", ")
          },
          null);
    }

    if (operation.scopes != null) {
      if (request.authorization == null) {
        // todo: this should be done compile-time
        Logger("aqueduct").warning(
            "'${runtimeType}' must be linked to channel that contains an 'Authorizer', because "
            "it uses 'Scope' annotation for one or more of its operation methods.");
        throw Response.serverError();
      }

      if (!AuthScope.verify(operation.scopes, request.authorization.scopes)) {
        throw Response.forbidden(body: {
          "error": "insufficient_scope",
          "scope": operation.scopes.map((s) => s.toString()).join(" ")
        });
      }
    }

    if (!request.body.isEmpty) {
      willDecodeRequestBody(request.body);
      await request.body.decode();
      didDecodeRequestBody(request.body);
    }

    final errors = <String>[];
    final args = ResourceControllerOperationArgs();
    args.positionalArguments = operation.positionalParameters
        .map((p) {
          try {
            final value = p.decode(request);
            if (value == null && p.isRequired) {
              errors
                  .add("missing required ${p.type} '${p.name ?? ""}'");
              return null;
            }

            return value;
          } on ArgumentError catch (e) {
            errors.add(e.message as String);
            return null;
          }
        })
        .where((p) => p != null)
        .toList();

    args.namedArguments =
        Map<Symbol, dynamic>.fromEntries(operation.namedParameters.map((p) {
      try {
        final value = p.decode(request);
        if (value == null) {
          return null;
        }

        return MapEntry(p.symbol, value);
      } on ArgumentError catch (e) {
        errors.add(e.message as String);
        return null;
      }
    }).where((e) => e != null));

    args.instanceVariables =
        Map<Symbol, dynamic>.fromEntries(operation.instanceVariables.map((p) {
      try {
        final value = p.decode(request);
        if (p.isRequired && value == null) {
          errors.add("missing required ${p.type} '${p.name ?? ""}'");
          return null;
        }

        return MapEntry(p.symbol, value);
      } on ArgumentError catch (e) {
        errors.add(e.message as String);
        return null;
      }
    }).where((e) => e != null));

    if (errors.isNotEmpty) {
      return Response.badRequest(body: {"error": errors.join(", ")});
    }

    final response = await operation.invoker(this, request, args);
    if (errors.isNotEmpty) {
      return Response.badRequest(body: {"error": errors.join(", ")});
    }

    if (!response.hasExplicitlySetContentType) {
      response.contentType = responseContentType;
    }

    return response;
  }
}

abstract class ResourceControllerRuntime {
  List<ResourceControllerOperationRuntime> get operations;

  ResourceControllerOperationRuntime getOperationRuntime(
      String method, List<String> pathVariables) {
    return operations.firstWhere(
        (op) => op.isSuitableForRequest(method, pathVariables),
        orElse: () => null);
  }

  void documentComponents(ResourceController rc, APIDocumentContext context);

  List<APIParameter> documentOperationParameters(
      ResourceController rc, APIDocumentContext context, Operation operation);

  APIRequestBody documentOperationRequestBody(
      ResourceController rc, APIDocumentContext context, Operation operation);

  Map<String, APIOperation> documentOperations(ResourceController rc,
      APIDocumentContext context, String route, APIPath path);
}

class ResourceControllerOperationRuntime {
  List<AuthScope> scopes;
  List<String> pathVariables;
  String method;

  List<ResourceControllerParameterRuntime> positionalParameters;
  List<ResourceControllerParameterRuntime> namedParameters;
  List<ResourceControllerParameterRuntime> instanceVariables;

  Future<Response> Function(ResourceController resourceController,
      Request request, ResourceControllerOperationArgs args) invoker;

  /// Checks if a request's method and path variables will select this binder.
  ///
  /// Note that [requestMethod] may be null; if this is the case, only
  /// path variables are compared.
  bool isSuitableForRequest(
      String requestMethod, List<String> requestPathVariables) {
    if (requestMethod != null && requestMethod.toUpperCase() != method) {
      return false;
    }

    if (pathVariables.length != requestPathVariables.length) {
      return false;
    }

    return requestPathVariables
        .every((varName) => pathVariables.contains(varName));
  }
}

abstract class ResourceControllerParameterRuntime {
  Symbol symbol;
  String name;

  /// Location in the request
  ///
  /// Values are: header, query parameter, body, path
  String type;

  bool isRequired;

  dynamic decode(Request request);
}

class ResourceControllerOperationArgs {
  Map<Symbol, dynamic> instanceVariables;
  Map<Symbol, dynamic> namedArguments;
  List<dynamic> positionalArguments;
}
