part of aqueduct_test.client;

/// Object to construct an HTTP request during testing.
///
/// Test requests are typically executed via methods in [Agent] (e.g., [Agent.get]).
/// For more granular configuration than provided by those methods, directly configure an
/// this object and execute it with methods like [get] or [post].
///
/// Instantiate these objects via [Agent.request] instead of through this type's constructor.
class TestRequest {
  HttpClient _client;

  /// The base URL of the request.
  ///
  /// The [path] will be appended to this value. When [TestRequest] is instantiated by
  /// a [Agent], this property is set to [Agent.baseURL].
  String baseURL;

  /// The path of the request; will be appended to [baseURL].
  String path;

  /// The Content-Type that [body] should be encoded in.
  ///
  /// [body] will be encoded according to the codec in [HTTPCodecRepository] that matches this value.
  ///
  /// Defaults to [ContentType.JSON].
  ContentType contentType = ContentType.JSON;

  /// The body of the this request.
  ///
  /// Prior to execution, [body] will be encoded according to its [contentType] codec in [HTTPCodecRepository].
  ///
  /// To disable encoded, set [encodeBody] to false: [body] must be a [List<int>] when encoding is disabled.
  dynamic body;

  /// Whether or not [body] should be encoded according to [contentType].
  ///
  /// Defaults to true. When true, [body] will automatically be encoded by selecting a codec from
  /// [HTTPCodecRepository] by [contentType]. If false, [body] must be a [List<int>].
  bool encodeBody = true;

  /// Query parameters to add to the request.
  ///
  /// Key-value pairs in this property will be appended to the request URI after being properly URL encoded.
  Map<String, dynamic> query = {};

  /// HTTP headers to add to the request.
  ///
  /// Each pair is added as a header to the request. The key is the header name and the value
  /// is the header value. Values follow the rules of [HttpHeaders.add].
  ///
  /// See also [setBasicAuthorization], [accept], [bearer] for setting common headers.
  Map<String, dynamic> headers = {};

  /// The full URL of this request.
  ///
  /// This value is derived from [baseURL], [path], and [query].
  String get requestURL {
    String url;
    if (path.startsWith("/")) {
      url = "$baseURL$path";
    } else {
      url = [baseURL, path].join("/");
    }

    var queryElements = [];
    query?.forEach((key, val) {
      if (val == null || val == true) {
        queryElements.add("$key");
      } else {
        queryElements.add("$key=${Uri.encodeComponent("$val")}");
      }
    });

    if (queryElements.length > 0) {
      url = url + "?" + queryElements.join("&");
    }

    return url;
  }

  /// Sets the Authorization header of this request.
  ///
  /// Will apply the following header to this request:
  ///
  ///         Authorization: Basic Base64(username:password)
  void setBasicAuthorization(String username, String password) {
    headers[HttpHeaders.AUTHORIZATION] = "Basic ${new Base64Encoder().convert("$username:$password".codeUnits)}";
  }

  /// Sets the Authorization header of this request.
  ///
  /// Will apply the following header to this request:
  ///
  ///         Authorization: Bearer token
  set bearerAuthorization(String token) {
    headers[HttpHeaders.AUTHORIZATION] = "Bearer $token";
  }

  /// Sets the Accept header of this request.
  set accept(List<ContentType> contentTypes) {
    headers[HttpHeaders.ACCEPT] = contentTypes.map((ct) => ct.toString()).join(",");
  }

  /// Executes this request with HTTP POST.
  ///
  /// The returned [Future] will complete with an instance of [TestResponse] which can be used
  /// in test expectations using [hasResponse] or [hasStatus].
  Future<TestResponse> post() {
    return _executeRequest("POST");
  }

  /// Executes this request with the given HTTP verb.
  ///
  /// The returned [Future] will complete with an instance of [TestResponse] which can be used
  /// in test expectations using [hasResponse] or [hasStatus].
  Future<TestResponse> method(String verb) {
    return _executeRequest(verb);
  }

  /// Executes this request with HTTP PUT.
  ///
  /// The returned [Future] will complete with an instance of [TestResponse] which can be used
  /// in test expectations using [hasResponse] or [hasStatus].
  Future<TestResponse> put() {
    return _executeRequest("PUT");
  }

  /// Executes this request with HTTP GET.
  ///
  /// The returned [Future] will complete with an instance of [TestResponse] which can be used
  /// in test expectations using [hasResponse] or [hasStatus].
  Future<TestResponse> get() {
    return _executeRequest("GET");
  }

  /// Executes this request with HTTP DELETE.
  ///
  /// The returned [Future] will complete with an instance of [TestResponse] which can be used
  /// in test expectations using [hasResponse] or [hasStatus].
  Future<TestResponse> delete() {
    return _executeRequest("DELETE");
  }

  Future<TestResponse> _executeRequest(String method) async {
    var uri = Uri.parse(requestURL);
    var lowercasedMethod = method.toLowerCase();

    if (body != null && (lowercasedMethod == "get" || lowercasedMethod == "head")) {
      throw new StateError("Cannot set 'body' when using HTTP '${method.toUpperCase()}'.");
    }

    var request = await _client.openUrl(method.toUpperCase(), uri);

    headers?.forEach((headerKey, headerValue) {
      request.headers.add(headerKey, headerValue);
    });

    if (body != null) {
      final bytes = _bodyBytes;
      request.headers.contentType = contentType;
      request.headers.contentLength = bytes.length;
      request.add(bytes);
    }

    final rawResponse = await request.close();

    final response = new TestResponse._(rawResponse);

    // Trigger body to be decoded
    await response.body.decodedData;

    return response;
  }

  List<int> get _bodyBytes {
    if (body == null) {
      return null;
    }

    var codec = HTTPCodecRepository.defaultInstance.codecForContentType(contentType);

    if (codec == null) {
      if (body is! List<int>) {
        throw new ArgumentError(
            "Invalid request body. Body of type '${body.runtimeType}' not encodable as content-type '$contentType'.");
      }

      return body;
    }

    return codec.encode(body);
  }
}
