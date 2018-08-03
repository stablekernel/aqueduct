library aqueduct_test.client;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';

import 'harness.dart';
import 'matchers.dart';

part 'request.dart';
part 'response.dart';

/// Executes HTTP requests during application testing.
///
/// Agents create and execute test requests. For most cases, methods like [get], [post], [put] and [delete]
/// are used to execute these requests. For more granular control, [request] creates a request object
/// that can be configured in more detail.
///
/// Each [Agent] has a set of default values, such as headers, that it uses for each of its requests.
/// When many test requests have common headers, it is preferable to create an [Agent] for the similar
/// requests. For example, after authenticating a user during tests, an [Agent] can add
/// the 'Authorization' header for that user to each of its requests.
///
/// The default constructor takes an [Application] and configures itself from that application's options.
/// The application is typically provided by [TestHarness]. [TestHarness] contains a default agent. Example usage:
///
///         void main() {
///           final harness = TestHarness<MyChannel>()..install();
///
///           test("GET /thing returns 200", () async {
///             final resp = await harness.agent.get("/thing");
///             expect(resp, hasStatus(200));
///           });
///         }
class Agent {
  /// Configures a new agent that sends requests to [app].
  Agent(Application app)
      : _application = app,
        _host = null,
        _port = null,
        _scheme = null;

  /// Configures a new agent that sends requests to 'http://localhost:[_port]'.
  Agent.onPort(this._port)
      : _scheme = "http",
        _host = "localhost",
        _application = null;

  /// Configures a new agent that sends requests to a server configured by [config].
  Agent.fromOptions(ApplicationOptions config, {bool useHTTPS = false})
      : _scheme = useHTTPS ? "https" : "http",
        _host = "localhost",
        _port = config.port,
        _application = null;

  /// Configures a new agent with the same properties as [original].
  Agent.from(Agent original)
      : _scheme = original._scheme,
        _host = original._host,
        _port = original._port,
        contentType = original.contentType,
        _application = original._application {
    headers.addAll(original?.headers ?? {});
  }

  final String _scheme;
  final String _host;
  final int _port;
  final Application _application;
  final HttpClient _client = HttpClient();

  /// Default headers to be added to requests made by this agent.
  ///
  /// By default, this value is the empty map.
  ///
  /// Do not provide a 'content-type' key. If the key 'content-type' is present,
  /// it will be removed prior to sending the request. It is replaced by the value
  /// of [TestRequest.contentType], which also controls body encoding.
  ///
  /// See also [setBasicAuthorization], [bearerAuthorization], [accept],
  /// [contentType] for setting common headers.
  final Map<String, dynamic> headers = {};

  /// Sets the default content-type of requests made by this agent.
  ///
  /// Defaults to 'application/json; charset=utf-8'. A request created
  /// by this agent will have its [TestRequest.contentType] set
  /// to this value.
  ContentType contentType = ContentType.json;

  /// The base URL that this agent's requests will be made against.
  String get baseURL {
    if (_application != null) {
      if (!_application.isRunning) {
        throw StateError("Application under test is not running.");
      }
      return "${_application.server.requiresHTTPS ? "https" : "http"}://localhost:${_application.channel.server.server.port}";
    }

    return "$_scheme://$_host:$_port";
  }

  /// Adds basic authorization to requests from this agent.
  ///
  /// Base-64 encodes username and password with a colon separator, and sets it
  /// for the key 'authorization' in [headers].
  void setBasicAuthorization(String username, String password) {
    headers["authorization"] =
        "Basic ${base64.encode("$username:${password ?? ""}".codeUnits)}";
  }

  /// Adds bearer authorization to requests from this agent.
  ///
  /// Prefixes [token] with 'Bearer ' and sets it for the key 'authorization' in [headers].
  set bearerAuthorization(String token) {
    headers[HttpHeaders.authorizationHeader] = "Bearer $token";
  }

  /// Adds Accept header to requests from this agent.
  set accept(List<ContentType> contentTypes) {
    headers[HttpHeaders.acceptHeader] =
        contentTypes.map((ct) => ct.toString()).join(",");
  }

  /// Creates a request object for [path] that can be configured and executed later.
  ///
  /// Use this method to create a configurable [TestRequest] object. Default values of this agent, such as [headers] and [contentType], are set on the returned request.
  /// You may override default values in the returned request without impacting other requests.
  ///
  /// The [path] will be appended to [baseURL]. Leading and trailing slashes are ignored.
  TestRequest request(String path) {
    final r = TestRequest._(_client)
      ..baseURL = baseURL
      ..path = path
      .._client = _client
      ..contentType = contentType;

    r.headers.addAll(headers);

    return r;
  }

  /// Closes this instances underlying HTTP client.
  void close() {
    _client.close(force: true);
  }

  /// Makes a GET request with this agent.
  ///
  /// Calls [execute] with "GET" method.
  Future<TestResponse> get(String path,
      {Map<String, dynamic> headers, Map<String, dynamic> query}) {
    return execute("GET", path, headers: headers, query: query);
  }

  /// Makes a POST request with this agent.
  ///
  /// Calls [execute] with "POST" method.
  Future<TestResponse> post(String path,
      {dynamic body,
      Map<String, dynamic> headers,
      Map<String, dynamic> query}) {
    return execute("POST", path, body: body, headers: headers, query: query);
  }

  /// Makes a DELETE request with this agent.
  ///
  /// Calls [execute] with "DELETE" method.
  Future<TestResponse> delete(String path,
      {dynamic body,
      Map<String, dynamic> headers,
      Map<String, dynamic> query}) {
    return execute("DELETE", path, body: body, headers: headers, query: query);
  }

  /// Makes a PUT request with this agent.
  ///
  /// Calls [execute] with "PUT" method.
  Future<TestResponse> put(String path,
      {dynamic body,
      Map<String, dynamic> headers,
      Map<String, dynamic> query}) {
    return execute("PUT", path, body: body, headers: headers, query: query);
  }

  /// Executes an HTTP request with this agent.
  ///
  /// The [method] is request method (e.g., GET, POST) and is case-insensitive. Prefer to use methods like [get] or [post].
  ///
  /// [path] is the path fo the resource on the server being tested. It is appended to [baseURL]. If there is no leading slash
  /// in the path, one is added to separate the base URL from the path.
  ///
  /// [body] is encoded according to [contentType] prior to the request being sent (the default encodes [body] as JSON). If [body] is null, none is sent.
  ///
  /// The headers of the request are formed by combining [headers] and the [Agent.headers]. If [headers] is null, the request's headers
  /// are only those in [Agent.headers].
  ///
  /// If [query] is non-null, each value is URI-encoded and then the map is encoding as the request URI's  query string.
  Future<TestResponse> execute(String method, String path,
      {dynamic body,
      Map<String, dynamic> headers,
      Map<String, dynamic> query}) {
    final req = request(path)
      ..body = body
      ..query = query;

    if (headers != null) {
      req.headers.addAll(headers);
    }

    return req.method(method);
  }
}
