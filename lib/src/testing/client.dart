library aqueduct.test.client;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aqueduct/aqueduct.dart';
import '../application/application.dart';
import '../application/application_configuration.dart';
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


class TestClientException implements Exception {
  TestClientException(this.message);

  String message;

  @override
  String toString() => "TestClientException: $message";
}
