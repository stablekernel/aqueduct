import 'dart:io';
import 'dart:mirrors';

import 'http_controller_internal.dart';
import 'http_controller.dart';
import 'request_path.dart';
import 'serializable.dart';
import '../db/managed/managed.dart';
import 'router.dart';
import 'body_decoder.dart';
import 'http_response_exception.dart';
import 'request.dart';

/// Binds an [HTTPController] responder method to HTTP GET.
///
/// [HTTPController] methods with this metadata will be invoked for HTTP GET requests
/// if their [HTTPPath] arguments match the [HTTPRequestPath.variables] of the incoming request.
/// For example, the following controller has two responder methods bound with this method. If the incoming
/// request has a valid 'id' path variable, the `getOneUser` is called, otherwise, the `getUsers` is called.
///
///         class UserController extends HTTPController {
///           @httpGet
///           Future<Response> getUsers() async => new Response.ok(getAllUsers());
///           @httpGet
///           Future<Response> getOneUser(@HTTPPath("id") int id) async => new Response.ok(getUser(id));
///         }
const HTTPMethod httpGet = const HTTPMethod("get");

/// Binds an [HTTPController] responder method to HTTP PUT.
///
/// [HTTPController] methods with this metadata will be invoked for HTTP PUT requests
/// if their [HTTPPath] arguments match the [HTTPRequestPath.variables] of the incoming request.
/// For example, the following controller invokes `updateUser` when it receives an HTTP PUT request:
///
///         class UserController extends HTTPController {
///           @httpPut
///           Future<Response> updateUser(@HTTPPath("id") int id) async
///             => new Response.ok(setUserFromBody(id, request.body.asMap()));
///         }
const HTTPMethod httpPut = const HTTPMethod("put");

/// Binds an [HTTPController] responder method to HTTP POST.
///
/// [HTTPController] methods with this metadata will be invoked for HTTP POST requests.
/// For example, the following controller invokes `createUser` when it receives an HTTP POST request:
///
///         class UserController extends HTTPController {
///           @httpPost
///           Future<Response> createUser() async
///             => new Response.ok(createUserFromMap(id, request.body.asMap()));
///         }
const HTTPMethod httpPost = const HTTPMethod("post");

/// Binds an [HTTPController] responder method to HTTP DELETE.
///
/// [HTTPController] methods with this metadata will be invoked for HTTP DELETE requests
/// if their [HTTPPath] arguments match the [HTTPRequestPath.variables] of the incoming request.
/// For example, the following controller invokes `deleteUser` when it receives an HTTP DELETE request:
///
///         class UserController extends HTTPController {
///           @httpDelete
///           Future<Response> deleteUser(@HTTPPath("id") int id) async
///             => new Response.ok(removeUser(id));
///         }
const HTTPMethod httpDelete = const HTTPMethod("delete");

/// Binds an [HTTPController] responder method to an HTTP Method (e.g., GET, POST)
///
/// [HTTPController] methods with this metadata will be invoked when [method] matches the HTTP method
/// of the incoming request.
///
/// For example, the following controller invokes `getOptions` when it receives an HTTP OPTIONS request:
///
///         class UserController extends HTTPController {
///           @HTTPMethod("options")
///           Future<Response> getOptions() => return new Response.ok(null);
///         }
///
/// This is the generic form of [httpGet], [httpPut], [httpPost] and [httpDelete].
class HTTPMethod {
  /// Creates an instance of [HTTPMethod] that will case-insensitively match the HTTP method of a request.
  const HTTPMethod(this.method);

  /// An HTTP method name.
  ///
  /// Case-insensitive.
  final String method;
}

/// Marks an [HTTPController] property binding as required.
///
/// Bindings are often applied to responder method arguments, in which required vs. optional
/// is determined by whether or not the argument is in required or optional in the method signature.
///
/// When properties are bound, they are optional by default. Adding this metadata to a bound controller
/// property requires that it for all responder methods.
///
/// For example, the following controller requires the header 'X-Request-ID' for both of its responder methods:
///
///         class UserController extends HTTPController {
///           @requiredHTTPParameter
///           @HTTPHeader("x-request-id")
///           String requestID;
///
///           @httpGet
///           Future<Response> getUser(@HTTPPath("id") int id)
///             async => return Response.ok(await getUserByID(id));
///
///           @httpGet
///           Future<Response> getAllUsers() async
///              => return Response.ok(await getUsers());
///         }
const HTTPRequiredParameter requiredHTTPParameter =
    const HTTPRequiredParameter();

/// See [requiredHTTPParameter].
class HTTPRequiredParameter {
  const HTTPRequiredParameter();
}

/// Binds a route variable from [HTTPRequestPath.variables] to an [HTTPController] responder method argument.
///
/// Routes may have path variables, e.g., a route declared as follows has a path variable named 'id':
///
///         router.route("/users/[:id]");
///
/// [HTTPController] responder methods may bind path variables to their arguments with this metadata. A responder
/// method is invoked if it has exactly the same path bindings as the incoming request's path variables. For example,
/// consider the above route and a controller with the following responder methods:
///
///         class UserController extends HTTPController {
///           @httpGet
///           Future<Response> getUsers() async => new Response.ok(getAllUsers());
///           @httpGet
///           Future<Response> getOneUser(@HTTPPath("id") int id) async => new Response.ok(getUser(id));
///         }
///
/// If the request path is /users/1, /users/2, etc., `getOneUser` is invoked because the path variable `id` is present and matches
/// the [HTTPPath] argument. If no path variables are present, `getUsers` is invoked.
class HTTPPath extends HTTPBinding {
  /// Binds a route variable from [HTTPRequestPath.variables] to an [HTTPController] responder method argument.
  ///
  /// [segment] matches the name of a path variable created by [Router]. See class description for more details.
  const HTTPPath(String segment) : super(segment);

  @override
  String get type => null;

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    return convertParameterWithMirror(
        request.path.variables[externalName], intoType);
  }
}

/// Binds an HTTP request header to an [HTTPController] property or responder method argument.
///
/// This metadata may be applied to a responder method argument or a property of an [HTTPController]. When the incoming request
/// has a matching header name, the argument or property is set to the header's value.
/// For example, the following controller reads the header 'x-timestamp' into `timestamp` for use
/// in the responder method:
///
///       class UserController extends HTTPController {
///         @httpGet
///         Future<Response> getUser(@HTTPHeader("x-timestamp") DateTime timestamp) async => ...;
///       }
///
/// The type of a bound property or argument must either be a [String] or implement a static `parse` method (e.g., [int.parse], [DateTime.parse]).
///
/// If a declaration with this metadata is a positional argument in a responder method, it is required for that method.
///     e.g. the above example shows a required positional argument
/// If a declaration with this metadata is an optional argument in a responder method, it is optional for that method.
///     e.g. `getUser({@HTTPHeader("x-timestamp") DateTime timestamp}) async => ...;`
/// If a declaration with this metadata is a property without any additional metadata, it is optional for all methods in an [HTTPController].
/// If a declaration with this metadata is a property with [requiredHTTPParameter], it is required for all methods in an [HTTPController].
///
/// Requirements that are not met will be evoke a 400 Bad Request response with the name of the missing header in the JSON error body.
/// No responder method will be called in this case.
///
/// If not required and not present in a request, the bound arguments and properties will be null when the responder method is invoked.
class HTTPHeader extends HTTPBinding {
  /// Binds an HTTP request header to an [HTTPController] property or responder method argument.
  ///
  /// [header] case-insensitively matches the name of a header of an incoming request. See class description for more details.
  const HTTPHeader(String header) : super(header);

  @override
  String get type => "Header";

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    var value = request.innerRequest.headers[externalName];
    return convertParameterListWithMirror(value, intoType);
  }
}

/// Binds an HTTP query parameter to an [HTTPController] property or responder method argument.
///
/// This metadata may be applied to a responder method argument or a property of an [HTTPController]. When the incoming request's [Uri]
/// has a matching query key, the argument or property is set to the query's value. Note that if the request is a POST with content-type 'application/x-www-form-urlencoded',
/// the query string included in the request body may still be bound to instances of this type.
///
/// For example, the following controller reads the query value 'since' into `timestamp` for use
/// in the responder method (e.g., http://host.com/users?since=2017-08-04T00:00:00Z
///
///       class UserController extends HTTPController {
///         @httpGet
///         Future<Response> getUser(@HTTPQuery("since") DateTime timestamp) async => ...;
///       }
///
/// The type of a bound property or argument may either be a [String], [bool] or implement a static `parse` method (e.g., [int.parse], [DateTime.parse]). It may also
/// be a [List] of any of the allowed typed, for which each query key-value pair will be added to this list.
///
/// If a declaration with this metadata is a positional argument in a responder method, it is required for that method.
///     e.g. the above example shows a required positional argument
/// If a declaration with this metadata is an optional argument in a responder method, it is optional for that method.
///     e.g. `getUser({@HTTPQuery("since") DateTime timestamp}) async => ...;`
/// If a declaration with this metadata is a property without any additional metadata, it is optional for all methods in an [HTTPController].
/// If a declaration with this metadata is a property with [requiredHTTPParameter], it is required for all methods in an [HTTPController].
///
/// Requirements that are not met will be evoke a 400 Bad Request response with the name of the missing header in the JSON error body.
/// No responder method will be called in this case.
///
/// If not required and not present in a request, the bound arguments and properties will be null when the responder method is invoked.
class HTTPQuery extends HTTPBinding {
  /// Binds an HTTP request path query element to an [HTTPController] property or responder method argument.
  ///
  /// [key] case-insensitively matches the name of a header of an incoming request. See class description for more details.
  const HTTPQuery(String key) : super(key);

  @override
  String get type => "Query Parameter";

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    var queryParameters = request.innerRequest.uri.queryParametersAll;
    dynamic value = queryParameters[externalName];
    if (value == null) {
      if (requestHasFormData(request)) {
        value = request.body.asMap()[externalName];
      }
    }

    return convertParameterListWithMirror(value, intoType);
  }
}

/// Binds an HTTP request body to an [HTTPController] property or responder method argument.
///
/// This metadata may be applied to a responder method argument or a property of an [HTTPController]. The body of an incoming
/// request is decoded into the argument or property. The argument or property *must* implement [HTTPSerializable] or be
/// a [List<HTTPSerializable>]. If the property or argument is a [List<HTTPSerializable>], the request body must be decoded into
/// a [List] of objects (i.e., a JSON array) and [HTTPSerializable.fromRequestBody] is invoked for each object.
///
/// Note that [ManagedObject] implements [HTTPSerializable].
///
/// For example, the following controller will read a JSON object from the request body and assign its key-value pairs
/// to the properties of `User`:
///
///
///       class UserController extends HTTPController {
///         @httpPost
///         Future<Response> createUser(@HTTPBody() User user) async {
///           var query = new Query<User)..values = user;
///
///           ...
///         }
///       }
///
/// If a declaration with this metadata is a positional argument in a responder method, it is required for that method.
///     e.g. the above example shows a required positional argument
/// If a declaration with this metadata is an optional argument in a responder method, it is optional for that method.
///     e.g. `getUser({@HTTPQuery("since") DateTime timestamp}) async => ...;`
/// If a declaration with this metadata is a property without any additional metadata, it is optional for all methods in an [HTTPController].
/// If a declaration with this metadata is a property with [requiredHTTPParameter], it is required for all methods in an [HTTPController].
///
/// Requirements that are not met will be evoke a 400 Bad Request response with the name of the missing header in the JSON error body.
/// No responder method will be called in this case. Validation only occurs if there is a request body.
///
/// If not required and not present in a request, the bound arguments and properties will be null when the responder method is invoked.
class HTTPBody extends HTTPBinding {
  /// Binds an HTTP request body to an [HTTPController] property or responder method argument.
  ///
  /// See class description for more details.

  const HTTPBody() : super(null);

  @override
  String get type => "Body";

  @override
  dynamic parse(ClassMirror intoType, Request request) {
    if (request.body.isEmpty) {
      return null;
    }

    if (intoType.isAssignableTo(reflectType(HTTPSerializable))) {
      if (!reflectType(request.body.decodedType)
          .isSubtypeOf(reflectType(Map))) {
        throw new HTTPResponseException(
            400, "Expected Map, got ${request.body.decodedType}");
      }

      var value = intoType.newInstance(new Symbol(""), []).reflectee
          as HTTPSerializable;
      value.fromRequestBody(request.body.asMap());

      return value;
    } else if (intoType.isSubtypeOf(reflectType(List))) {
      if (!reflectType(request.body.decodedType)
          .isSubtypeOf(reflectType(List))) {
        throw new HTTPResponseException(
            400, "Expected List, got ${request.body.decodedType}");
      }

      var bodyList = request.body.asList();
      if (bodyList.isEmpty) {
        return [];
      }

      var typeArg = intoType.typeArguments.first as ClassMirror;
      return bodyList.map((object) {
        if (!reflectType(object.runtimeType).isSubtypeOf(reflectType(Map))) {
          throw new HTTPResponseException(
              400, "Expected Map, got ${request.body.decodedType}");
        }

        var value = typeArg.newInstance(new Symbol(""), []).reflectee
            as HTTPSerializable;
        value.fromRequestBody(object);

        return value;
      }).toList();
    }

    throw new _HTTPBodyBindingException(
        "Failed to bind HTTPBody: ${intoType.reflectedType} is not HTTPSerializable or List<HTTPSerializable>");
  }
}

class _HTTPBodyBindingException implements Exception {
  _HTTPBodyBindingException(this.message);

  String message;

  @override
  String toString() => message;
}
