part of monadart;

class CORSPolicy {
  List<String> allowedOrigins = ["*"];
  bool allowCredentials = false;
  List<String> exposedResponseHeaders = [];

  List<String> allowedMethods = ["POST", "PUT", "DELETE", "GET"];
  List<String> allowedRequestHeaders = ["authorization"];
  int cacheInSeconds = 3600;

  Map<String, dynamic> headersForRequest(ResourceRequest request) {
    var origin = request.innerRequest.headers.value("origin");
    if (origin == null) {
      return null;
    }

    if (allowedOrigins.contains(origin)) {
      return {"Access-Control-Allow-Origin" : origin};
    }

    return null;
  }

  bool validatePreflightRequest(HttpRequest request) {
    if (!allowedOrigins.contains("*") && !allowedOrigins.contains(request.headers.value("origin"))) {
      return false;
    }

    if (!allowedMethods.contains(request.headers.value("access-control-request-method"))) {
      return false;
    }

    var requestedHeaders = request.headers["access-control-request-headers"];
    if (requestedHeaders.any((h) => !allowedRequestHeaders.contains(h))) {
      return false;
    }

    return true;
  }

  Response preflightResponse(ResourceRequest req) {
    if (!validatePreflightRequest(req.innerRequest)) {
      return new Response.ok(null);
    }

    return new Response.ok(null, headers: {
      "Access-Allow-Control-Origin" : "*",
      "Access-Control-Allow-Methods" : allowedMethods.join(","),
      "Access-Control-Allow-Headers" : allowedRequestHeaders.join(",")
    });
  }
}