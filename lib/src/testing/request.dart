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
  /// Sets the body of this instance directly.
  ///
  /// Prior to execution, this property will be encoded according to its [contentType] and [HTTPCodecRepository].
  /// If [encodeBody] is false, this must be a [List<int>].
  ///
  /// Prefer to use [setBody], [json] or [formData] which set this property and [contentType]
  /// at the same time.
  ///
  /// Note: for backwards compatibility, if [body] is a [String] is encoded
  /// as UTF8 bytes by default and no codec is used.
  dynamic body;

  /// Whether or not [body] should be encoded according to [contentType].
  ///
  /// Defaults to true. When true, [body] will automatically be encoded by selecting a codec from
  /// [HTTPCodecRepository] by [contentType]. If false, [body] must be a [List<int>].
  bool encodeBody = true;

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

  /// Sets the [body] and [contentType].
  ///
  /// On execution, [body] will be encoded according to [contentType]. [contentType]
  /// defaults to [ContentType.JSON].
  void setBody(dynamic body, {ContentType contentType}) {
    this.contentType = contentType ?? ContentType.JSON;
    this.body = body;
  }

  /// JSON encodes a serialized value into [body] and sets [contentType].
  ///
  /// This method will encode [v] as JSON data and set it as the [body] of this request. [v] must be
  /// encodable to JSON ([Map]s, [List]s, [String]s, [int]s, etc.). The [contentType]
  /// will be set to [ContentType.JSON].
  set json(dynamic v) {
    setBody(v, contentType: ContentType.JSON);
  }

  /// Form-data encodes a serialized value into [body] and sets [contentType].
  ///
  /// This method will encode [args] as x-www-form-urlencoded data and set it as the [body] of this request. [args] must be
  /// a [Map<String, String>] . The [contentType] will be set to "application/x-www-form-urlencoded".
  set formData(Map<String, String> args) {
    setBody(args, contentType: new ContentType("application", "x-www-form-urlencoded", charset: "utf-8"));
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
    var uri = Uri.parse(requestURL);
    var lowercasedMethod = method.toLowerCase();
    if (body != null) {
      if (lowercasedMethod == "get" || lowercasedMethod == "delete" || lowercasedMethod == "head") {
        if (contentType.subType == "x-www-form-urlencoded") {
          if (body is! Map) {
            throw new TestClientException("Cannot encode body of type '${body.runtimeType}' into URI query string, must be a Map.");
          }

          var queryParams = queryParameters;
          queryParams.addAll(body);
          uri = uri.replace(queryParameters: queryParams);

          contentType = null;
          body = null;
        } else {
          throw new TestClientException("Cannot send HTTP body with HTTP method '$method'");
        }
      }
    }

    var request = await _client.openUrl(method, uri);

    headers?.forEach((headerKey, headerValue) {
      request.headers.add(headerKey, headerValue);
    });

    if (body != null) {
      request.headers.contentType = contentType;
      var bytes;
      if (body is String) {
        bytes = UTF8.encode(body);
      } else {
        bytes = _bodyBytes(body);
      }
      request.headers.contentLength = bytes.length;
      request.add(bytes);
    }

    var requestResponse = await request.close();

    var response = new TestResponse._(requestResponse);

    // Trigger body to be decoded
    await response.bodyDecoder.decodedData;

    return response;
  }

  List<int> _bodyBytes(dynamic body) {
    if (body == null) {
      return null;
    }

    var codec = HTTPCodecRepository.defaultInstance.codecForContentType(contentType);

    if (codec == null) {
      if (body is! List<int>) {
        throw new HTTPCodecException("Invalid body '${body.runtimeType}' for Content-Type '${contentType}'");
      }

      return body;
    }

    return codec.encode(body);
  }
}
