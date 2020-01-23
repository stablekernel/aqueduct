import 'request_path.dart';
import 'resource_controller.dart';
import 'serializable.dart';

/// Binds an instance method in [ResourceController] to an operation.
///
/// An operation is a request method (e.g., GET, POST) and a list of path variables. A [ResourceController] implements
/// an operation method for each operation it handles (e.g., GET /users/:id, POST /users). A method with this annotation
/// will be invoked when a [ResourceController] handles a request where [method] matches the request's method and
/// *all* [pathVariables] are present in the request's path. For example:
///
///         class MyController extends ResourceController {
///           @Operation.get('id')
///           Future<Response> getOne(@Bind.path('id') int id) async {
///             return Response.ok(objects[id]);
///           }
///         }
class Operation {
  const Operation(this.method,
      [String pathVariable1,
      String pathVariable2,
      String pathVariable3,
      String pathVariable4])
      : _pathVariable1 = pathVariable1,
        _pathVariable2 = pathVariable2,
        _pathVariable3 = pathVariable3,
        _pathVariable4 = pathVariable4;

  const Operation.get(
      [String pathVariable1,
      String pathVariable2,
      String pathVariable3,
      String pathVariable4])
      : method = "GET",
        _pathVariable1 = pathVariable1,
        _pathVariable2 = pathVariable2,
        _pathVariable3 = pathVariable3,
        _pathVariable4 = pathVariable4;

  const Operation.put(
      [String pathVariable1,
      String pathVariable2,
      String pathVariable3,
      String pathVariable4])
      : method = "PUT",
        _pathVariable1 = pathVariable1,
        _pathVariable2 = pathVariable2,
        _pathVariable3 = pathVariable3,
        _pathVariable4 = pathVariable4;

  const Operation.post(
      [String pathVariable1,
      String pathVariable2,
      String pathVariable3,
      String pathVariable4])
      : method = "POST",
        _pathVariable1 = pathVariable1,
        _pathVariable2 = pathVariable2,
        _pathVariable3 = pathVariable3,
        _pathVariable4 = pathVariable4;

  const Operation.delete(
      [String pathVariable1,
      String pathVariable2,
      String pathVariable3,
      String pathVariable4])
      : method = "DELETE",
        _pathVariable1 = pathVariable1,
        _pathVariable2 = pathVariable2,
        _pathVariable3 = pathVariable3,
        _pathVariable4 = pathVariable4;

  final String method;
  final String _pathVariable1;
  final String _pathVariable2;
  final String _pathVariable3;
  final String _pathVariable4;

  /// Returns a list of all path variables required for this operation.
  List<String> get pathVariables {
    return [_pathVariable1, _pathVariable2, _pathVariable3, _pathVariable4]
        .where((s) => s != null)
        .toList();
  }
}

/// Binds elements of an HTTP request to a [ResourceController]'s operation method arguments and properties.
///
/// See individual constructors and [ResourceController] for more details.
class Bind {
  /// Binds an HTTP query parameter to an [ResourceController] property or operation method argument.
  ///
  /// When the incoming request's [Uri]
  /// has a query key that matches [name], the argument or property value is set to the query parameter's value. For example,
  /// the request /users?foo=bar would bind the value `bar` to the variable `foo`:
  ///
  ///         @Operation.get()
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
  /// If the bound parameter is a positional argument in a operation method, it is required for that method. A 400 Bad Request
  /// will be sent and the operation method will not be invoked if the request does not contain the query key.
  ///
  /// If the bound parameter is an optional argument in a operation method, it is optional for that method. The value of
  /// the bound property will be null if it was not present in the request.
  ///
  /// If the bound parameter is a property without any additional metadata, it is optional for all methods in an [ResourceController].
  /// If the bound parameter is a property with [requiredBinding], it is required for all methods in an [ResourceController].
  const Bind.query(this.name)
      : bindingType = BindingType.query,
        accept = null,
        require = null,
        ignore = null,
        reject = null;

  /// Binds an HTTP request header to an [ResourceController] property or operation method argument.
  ///
  /// When the incoming request has a header with the name [name],
  /// the argument or property is set to the headers's value. For example,
  /// a request with the header `Authorization: Basic abcdef` would bind the value `Basic abcdef` to the `authHeader`  argument:
  ///
  ///         @Operation.get()
  ///         Future<Response> getUsers(@Bind.header("Authorization") String authHeader) async => ...;
  ///
  /// [name] is compared case-insensitively; both `Authorization` and `authorization` will match the same header.
  ///
  /// Parameters with this metadata may be [String], [bool], or any type that implements `parse` (e.g., [int.parse] or [DateTime.parse]).
  ///
  /// If the bound parameter is a positional argument in a operation method, it is required for that method. A 400 Bad Request
  /// will be sent and the operation method will not be invoked if the request does not contain the header.
  ///
  /// If the bound parameter is an optional argument in a operation method, it is optional for that method. The value of
  /// the bound property will be null if it was not present in the request.
  ///
  /// If the bound parameter is a property without any additional metadata, it is optional for all methods in an [ResourceController].
  /// If the bound parameter is a property with [requiredBinding], it is required for all methods in an [ResourceController].
  const Bind.header(this.name)
      : bindingType = BindingType.header,
        accept = null,
        require = null,
        ignore = null,
        reject = null;

  /// Binds an HTTP request body to an [ResourceController] property or operation method argument.
  ///
  /// The body of an incoming
  /// request is decoded into the bound argument or property. The argument or property *must* implement [Serializable] or be
  /// a [List<Serializable>]. If the property or argument is a [List<Serializable>], the request body must be able to be decoded into
  /// a [List] of objects (i.e., a JSON array) and [Serializable.read] is invoked for each object (see this method for parameter details).
  ///
  /// Example:
  ///
  ///
  ///       class UserController extends ResourceController {
  ///         @Operation.post()
  ///         Future<Response> createUser(@Bind.body() User user) async {
  ///           final username = user.name;
  ///           ...
  ///         }
  ///       }
  ///
  ///
  /// If the bound parameter is a positional argument in a operation method, it is required for that method.
  /// If the bound parameter is an optional argument in a operation method, it is optional for that method.
  /// If the bound parameter is a property without any additional metadata, it is optional for all methods in an [ResourceController].
  /// If the bound parameter is a property with [requiredBinding], it is required for all methods in an [ResourceController].
  ///
  /// Requirements that are not met will be throw a 400 Bad Request response with the name of the missing header in the JSON error body.
  /// No operation method will be called in this case.
  ///
  /// If not required and not present in a request, the bound arguments and properties will be null when the operation method is invoked.
  const Bind.body({this.accept, this.ignore, this.reject, this.require})
      : name = null,
        bindingType = BindingType.body;

  /// Binds a route variable from [RequestPath.variables] to an [ResourceController] operation method argument.
  ///
  /// Routes may have path variables, e.g., a route declared as follows has an optional path variable named 'id':
  ///
  ///         router.route("/users/[:id]");
  ///
  /// A operation
  /// method is invoked if it has exactly the same path bindings as the incoming request's path variables. For example,
  /// consider the above route and a controller with the following operation methods:
  ///
  ///         class UserController extends ResourceController {
  ///           @Operation.get()
  ///           Future<Response> getUsers() async => Response.ok(getAllUsers());
  ///           @Operation.get('id')
  ///           Future<Response> getOneUser(@Bind.path("id") int id) async => Response.ok(getUser(id));
  ///         }
  ///
  /// If the request path is /users/1, /users/2, etc., `getOneUser` is invoked because the path variable `id` is present and matches
  /// the [Bind.path] argument. If no path variables are present, `getUsers` is invoked.
  const Bind.path(this.name)
      : bindingType = BindingType.path,
        accept = null,
        require = null,
        ignore = null,
        reject = null;

  final String name;
  final BindingType bindingType;

  final List<String> accept;
  final List<String> ignore;
  final List<String> reject;
  final List<String> require;
}

enum BindingType { query, header, body, path }

/// Marks an [ResourceController] property binding as required.
///
/// Bindings are often applied to operation method arguments, in which required vs. optional
/// is determined by whether or not the argument is in required or optional in the method signature.
///
/// When properties are bound, they are optional by default. Adding this metadata to a bound controller
/// property requires that it for all operation methods.
///
/// For example, the following controller requires the header 'X-Request-ID' for both of its operation methods:
///
///         class UserController extends ResourceController {
///           @requiredBinding
///           @Bind.header("x-request-id")
///           String requestID;
///
///           @Operation.get('id')
///           Future<Response> getUser(@Bind.path("id") int id) async
///              => return Response.ok(await getUserByID(id));
///
///           @Operation.get()
///           Future<Response> getAllUsers() async
///              => return Response.ok(await getUsers());
///         }
const RequiredBinding requiredBinding = RequiredBinding();

/// See [requiredBinding].
class RequiredBinding {
  const RequiredBinding();
}
