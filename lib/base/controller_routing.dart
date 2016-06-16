part of aqueduct;

/// 'GET' HttpMethod metadata.
///
/// Handler methods on [HttpController]s that handle GET requests must be marked with this.
const HttpMethod httpGet = const HttpMethod("get");

/// 'PUT' HttpMethod metadata.
///
/// Handler methods on [HttpController]s that handle PUT requests must be marked with this.
const HttpMethod httpPut = const HttpMethod("put");

/// 'POST' HttpMethod metadata.
///
/// Handler methods on [HttpController]s that handle POST requests must be marked with this.
const HttpMethod httpPost = const HttpMethod("post");

/// 'DELETE' HttpMethod metadata.
///
/// Handler methods on [HttpController]s that handle DELETE requests must be marked with this.
const HttpMethod httpDelete = const HttpMethod("delete");

/// 'PATCH' HttpMethod metadata.
///
/// Handler methods on [HttpController]s that handle PATCH requests must be marked with this.
const HttpMethod httpPatch = const HttpMethod("patch");

/// Resource controller handler method metadata for indicating the HTTP method the controller method corresponds to.
///
/// Each [HttpController] handler method for an HTTP request must be marked with an instance
/// of [HttpMethod]. See [httpGet], [httpPut], [httpPost] and [httpDelete] for concrete examples.
class HttpMethod {
  /// Creates an instance of [HttpMethod] that will case-insensitively match the [String] argument of an HTTP request.
  const HttpMethod(this.method) : this._parameters = null;

  /// The method that the marked request handler method corresponds to.
  ///
  /// Case-insensitive.
  final String method;

  final List<String> _parameters;

  HttpMethod._fromMethod(HttpMethod m, List<String> parameters)
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
