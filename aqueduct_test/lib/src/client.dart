library aqueduct_test.client;

import 'dart:async';
import 'dart:convert';
import 'dart:mirrors';
import 'dart:io';
import 'package:aqueduct/aqueduct.dart';
import 'matchers.dart';

part 'response.dart';
part 'request.dart';

/// Instances of this class are used during testing to make testing an HTTP server more convenient.
///
/// A [TestClient] is used to execute HTTP requests during tests. The client is configured to target
/// a 'test' instance of the application under test. The HTTP responses returned from the application
/// are wrapped in instances of [TestResponse], which are easy to test using [hasResponse] and [hasStatus]
/// test matchers.
class TestClient {
  /// Creates an instance that targets the configured [app].
  TestClient(Application app) : _application = app;

  /// Creates an instance that targets http://localhost:[_port].
  TestClient.onPort(this._port);

  /// Creates an instance from an [ApplicationOptions].
  TestClient.fromOptions(ApplicationOptions config, {bool useHTTPS: false}) :
    _scheme = useHTTPS ? "https" : "http",
    _host = "localhost",
    _port = config.port;


  /// The base URL that requests will be made against.
  String get baseURL {
    if (_application != null) {
      if (!_application.isRunning) {
        throw new TestClientException("Application under test is not running. Add `await app.start()` in a setup method.");
      }
      return "${_application.server.requiresHTTPS ? "https" : "http"}://localhost:${_application.channel.server.server.port}";
    }

    return "$_scheme://$_host:$_port";
  }

  String _scheme = "http";
  String _host = "localhost";
  int _port = 0;
  Application _application;

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
      {String clientID, String clientSecret}) {

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
  TestRequest authenticatedRequest(String path, {String accessToken}) {
    accessToken ??= defaultAccessToken;

    var req = request(path)..bearerAuthorization = accessToken;
    return req;
  }

  /// Closes this instances underlying HTTP client.
  void close() {
    _client.close(force: true);
  }
}


class TestClientException implements Exception {
  TestClientException(this.message);

  String message;

  @override
  String toString() => "TestClientException: $message";
}
