import 'dart:io';
import 'dart:async';
import 'dart:convert';
import '../application/application.dart';
import '../application/application_configuration.dart';

/// Instances of this class are used during testing to make testing an HTTP server more convenient.
///
/// A [TestClient] is used to execute HTTP requests during tests. The client is configured to target
/// a 'test' instance of the application under test. The HTTP responses returned from the application
/// are wrapped in instances of [TestResponse], which are easy to test using [hasResponse] and [hasStatus]
/// test matchers.
class TestClient {
  /// Creates an instance that targets the configured [app].
  TestClient(Application app) {
    if (app.server == null) {
      throw new TestClientException(
          "TestClient failed to initialize from Application. "
              "Start the application prior to instantiating a TestClient and ensure that the "
              "application is run with `runOnMainIsolate: true`. You may also create a TestClient "
              "without an Application through its named constructors.");
    }

    var scheme = app.server.requiresHTTPS ? "https" : "http";
    var host = "localhost";
    var port = app.configuration.port;

    if (port == 0) {
      port = app.mainIsolateSink.server.server.port;
    }
    baseURL = "$scheme://$host:$port";
  }

  /// Creates an instance that targets http://localhost:[port].
  TestClient.onPort(int port) {
    baseURL = "http://localhost:$port";
  }

  /// Creates an instance from an [ApplicationConfiguration].
  TestClient.fromConfig(ApplicationConfiguration config, {bool useHTTPS: false}) {
    baseURL = "${useHTTPS ? "https" : "http"}://localhost:${config.port}";
  }

  /// The base URL that requests will be made against.
  String baseURL;

  /// When making a [clientAuthenticatedRequest], this client ID will be used if none is provided.
  ///
  /// This is the 'default' value for the [clientID] parameter in [clientAuthenticatedRequest]. The
  /// client ID along with [clientSecret] will be Base-64 encoded and set as a Basic Authorization header
  /// for requests made through [clientAuthenticatedRequest].
  String clientID;

  /// When making a [clientAuthenticatedRequest], this client secret will be used if none is provided.
  ///
  /// This is the 'default' value for the [clientSecret] parameter in [clientAuthenticatedRequest]. The
  /// client secret along with [clientID] will be Base-64 encoded and set as a Basic Authorization header
  /// for requests made through [clientAuthenticatedRequest].
  String clientSecret;

  /// When making an [authenticatedRequest], this access token will be used if none is provided.
  ///
  /// This is the 'default' value for the accessToken parameter in [authenticatedRequest]. This
  /// value will be provided in an Bearer Authorization header for requests made through [authenticatedRequest].
  String defaultAccessToken;

  /// Default headers to be added to any requests made by this client.
  ///
  /// By default, this value is the empty map.
  Map<String, String> defaultHeaders = {};

  HttpClient _client = new HttpClient();

  /// Executes a request with no Authorization header to the application under test.
  ///
  /// The [path] will be appended to the [baseURL] of this instance. You may omit or include
  /// the leading slash in the path, the result will be the same.
  TestRequest request(String path) {
    TestRequest r = new TestRequest()
      ..baseURL = this.baseURL
      ..path = path
      .._client = _client
      ..headers = new Map.from(defaultHeaders);

    return r;
  }

  /// Executes a request with a Basic Authorization header to the application under test.
  ///
  /// The [path] will be appended to the [baseURL] of this instance. You may omit or include
  /// the leading slash in the path, the result will be the same.
  ///
  /// If you do not provide a [clientID] and [clientSecret], the values of [TestClient.clientID] and [TestClient.clientSecret]
  /// will be used. If you provide only a [clientID] and no [clientSecret], [clientSecret] defaults to the empty string; i.e.
  /// [clientID] is considered a public client without a secret.
  TestRequest clientAuthenticatedRequest(String path,
      {String clientID: null, String clientSecret: null}) {

    if (clientID != null && clientSecret == null) {
      clientSecret = "";
    }
    clientID ??= this.clientID;
    clientSecret ??= this.clientSecret ?? "";

    var req = request(path)..setBasicAuthorization(clientID, clientSecret);

    return req;
  }

  /// Executes a request with a Bearer Authorization header to the application under test.
  ///
  /// The [path] will be appended to the [baseURL] of this instance. You may omit or include
  /// the leading slash in the path, the result will be the same.
  ///
  /// If you do not provide an [accessToken], the value of [defaultAccessToken]
  /// will be used.
  TestRequest authenticatedRequest(String path, {String accessToken: null}) {
    accessToken ??= defaultAccessToken;

    var req = request(path)..bearerAuthorization = accessToken;
    return req;
  }

  /// Closes this instances underlying HTTP client.
  void close() {
    _client.close(force: true);
  }
}

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
  /// there are setters for setting specific and common headers. See [basicAuthorization] and [accepts] as examples.
  Map<String, dynamic> get headers => _headers;
  void set headers(Map<String, dynamic> h) {
    if (!_headers.isEmpty) {
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
    String url = null;
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
  void set bearerAuthorization(String token) {
    addHeader(HttpHeaders.AUTHORIZATION, "Bearer $token");
  }

  /// Sets the Accept header of this request.
  void set accept(List<ContentType> contentTypes) {
    addHeader(
        HttpHeaders.ACCEPT, contentTypes.map((ct) => ct.toString()).join(","));
  }

  /// JSON encodes a serialized value into [body] and sets [contentType].
  ///
  /// This method will encode [v] as JSON data and set it as the [body] of this request. [v] must be
  /// encodable to JSON ([Map]s, [List]s, [String]s, [int]s, etc.). The [contentType]
  /// will be set to [ContentType.JSON].
  void set json(dynamic v) {
    body = JSON.encode(v);
    contentType = ContentType.JSON;
  }

  /// Form-data encodes a serialized value into [body] and sets [contentType].
  ///
  /// This method will encode [v] as x-www-form-urlencoded data and set it as the [body] of this request. [v] must be
  /// a [Map<String, String>] . The [contentType] will be set to "application/x-www-form-urlencoded".
  void set formData(Map<String, String> args) {
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

/// Instances of this type represent the response from executing a [TestRequest].
///
/// This class is used to create test expectations on responses from your application code. See also [hasStatus] and [hasResponse].
/// Do not create instances of this class manually - see [TestRequest] for more details.
class TestResponse {
  TestResponse._(this._innerResponse);

  final HttpClientResponse _innerResponse;

  /// The HTTP response body decoded according to its Content-Type.
  ///
  /// For example, if the response has a Content-Type of application/json, this value will be the body decoded
  /// from JSON into a [Map] or [List]. You may also use [asList] and [asMap] for additional typing clues for the analyzer.
  dynamic decodedBody;

  /// The raw HTTP response body.
  String body;

  /// HTTP response headers.
  HttpHeaders get headers => _innerResponse.headers;

  /// The Content-Length of the response if provided.
  int get contentLength => _innerResponse.contentLength;

  /// The status code of the response.
  int get statusCode => _innerResponse.statusCode;

  /// Whether or not the response is a redirect.
  bool get isRedirect => _innerResponse.isRedirect;

  /// The [decodedBody] typed to a [List].
  ///
  /// This is a convenience for casting [decodedBody] to an expected type as well as type-checking the decoded body.
  List<dynamic> get asList => decodedBody as List;

  /// The [decodedBody] typed to a [Map].
  ///
  /// This is a convenience for casting [decodedBody] to an expected type as well as type-checking the decoded body.
  Map<dynamic, dynamic> get asMap => decodedBody as Map;

  Future _decodeBody() {
    var completer = new Completer();
    _innerResponse.transform(UTF8.decoder).listen((contents) {
      body = contents;

      if (body != null) {
        var contentType = this._innerResponse.headers.contentType;
        if (contentType.primaryType == "application" &&
            contentType.subType == "json") {
          decodedBody = JSON.decode(body);
        } else {
          decodedBody = body;
        }
      }
    }).onDone(() {
      completer.complete();
    });

    return completer.future;
  }

  String toString() {
    var headerItems = headers.toString().split("\n");
    headerItems.removeWhere((str) => str == "");
    var headerString = headerItems.join("\n\t\t\t ");
    return "\n\tStatus Code: $statusCode\n\tHeaders: ${headerString}\n\tBody: $body";
  }
}

class TestClientException implements Exception {
  TestClientException(this.message);

  String message;

  String toString() => "TestClientException: $message";
}