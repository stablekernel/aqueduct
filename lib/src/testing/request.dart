part of aqueduct.test.client;

/// Instances of this type represent an HTTP request to be executed with a [TestClient].
///
/// There is no need to instantiate this class directly. See [TestClient.request], [TestClient.clientAuthenticatedRequest],
/// and [TestClient.authenticatedRequest]. Once returned an instance from one of these methods, you may configure
/// additional properties before executing it with methods like [TestRequest.get], [TestRequest.post], etc.
///
/// Instances of this class will create instances of [TestResponse] once executed that can be used in test expectations. See
/// also [hasResponse] and [hasStatus].
class TestRequest {
  HttpClient _client;

  /// The base URL of the request.
  ///
  /// The [path] will be appended to this value.
  String baseURL;

  /// The path of the request; will be appended to [baseURL].
  String path;

  /// The Content-Type of the [body].
  ///
  /// This defaults to [ContentType.JSON]. For form data or JSON data, use [formData] or [json] instead of setting this
  /// directly. For other encodings, you must set this value to the appropriate [ContentType].
  ContentType contentType = ContentType.JSON;

  /// The HTTP request body.
  ///
  /// For form data or JSON data, use [formData] or [json] instead of setting this
  /// directly. Those methods will set this property to the encoded value. For other content types,
  /// this value must be the encoded HTTP request body and [contentType] must also be set to
  /// an appropriate value.
  dynamic body;

  /// Query parameters to add to the request.
  ///
  /// Key-value pairs in this property will be appended to the request URI after being properly URL encoded.
  Map<String, dynamic> queryParameters = {};

  /// HTTP headers to add to the request.
  ///
  /// Prefer to use [addHeader] over directly setting this value. Additionally,
  /// there are setters for setting specific and common headers. See [setBasicAuthorization] and [accept] as examples.
  Map<String, dynamic> get headers => _headers;
  set headers(Map<String, dynamic> h) {
    if (_headers.isNotEmpty) {
      print(
          "WARNING: Setting TestRequest headers, but headers already have values.");
    }
    _headers = h;
  }

  Map<String, dynamic> _headers = {};

  /// The full URL of this request.
  ///
  /// This value is derived from [baseURL], [path], and [queryParameters].
  String get requestURL {
    String url;
    if (path.startsWith("/")) {
      url = "$baseURL$path";
    } else {
      url = [baseURL, path].join("/");
    }

    var queryElements = [];
    queryParameters?.forEach((key, val) {
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
    addHeader(HttpHeaders.AUTHORIZATION,
        "Basic ${new Base64Encoder().convert("$username:$password".codeUnits)}");
  }

  /// Sets the Authorization header of this request.
  ///
  /// Will apply the following header to this request:
  ///
  ///         Authorization: Bearer token
  set bearerAuthorization(String token) {
    addHeader(HttpHeaders.AUTHORIZATION, "Bearer $token");
  }

  /// Sets the Accept header of this request.
  set accept(List<ContentType> contentTypes) {
    addHeader(
        HttpHeaders.ACCEPT, contentTypes.map((ct) => ct.toString()).join(","));
  }

  /// JSON encodes a serialized value into [body] and sets [contentType].
  ///
  /// This method will encode [v] as JSON data and set it as the [body] of this request. [v] must be
  /// encodable to JSON ([Map]s, [List]s, [String]s, [int]s, etc.). The [contentType]
  /// will be set to [ContentType.JSON].
  set json(dynamic v) {
    body = JSON.encode(v);
    contentType = ContentType.JSON;
  }

  /// Form-data encodes a serialized value into [body] and sets [contentType].
  ///
  /// This method will encode [args] as x-www-form-urlencoded data and set it as the [body] of this request. [args] must be
  /// a [Map<String, String>] . The [contentType] will be set to "application/x-www-form-urlencoded".
  set formData(Map<String, String> args) {
    body = args.keys
        .map((key) => "$key=${Uri.encodeQueryComponent(args[key])}")
        .join("&");
    contentType = new ContentType("application", "x-www-form-urlencoded");
  }

  /// Adds a header to this request.
  void addHeader(String name, String value) {
    headers[name] = value;
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
    var request = await _client.openUrl(method, Uri.parse(requestURL));
    headers?.forEach((headerKey, headerValue) {
      request.headers.add(headerKey, headerValue);
    });

    if (body != null) {
      request.headers.contentType = contentType;
      request.headers.contentLength = body.length;
      request.add(UTF8.encode(body));
    }

    var requestResponse = await request.close();

    var response = new TestResponse._(requestResponse);
    await response._decodeBody();

    return response;
  }
}
