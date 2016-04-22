part of monadart;

class CORSPolicy {
  List<String> allowedOrigins = ["*"];
  bool allowCredentials = false;
  List<String> exposedResponseHeaders = [];

  List<String> allowedMethods = ["POST", "PUT", "DELETE", "GET"];
  List<String> allowedRequestHeaders = ["authorization", "x-requested-with", "content-type", "accept"];
  int cacheInSeconds = 3600;

  Map<String, dynamic> headersForRequest(ResourceRequest request) {
    var origin = request.innerRequest.headers.value("origin");

    var headers = {};
    if (allowedOrigins.contains("*") || allowedOrigins.contains(origin)) {
      headers["Access-Control-Allow-Origin"] = origin;
    }

    if (exposedResponseHeaders.length > 0) {
      headers["Access-Control-Expose-Headers"] = exposedResponseHeaders.join(" ,");
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

    var requestedHeaders = request.headers.value("access-control-request-headers")?.split(",")?.map((str) => str.trim())?.toList();
    if (requestedHeaders != null) {
      if (requestedHeaders.any((h) => !allowedRequestHeaders.contains(h.toLowerCase()))) {
        return false;
      }
    }

    return true;
  }

  Response preflightResponse(ResourceRequest req) {
    if (!validatePreflightRequest(req.innerRequest)) {
      return new Response.forbidden();
    }

    return new Response.ok(null, headers: {
      "Access-Control-Allow-Origin" : req.innerRequest.headers.value("origin"),
      "Access-Control-Allow-Methods" : allowedMethods.join(", "),
      "Access-Control-Allow-Headers" : allowedRequestHeaders.join(", ")
    });
  }
}