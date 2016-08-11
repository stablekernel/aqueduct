part of aqueduct;

/// 'GET' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle GET requests must be marked with this.
const HTTPMethod httpGet = const HTTPMethod("get");

/// 'PUT' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle PUT requests must be marked with this.
const HTTPMethod httpPut = const HTTPMethod("put");

/// 'POST' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle POST requests must be marked with this.
const HTTPMethod httpPost = const HTTPMethod("post");

/// 'DELETE' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle DELETE requests must be marked with this.
const HTTPMethod httpDelete = const HTTPMethod("delete");

/// 'PATCH' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle PATCH requests must be marked with this.
const HTTPMethod httpPatch = const HTTPMethod("patch");

/// Resource controller handler method metadata for indicating the HTTP method the controller method corresponds to.
///
/// Each [HTTPController] handler method for an HTTP request must be marked with an instance
/// of [HTTPMethod]. See [httpGet], [httpPut], [httpPost] and [httpDelete] for concrete examples.
class HTTPMethod {
  /// Creates an instance of [HTTPMethod] that will case-insensitively match the [String] argument of an HTTP request.
  const HTTPMethod(this.method);

  /// The method that the marked request handler method corresponds to.
  ///
  /// Case-insensitive.
  final String method;
}

/// Parent class for annotations used for optional parameters in controller methods
abstract class _HTTPParameter {
  const _HTTPParameter.required(this.externalName) : isRequired = true;
  const _HTTPParameter.optional(this.externalName) : isRequired = false;

  /// The name of the variable in the HTTP request.
  final String externalName;

  /// If [isRequired] is true, requests missing this parameter will not be directed
  /// to the controller method and will return a 400 immediately.
  final bool isRequired;
}

/// Metadata indicating a parameter to a controller's method should be set from
/// the HTTP header indicated by the [header] field. The [header] value is case-
/// insensitive.
class HTTPHeader extends _HTTPParameter {

  /// Creates a required HTTP header parameter.
  const HTTPHeader.required(String header) : super.required(header);

  /// Creates an optional HTTP header parameter.
  const HTTPHeader.optional(String header) : super.optional(header);
}

/// Metadata indicating a parameter to a controller's method should be set from
/// the query value (or form-encoded body) from the indicated [key]. The [key]
/// value is case-sensitive.
class HTTPQuery extends _HTTPParameter {

  /// Creates a required HTTP query parameter.
  const HTTPQuery.required(String key) : super.required(key);

  /// Creates an optional HTTP query parameter.
  const HTTPQuery.optional(String key) : super.optional(key);
}