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
  const HTTPMethod(this.method) : this._parameters = null;

  /// The method that the marked request handler method corresponds to.
  ///
  /// Case-insensitive.
  final String method;

  final List<String> _parameters;

  HTTPMethod._fromMethod(HTTPMethod m, List<String> parameters)
      : this.method = m.method,
        this._parameters = parameters;

  bool _matchesRequest(Request req) {
    if (req.innerRequest.method.toLowerCase() != this.method.toLowerCase()) {
      return false;
    }

    if (req.path == null || req.path.variables == null) {
      if (this._parameters.length == 0) {
        return true;
      }
      return false;
    }

    if (req.path.variables.length != this._parameters.length) {
      return false;
    }

    for (var id in this._parameters) {
      if (req.path.variables[id] == null) {
        return false;
      }
    }

    return true;
  }
}

class HTTPHeader {
  const HTTPHeader(this.header);

  final String header;

  bool _matchesRequest(Request req) {
    return req.innerRequest.headers[header] != null;
  }
}