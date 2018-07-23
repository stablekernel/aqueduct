part of aqueduct_test.client;

/// Object to construct and execute an HTTP request during testing.
///
/// Test requests are typically executed via methods in [Agent] (e.g., [Agent.get]).
/// For more granular configuration than provided by those methods, directly configure an
/// this object and execute it with methods like [get] or [post].
///
/// Use [Agent.request] to create instances of this type.
class TestRequest {
  TestRequest._(this._client);

  HttpClient _client;
  Uri _baseUrl;

  /// The base URL of the request.
  ///
  /// For example, 'http://localhost:8000'. May contain base path segments. The [path] will be appended to this value
  /// when this request is executed.
  ///
  /// This property is set to [Agent.baseURL] of the creating agent.
  set baseURL(String baseURL) {
    _baseUrl = Uri.parse(baseURL);
  }

  String get baseURL => _baseUrl.toString();

  /// The path of the request; will be appended to [baseURL].
  String path;

  /// The Content-Type that [body] should be encoded in.
  ///
  /// [body] will be encoded according to the codec in [CodecRegistry] that matches this value.
  ///
  /// Defaults to [ContentType.json].
  ContentType contentType = ContentType.json;

  /// The body of the this request.
  ///
  /// Prior to execution, [body] will be encoded according to its [contentType] codec in [CodecRegistry].
  ///
  /// To disable encoded, set [encodeBody] to false: [body] must be a [List<int>] when encoding is disabled.
  dynamic body;

  /// Whether or not [body] should be encoded according to [contentType].
  ///
  /// Defaults to true. When true, [body] will automatically be encoded by selecting a codec from
  /// [CodecRegistry] by [contentType]. If false, [body] must be a [List<int>].
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
  /// See also [setBasicAuthorization], [accept], [bearerAuthorization] for setting common headers.
  Map<String, dynamic> headers = {};

  /// The full URL of this request.
  ///
  /// This value is derived from [baseURL], [path], and [query].
  String get requestURL {
    if (path == null || baseURL == null) {
      throw StateError("TestRequest must have non-null path and baseURL.");
    }

    var actualPath = path;
    while (actualPath.startsWith("/")) {
      actualPath = actualPath.substring(1);
    }

    var url = _baseUrl.resolve(actualPath).toString();
    if ((query?.length ?? 0) > 0) {
      final pairs = query.keys.map((key) {
        final val = query[key];
        if (val == null || val == true) {
          return "$key";
        } else {
          return "$key=${Uri.encodeComponent("$val")}";
        }
      });

      url = "$url?${pairs.join("&")}";
    }

    return url;
  }

  /// Sets the Authorization header of this request.
  ///
  /// Will apply the following header to this request:
  ///
  ///         Authorization: Basic Base64(username:password)
  void setBasicAuthorization(String username, String password) {
    headers[HttpHeaders.authorizationHeader] =
        "Basic ${const Base64Encoder().convert("$username:$password".codeUnits)}";
  }

  /// Sets the Authorization header of this request.
  ///
  /// Will apply the following header to this request:
  ///
  ///         Authorization: Bearer token
  set bearerAuthorization(String token) {
    headers[HttpHeaders.authorizationHeader] = "Bearer $token";
  }

  /// Sets the Accept header of this request.
  set accept(List<ContentType> contentTypes) {
    headers[HttpHeaders.acceptHeader] =
        contentTypes.map((ct) => ct.toString()).join(",");
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
    final uri = Uri.parse(requestURL);
    final lowercasedMethod = method.toLowerCase();

    if (body != null &&
        (lowercasedMethod == "get" || lowercasedMethod == "head")) {
      throw StateError(
          "Cannot set 'body' when using HTTP '${method.toUpperCase()}'.");
    }

    final request = await _client.openUrl(method.toUpperCase(), uri);

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
    final response = TestResponse._(rawResponse);

    // Trigger body to be decoded
    await response.body.decode();

    return response;
  }

  List<int> get _bodyBytes {
    if (body == null) {
      return null;
    }

    if (!encodeBody) {
      return body as List<int>;
    }

    final codec =
        CodecRegistry.defaultInstance.codecForContentType(contentType);

    if (codec == null) {
      // this check doesn't truly work, but if its a list, it's probably a list of bytes.
      // if its not, we'll get an exception when we try and write to the response
      if (body is! List<int>) {
        throw StateError("No codec for content type '$contentType'.");
      }

      return body as List<int>;
    }

    return codec.encode(body);
  }
}
