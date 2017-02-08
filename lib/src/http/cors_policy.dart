import 'dart:io';
import 'http.dart';

/// Describes a CORS policy for a [RequestController].
///
/// These instances can be set as a [RequestController.policy], which will
/// manage CORS requests according to the policy's properties.
class CORSPolicy {
  /// The default CORS policy.
  ///
  /// You may modify this default policy. All instances of [CORSPolicy] are instantiated
  /// using the values of this default policy. Do not modify this property
  /// unless you want the defaults to change application-wide.
  static CORSPolicy get defaultPolicy {
    if (_defaultPolicy == null) {
      _defaultPolicy = new CORSPolicy._defaults();
    }
    return _defaultPolicy;
  }

  static CORSPolicy _defaultPolicy;

  /// List of 'Simple' CORS headers.
  ///
  /// These are headers that are considered acceptable as part of any CORS request.
  static List<String> simpleHeaders = const [
    "accept",
    "accept-language",
    "content-language",
    "content-type"
  ];

  /// List of 'Simple' CORS Response headers.
  ///
  /// These headers can be returned in a response without explicitly exposing them.
  static List<String> simpleResponseHeaders = const [
    "cache-control",
    "content-language",
    "content-type",
    "content-type",
    "expires",
    "last-modified",
    "pragma"
  ];

  /// Create a new instance of [CORSPolicy].
  ///
  /// Values are set to match [defaultPolicy].
  CORSPolicy() {
    var def = defaultPolicy;
    allowedOrigins = def.allowedOrigins;
    allowCredentials = def.allowCredentials;
    exposedResponseHeaders = def.exposedResponseHeaders;
    allowedMethods = def.allowedMethods;
    allowedRequestHeaders = def.allowedRequestHeaders;
    cacheInSeconds = def.cacheInSeconds;
  }

  CORSPolicy._defaults() {
    allowedOrigins = ["*"];
    allowCredentials = true;
    exposedResponseHeaders = [];
    allowedMethods = ["POST", "PUT", "DELETE", "GET"];
    allowedRequestHeaders = [
      "origin",
      "authorization",
      "x-requested-with",
      "x-forwarded-for",
      "content-type"
    ];
    cacheInSeconds = 86400;
  }

  /// The list of case-sensitive allowed origins.
  ///
  /// Defaults to '*'. Case-sensitive. In the specification (http://www.w3.org/TR/cors/), this is 'list of origins'.
  List<String> allowedOrigins;

  /// Whether or not to allow use of credentials, including Authorization and cookies.
  ///
  /// Defaults to true. In the specification (http://www.w3.org/TR/cors/), this is 'supports credentials'.
  bool allowCredentials;

  /// Which response headers to expose to the client.
  ///
  /// Defaults to empty. In the specification (http://www.w3.org/TR/cors/), this is 'list of exposed headers'.
  List<String> exposedResponseHeaders;

  /// Which HTTP methods are allowed.
  ///
  /// Defaults to POST, PUT, DELETE, and GET. Case-sensitive. In the specification (http://www.w3.org/TR/cors/), this is 'list of methods'.
  List<String> allowedMethods;

  /// The allowed request headers.
  ///
  /// Defaults to authorization, x-requested-with, x-forwarded-for. Must be lowercase.
  /// Use in conjunction with [simpleHeaders]. In the specification (http://www.w3.org/TR/cors/), this is 'list of headers'.
  List<String> allowedRequestHeaders;

  /// The number of seconds to cache a pre-flight request for a requesting client.
  int cacheInSeconds;

  /// Returns a map of HTTP headers for a request based on this policy.
  ///
  /// This will add Access-Control-Allow-Origin, Access-Control-Expose-Headers and Access-Control-Allow-Credentials
  /// depending on the this policy.
  Map<String, dynamic> headersForRequest(Request request) {
    var origin = request.innerRequest.headers.value("origin");

    var headers = <String, dynamic>{};
    headers["Access-Control-Allow-Origin"] = origin;

    if (exposedResponseHeaders.length > 0) {
      headers["Access-Control-Expose-Headers"] =
          exposedResponseHeaders.join(", ");
    }

    if (allowCredentials) {
      headers["Access-Control-Allow-Credentials"] = "true";
    }

    return headers;
  }

  /// Whether or not this policy allows the Origin of the [request].
  ///
  /// Will return true if [allowedOrigins] contains the case-sensitive Origin of the [request],
  /// or that [allowedOrigins] contains *.
  bool isRequestOriginAllowed(HttpRequest request) {
    if (allowedOrigins.contains("*")) {
      return true;
    }

    var origin = request.headers.value("origin");
    if (allowedOrigins.contains(origin)) {
      return true;
    }

    return false;
  }

  /// Validates whether or not a preflight request matches this policy.
  ///
  /// Will return true if the policy agrees with the Access-Control-Request-* headers of the request, otherwise, false.
  bool validatePreflightRequest(HttpRequest request) {
    if (!isRequestOriginAllowed(request)) {
      return false;
    }

    var method = request.headers.value("access-control-request-method");
    if (!allowedMethods.contains(method)) {
      return false;
    }

    var requestedHeaders = request.headers
        .value("access-control-request-headers")
        ?.split(",")
        ?.map((str) => str.trim())
        ?.toList();
    if (requestedHeaders?.isNotEmpty ?? false) {
      var nonSimpleHeaders =
          requestedHeaders.where((str) => !simpleHeaders.contains(str));
      if (nonSimpleHeaders.any((h) => !allowedRequestHeaders.contains(h))) {
        return false;
      }
    }

    return true;
  }

  /// Returns a preflight response for a given [Request].
  ///
  /// Contains the Access-Control-Allow-* headers for a CORS preflight request according
  /// to this policy.
  Response preflightResponse(Request req) {
    var headers = {
      "Access-Control-Allow-Origin": req.innerRequest.headers.value("origin"),
      "Access-Control-Allow-Methods": allowedMethods.join(", "),
      "Access-Control-Allow-Headers": allowedRequestHeaders.join(", ")
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
