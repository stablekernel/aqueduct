import 'http_controller_internal.dart';
import 'http_controller.dart';
import 'request.dart';

/// Metadata for a [HTTPController] responder method that is triggered by an HTTP GET method.
///
/// Controller methods on [HTTPController]s that handle GET requests must be marked with this. For example,
///
///         class UserController extends HTTPController {
///           @httpGet
///           Future<Response> getUsers() async => new Response.ok(getAllUsers());
///         }
const HTTPMethod httpGet = const HTTPMethod("get");

/// Metadata for a [HTTPController] responder method that is triggered by an HTTP PUT method.
///
/// Controller methods on [HTTPController]s that handle PUT requests must be marked with this. For example,
///
///         class UserController extends HTTPController {
///           @httpPut
///           Future<Response> updateUser(@HTTPPath("id") int userID) async {
///             var updatedUser = await updateUserObject(userID, request.body.asMap());
///             return new Response.ok(updatedUser);
///           }
///         }
const HTTPMethod httpPut = const HTTPMethod("put");

/// Metadata for a [HTTPController] responder method that is triggered by an HTTP POST method.
///
/// Controller methods on [HTTPController]s that handle POST requests must be marked with this. For example,
///
///         class UserController extends HTTPController {
///           @httpPost
///           Future<Response> createUser() async {
///             var createdUser = await createUserObject(request.body.asMap());
///             return new Response.ok(createdUser);
///           }
///         }
const HTTPMethod httpPost = const HTTPMethod("post");

/// Metadata for a [HTTPController] responder method that is triggered by an HTTP DELETE method.
///
/// Controller methods on [HTTPController]s that handle DELETE requests must be marked with this. For example,
///
///         class UserController extends HTTPController {
///           @httpDelete
///           Future<Response> deleteUser(@HTTPPath("id") int userID) async {
///             await deleteUserObject(userID);
///             return new Response.ok(null);
///           }
///         }
const HTTPMethod httpDelete = const HTTPMethod("delete");

/// Metadata for indicating the HTTP Method a responder method in an [HTTPController] will respond to.
///
/// Each [HTTPController] responder method for an HTTP request must be marked with an instance
/// of [HTTPMethod]. See [httpGet], [httpPut], [httpPost] and [httpDelete] for concrete examples.
class HTTPMethod {
  /// Creates an instance of [HTTPMethod] that will case-insensitively match the [String] argument of an HTTP request.
  const HTTPMethod(this.method);

  /// The method that the marked request responder method corresponds to.
  ///
  /// Case-insensitive.
  final String method;
}

/// Marks an [HTTPController] [HTTPHeader] or [HTTPQuery] property as required.
///
/// Use when adding a required property to all endpoints in an [HTTPController],
/// this metadata ensures the header or query value is present in a [Request] or else
/// returns a 400 before calling responder methods. For example, GET /users/id
/// would require the header 'x-request-id' before invoking `getUser` in the following controller:
///
///         class UserController extends HTTPController {
///           @requiredHTTPParameter
///           @HTTPHeader("x-request-id")
///           String requestID;
///
///           @httpGet
///           Future<Response> getUser(@HTTPPath("id") int id)
///             async => return Response.ok(await getUserByID(id));
///         }
const HTTPRequiredParameter requiredHTTPParameter =
    const HTTPRequiredParameter();

/// See [requiredHTTPParameter].
class HTTPRequiredParameter {
  const HTTPRequiredParameter();
}

/// Metadata for an [HTTPController] responder method parameter to match on a route variable.
///
/// Routes may have path variables, e.g., a route declared as follows has a path variable named 'id':
///
///         router.route("/users/[:id]");
///
/// [HTTPController] responder methods may have parameters that will parse path variables. Those parameters
/// must have this metadata. The responder method will match on requests that have a matching path variable.
/// For example, the previous route has a path variable of 'id'. The following [HTTPController] will invoke `getUser()` for the request path `/users/1`:
///
///         class UserController extends HTTPController {
///           @httpGet
///           Future<Response> getUser(@HTTPPath("id") int id) async => ...;
///         }
///
/// The string argument to the constructor must match the name of the path variable declared in the route.
///
/// If multiple responder methods are declared for the same HTTP method, the responder method called is determined by matching path variables.
class HTTPPath extends HTTPParameter {
  const HTTPPath(String segment) : super(segment);
}

/// Marks properties of an [HTTPController] and parameters of responder methods as proxies for HTTP request header values.
///
/// See constructor.
class HTTPHeader extends HTTPParameter {
  /// Marks properties of an [HTTPController] and parameters of responder methods as proxies for HTTP request header values.
  ///
  /// Properties of [HTTPController] and parameters of responder methods with this metadata will be set to the value of a request's HTTP header named [header].
  /// [header] is compared case-insensitively. For example, the following controller requires the header 'x-timestamp' to be an
  /// HTTP datetime value.
  ///
  ///       class UserController extends HTTPController {
  ///         @httpGet
  ///         Future<Response> getUser(@HTTPHeader("x-timestamp") DateTime timestamp) async => ...;
  ///       }
  ///
  /// If a declaration with this metadata is a positional argument in a responder method, it is required for that method.
  /// If a declaration with this metadata is an optional argument in a responder method, it is optional for that method.
  /// If a declaration with this metadata is a property without any additional metadata, it is optional for all methods in an [HTTPController].
  /// If a declaration with this metadata is a property with [requiredHTTPParameter], it is required for all methods in an [HTTPController].
  ///
  /// Requests with requirements that are not met will be responded to with a 400 status code, the name of the missing header in the JSON error body,
  /// and no responder method will be called.
  ///
  /// If not required and not present in a request, the value for parameters and properties with this metadata will be null.
  const HTTPHeader(String header) : super(header);
}


/// Marks properties of an [HTTPController] and parameters of responder methods as proxies for HTTP request query string values.
///
/// See constructor.
class HTTPQuery extends HTTPParameter {
  /// Marks properties of an [HTTPController] and parameters of responder methods as proxies for HTTP request query string values.
  ///
  /// Properties of [HTTPController] and parameters of responder methods with this metadata will be set to the value of a request's HTTP query parameter named [key].
  /// [key] is compared case-sensitively. For example, the following controller requires the query string value 'fooBar' to be an
  /// integer:
  ///
  ///       class UserController extends HTTPController {
  ///         @httpGet
  ///         Future<Response> getUser(@HTTPQuery("fooBar") int foobar) async => ...;
  ///       }
  ///
  /// If a declaration with this metadata is a positional argument in a responder method, it is required for that method.
  /// If a declaration with this metadata is an optional argument in a responder method, it is optional for that method.
  /// If a declaration with this metadata is a property without any additional metadata, it is optional for all methods in an [HTTPController].
  /// If a declaration with this metadata is a property with [requiredHTTPParameter], it is required for all methods in an [HTTPController].
  ///
  /// Requests with requirements that are not met will be responded to with a 400 status code, the name of the missing query parameter in the JSON error body,
  /// and no responder method will be called.
  ///
  /// If not required and not present in a request, the value for parameters and properties with this metadata will be null.
  const HTTPQuery(String key) : super(key);
}
