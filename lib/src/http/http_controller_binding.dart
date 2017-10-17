import 'http_controller_internal.dart';
import 'http_controller.dart';
import 'request_path.dart';
import 'serializable.dart';
import '../db/managed/managed.dart';


/// Binds elements of an HTTP request to a [HTTPController]'s operation method arguments and properties.
///
/// See individual constructors and [HTTPController] for more details.
class Bind {
  /// Binds an [HTTPController] operation method to GET requests.
  ///
  /// Equivalent to `Bind.method("get")`
  ///
  /// See [Bind.method].
  const Bind.get() : name = "get", _type = _BindType.method;

  /// Binds an [HTTPController] operation method to PUT requests.
  ///
  /// Equivalent to `Bind.method("put")`
  ///
  /// See [Bind.method].
  const Bind.put() : name = "put", _type = _BindType.method;

  /// Binds an [HTTPController] operation method to POST requests.
  ///
  /// Equivalent to `Bind.method("post")`
  ///
  /// See [Bind.method].
  const Bind.post() : name = "post", _type = _BindType.method;

  /// Binds an [HTTPController] operation method to DELETE requests.
  ///
  /// Equivalent to `Bind.method("delete")`
  ///
  /// See [Bind.method].
  const Bind.delete() : name = "delete", _type = _BindType.method;

  /// Binds an HTTP query parameter to an [HTTPController] property or operation method argument.
  ///
  /// When the incoming request's [Uri]
  /// has a query key that matches [name], the argument or property value is set to the query parameter's value. For example,
  /// the request /users?foo=bar would bind the value `bar` to the variable `foo`:
  ///
  ///         @Bind.method("get")
  ///         Future<Response> getUsers(@Bind.query("foo") String foo) async => ...;
  ///
  /// [name] is compared case-sensitively, i.e. `Foo` and `foo` are different.
  ///
  /// Note that if the request is a POST with content-type 'application/x-www-form-urlencoded',
  /// the query string in the request body is bound to arguments with this metadata.
  ///
  /// Parameters with this metadata may be [String], [bool], or any type that implements `parse` (e.g., [int.parse] or [DateTime.parse]). It may also
  /// be a [List] of any of the allowed types, for which each query key-value pair in the request [Uri] be available in the list.
  ///
  /// If a declaration with this metadata is a positional argument in a operation method, it is required for that method. A 400 Bad Request
  /// will be sent and the operation method will not be invoked if the request does not contain the query key.
  ///
  /// If a declaration with this metadata is an optional argument in a operation method, it is optional for that method. The value of
  /// the bound property will be null if it was not present in the request.
  ///
  /// If a declaration with this metadata is a property without any additional metadata, it is optional for all methods in an [HTTPController].
  /// If a declaration with this metadata is a property with [requiredHTTPParameter], it is required for all methods in an [HTTPController].
  const Bind.query(this.name) : _type = _BindType.query;

  /// Binds an HTTP method to a [HTTPController] operation method.
  ///
  /// See also [Bind.get], [Bind.put], [Bind.post], and [Bind.delete].
  ///
  /// [HTTPController] methods with this metadata will be invoked when [name] matches the HTTP method
  /// of the incoming request. [name] is case-insensitively compared; e.g. "GET" and "get" are identical.
  ///
  /// Note that multiple operation methods can have the same [Bind.method] metadata as long as each method
  /// has different [Bind.path] arguments. A operation method is invoked if both [Bind.method] and its [Bind.path] arguments
  /// match the incoming request.
  ///
  /// Example:
  ///
  ///         class UserController extends HTTPController {
  ///           @Bind.method("get")
  ///           Future<Response> getThings() => return new Response.ok(null);
  ///         }
  ///
  /// This is the generic form of [Bind.get], [Bind.put], [Bind.delete] and [Bind.post].
  const Bind.method(this.name) : _type  = _BindType.method;

  /// Binds an HTTP request header to an [HTTPController] property or operation method argument.
  ///
  /// When the incoming request has a header with the name [name],
  /// the argument or property is set to the headers's value. For example,
  /// a request with the header `Authorization: Basic abcdef` would bind the value `Basic abcdef` to the `authHeader`  argument:
  ///
  ///         @Bind.method("get")
  ///         Future<Response> getUsers(@Bind.header("Authorization") String authHeader) async => ...;
  ///
  /// [name] is compared case-insensitively; both `Authorization` and `authorization` will match the same header.
  ///
  /// Parameters with this metadata may be [String], [bool], or any type that implements `parse` (e.g., [int.parse] or [DateTime.parse]).
  ///
  /// If a declaration with this metadata is a positional argument in a operation method, it is required for that method. A 400 Bad Request
  /// will be sent and the operation method will not be invoked if the request does not contain the header.
  ///
  /// If a declaration with this metadata is an optional argument in a operation method, it is optional for that method. The value of
  /// the bound property will be null if it was not present in the request.
  ///
  /// If a declaration with this metadata is a property without any additional metadata, it is optional for all methods in an [HTTPController].
  /// If a declaration with this metadata is a property with [requiredHTTPParameter], it is required for all methods in an [HTTPController].
  const Bind.header(this.name) : _type  = _BindType.header;

  /// Binds an HTTP request body to an [HTTPController] property or operation method argument.
  ///
  /// The body of an incoming
  /// request is decoded into the bound argument or property. The argument or property *must* implement [HTTPSerializable] or be
  /// a [List<HTTPSerializable>]. If the property or argument is a [List<HTTPSerializable>], the request body must be able to be decoded into
  /// a [List] of objects (i.e., a JSON array) and [HTTPSerializable.readFromMap] is invoked for each object.
  ///
  /// Note that [ManagedObject] implements [HTTPSerializable].
  ///
  /// For example, the following controller will read a JSON object from the request body and assign its key-value pairs
  /// to the properties of `User`:
  ///
  ///
  ///       class UserController extends HTTPController {
  ///         @Bind.method("post")
  ///         Future<Response> createUser(@Bind.body() User user) async {
  ///           var query = new Query<User>()..values = user;
  ///
  ///           ...
  ///         }
  ///       }
  ///
  /// If a declaration with this metadata is a positional argument in a operation method, it is required for that method.
  /// If a declaration with this metadata is an optional argument in a operation method, it is optional for that method.
  /// If a declaration with this metadata is a property without any additional metadata, it is optional for all methods in an [HTTPController].
  /// If a declaration with this metadata is a property with [requiredHTTPParameter], it is required for all methods in an [HTTPController].
  ///
  /// Requirements that are not met will be evoke a 400 Bad Request response with the name of the missing header in the JSON error body.
  /// No operation method will be called in this case.
  ///
  /// If not required and not present in a request, the bound arguments and properties will be null when the operation method is invoked.
  const Bind.body() : name = null, _type  = _BindType.body;

  /// Binds a route variable from [HTTPRequestPath.variables] to an [HTTPController] operation method argument.
  ///
  /// Routes may have path variables, e.g., a route declared as follows has an optional path variable named 'id':
  ///
  ///         router.route("/users/[:id]");
  ///
  /// A operation
  /// method is invoked if it has exactly the same path bindings as the incoming request's path variables. For example,
  /// consider the above route and a controller with the following operation methods:
  ///
  ///         class UserController extends HTTPController {
  ///           @httpGet
  ///           Future<Response> getUsers() async => new Response.ok(getAllUsers());
  ///           @httpGet
  ///           Future<Response> getOneUser(@Bind.path("id") int id) async => new Response.ok(getUser(id));
  ///         }
  ///
  /// If the request path is /users/1, /users/2, etc., `getOneUser` is invoked because the path variable `id` is present and matches
  /// the [Bind.path] argument. If no path variables are present, `getUsers` is invoked.
  const Bind.path(this.name) : _type  = _BindType.path;

  final String name;
  final _BindType _type;

  /// Used internally
  HTTPBinding get binding {
    switch (_type) {
      case _BindType.query: return new HTTPQuery(name);
      case _BindType.method: return new HTTPMethod(name);
      case _BindType.header: return new HTTPHeader(name);
      case _BindType.body: return new HTTPBody();
      case _BindType.path: return new HTTPPath(name);
      default: return null;
    }
  }
}

enum _BindType {
  query, method, header, body, path
}

/// Binds an [HTTPController] operation method to HTTP GET requests.
///
/// Equivalent to [Bind.method] with "GET" argument.
const Bind httpGet = const Bind.method("get");

/// Binds an [HTTPController] operation method to HTTP PUT requests.
///
/// Equivalent to [Bind.method] with "PUT" argument.
const Bind httpPut = const Bind.method("put");

/// Binds an [HTTPController] operation method to HTTP POST requests.
///
/// Equivalent to [Bind.method] with "POST" argument.
const Bind httpPost = const Bind.method("post");

/// Binds an [HTTPController] operation method to HTTP DELETE requests.
///
/// Equivalent to [Bind.method] with "DELETE" argument requests.
const Bind httpDelete = const Bind.method("delete");

/// Marks an [HTTPController] property binding as required.
///
/// Bindings are often applied to operation method arguments, in which required vs. optional
/// is determined by whether or not the argument is in required or optional in the method signature.
///
/// When properties are bound, they are optional by default. Adding this metadata to a bound controller
/// property requires that it for all operation methods.
///
/// For example, the following controller requires the header 'X-Request-ID' for both of its operation methods:
///
///         class UserController extends HTTPController {
///           @requiredHTTPParameter
///           @Bind.header("x-request-id")
///           String requestID;
///
///           @Bind.method("get")
///           Future<Response> getUser(@Bind.path("id") int id) async
///              => return Response.ok(await getUserByID(id));
///
///           @Bind.method("get")
///           Future<Response> getAllUsers() async
///              => return Response.ok(await getUsers());
///         }
const HTTPRequiredParameter requiredHTTPParameter =
    const HTTPRequiredParameter();

/// See [requiredHTTPParameter].
class HTTPRequiredParameter {
  const HTTPRequiredParameter();
}

