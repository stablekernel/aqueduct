import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:analyzer/analyzer.dart';
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

  List<APIParameter> documentOperationParameters(Operation operation) {
    final binder = _binderForOperation(operation);

    bool usesFormEncodedData = operation.method == "POST" &&
        acceptedContentTypes.any((ct) => ct.primaryType == "application" && ct.subType == "x-www-form-urlencoded");

    final params = [binder.optionalParameters, binder.positionalParameters]
        .expand((p) => p)
        .map((param) => param.asDocumentedParameter());
    if (usesFormEncodedData) {
      return params.where((p) => p.location != APIParameterLocation.query).toList();
    }

    return params.toList();
  }

  String documentOperationSummary(Operation operation) {}

  String documentOperationDescription(Operation operation) {}

  APIRequestBody documentOperationRequestBody(Operation operation) {
    final binder = _binderForOperation(operation);
    final usesFormEncodedData = operation.method == "POST" &&
        acceptedContentTypes.any((ct) => ct.primaryType == "application" && ct.subType == "x-www-form-urlencoded");
    final boundBody = binder.positionalParameters.firstWhere((p) => p.binding is HTTPBody, orElse: () => null) ??
        binder.optionalParameters.firstWhere((p) => p.binding is HTTPBody, orElse: () => null);

    if (boundBody != null) {
      final body = new APIRequestBody()..isRequired = boundBody.isRequired;
      final HTTPSerializable instance = boundBody.boundValueType.newInstance(const Symbol(""), []).reflectee;
      for (final type in acceptedContentTypes) {
        body.content[type.toString()] = new APIMediaType(schema: instance.asSchemaObject());
      }

      return body;
    } else if (usesFormEncodedData) {
      final params = [binder.optionalParameters, binder.positionalParameters]
          .expand((p) => p)
          .map((param) => param.asDocumentedParameter())
          .where((p) => p.location == APIParameterLocation.query)
          .toList();

      final props = params.fold(<String, APIParameter>{}, (prev, elem) {
        prev[elem.name] = elem;
        return prev;
      });

      return new APIRequestBody()
        ..isRequired = true
        ..content = {"application/x-www-form-urlencoded": new APIMediaType(schema: new APISchemaObject.object(props))};
    }

    return null;
  }

  Map<String, APIResponse> documentOperationResponses(Operation operation) {
    return {};
  }

  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext context, APIPath path) {
    return RESTControllerBinder
        .binderForType(runtimeType)
        .methodBinders
        .where((method) => path.containsPathParameters(method.pathVariables))
        .fold(<String, APIOperation>{}, (opMap, method) {
      final annotation = firstMetadataOfType(Operation, reflect(this).type.instanceMembers[method.methodSymbol]);
      final op = new APIOperation()
        ..id = MirrorSystem.getName(method.methodSymbol)
        ..summary = documentOperationSummary(annotation)
        ..description = documentOperationDescription(annotation)
        ..parameters = documentOperationParameters(annotation)
        ..requestBody = documentOperationRequestBody(annotation)
        ..responses = documentOperationResponses(annotation);

      opMap[method.httpMethod.toLowerCase()] = op;

      return opMap;
    });
  }

  RESTControllerMethodBinder _binderForOperation(Operation operation) {
    return RESTControllerBinder.binderForType(runtimeType).methodBinders.firstWhere((m) {
      if (m.httpMethod != operation.method) {
        return false;
      }

      if (m.pathVariables.length == operation.pathVariables.length) {
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

class RESTControllerException implements Exception {
  RESTControllerException(this.message);

  final String message;

  @override
  String toString() => "RESTControllerException: $message";
}
