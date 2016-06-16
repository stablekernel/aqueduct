part of aqueduct;

/// Describes a CORS policy for a [RequestHandler].
///
/// These instances can be set as a [RequestHandler]s [policy] property, which will
/// manage CORS requests according to the policy's properties.
class CORSPolicy {
  static CORSPolicy get DefaultPolicy {
    if (_defaultPolicy == null) {
      _defaultPolicy = new CORSPolicy._defaults();
    }
    return _defaultPolicy;
  }
  static CORSPolicy _defaultPolicy;

  CORSPolicy() {
    var defaultPolicy = DefaultPolicy;
    allowedOrigins = defaultPolicy.allowedOrigins;
    allowCredentials = defaultPolicy.allowCredentials;
    exposedResponseHeaders = defaultPolicy.exposedResponseHeaders;
    allowedMethods = defaultPolicy.allowedMethods;
    allowedRequestHeaders = defaultPolicy.allowedRequestHeaders;
    cacheInSeconds = defaultPolicy.cacheInSeconds;
  }

  CORSPolicy._defaults() {
    allowedOrigins = ["*"];
    allowCredentials = true;
    exposedResponseHeaders = [];
    allowedMethods = ["POST", "PUT", "DELETE", "GET"];
    allowedRequestHeaders = ["authorization", "x-requested-with", "content-type", "accept"];
    cacheInSeconds = 86400;
  }

  List<String> allowedOrigins;
  bool allowCredentials;
  List<String> exposedResponseHeaders;
  List<String> allowedMethods;
  List<String> allowedRequestHeaders;
  int cacheInSeconds;

  Map<String, dynamic> headersForRequest(Request request) {
    var origin = request.innerRequest.headers.value("origin");

    var headers = {};
    headers["Access-Control-Allow-Origin"] = origin;

    if (exposedResponseHeaders.length > 0) {
      headers["Access-Control-Expose-Headers"] = exposedResponseHeaders.join(", ");
    }

    headers["Access-Control-Allow-Credentials"] = allowCredentials ? "true" : "false";

    return headers;
  }

  bool isRequestOriginAllowed(HttpRequest request) {
    var origin = request.headers.value("origin");
    if (!allowedOrigins.contains("*") && !allowedOrigins.contains(origin)) {
      return false;
    }
    return true;
  }

  bool validatePreflightRequest(HttpRequest request) {
    var method = request.headers.value("access-control-request-method");
    if (!allowedMethods.contains(method)) {
      return false;
    }

    var requestedHeaders = request.headers.value("access-control-request-headers").split(",").map((str) => str.trim()).toList();
    if (requestedHeaders != null) {
      if (requestedHeaders.any((h) => !allowedRequestHeaders.contains(h))) {
        return false;
      }
    }

    return true;
  }

  Response preflightResponse(Request req) {
    var headers = {
      "Access-Control-Allow-Origin" : req.innerRequest.headers.value("origin"),
      "Access-Control-Allow-Methods" : allowedMethods.join(", "),
      "Access-Control-Allow-Headers" : allowedRequestHeaders.join(", ")
    };

    if (allowCredentials) {
      headers["Access-Control-Allow-Credentials"] = "true";
    }

    if (cacheInSeconds != null) {
      headers["Access-Control-Max-Age"] = "$cacheInSeconds";
    }

    return new Response.ok(null, headers: headers);
  }
}