part of aqueduct;

class TestClient {
  String host;
  HttpClient _client = new HttpClient();
  http.Client _innerClient = new http.Client();
  String clientID;
  String clientSecret;
  String defaultAccessToken;
  Map<String, String> defaultHeaders = {};

  TestClient(int port) {
    host = "http://localhost:$port";
  }

  TestClient.fromConfig(ApplicationInstanceConfiguration config) {
    var hostname = config.address;
    hostname ??= "localhost";

    host = "${config.securityContext != null ? "https" : "http"}://$hostname:${config.port}";
  }

  TestRequest request(String path) {
    TestRequest r = new TestRequest()
      ..host = this.host
      ..path = path
      .._client = _client
      ..headers = new Map.from(defaultHeaders);

    return r;
  }

  TestRequest clientAuthenticatedRequest(String path, {String clientID: null, String clientSecret: null}) {
    clientID ??= this.clientID;
    clientSecret ??= this.clientSecret;

    var req = request(path)
      ..basicAuthorization = "$clientID:$clientSecret";

    return req;
  }

  TestRequest authenticatedRequest(String path, {String accessToken: null}) {
    accessToken ??= defaultAccessToken;

    var req = request(path)
      ..bearerAuthorization = accessToken;
    return req;
  }

  Future close() async {
    await _client.close(force: true);
  }
}

class TestRequest {
  HttpClient _client;
  String host;
  String path;
  ContentType contentType = ContentType.JSON;
  List<int> _bodyBytes;

  Map<String, String> queryParameters = {};

  Map<String, String> get headers => _headers;
  void set headers(Map<String, String> h) {
    if (!_headers.isEmpty) {
      print("WARNING: Setting TestRequest headers, but headers already have values.");
    }
    _headers = h;
  }
  Map<String, String> _headers = {};

  String get requestURL {
    String url = null;
    if (path.startsWith("/")) {
      url = "$host$path";
    } else {
      url = [host, path].join("/");
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

  void set basicAuthorization(String str) {
    addHeader(HttpHeaders.AUTHORIZATION, "Basic ${new Base64Encoder().convert(str.codeUnits)}");
  }

  void set bearerAuthorization(String str) {
    addHeader(HttpHeaders.AUTHORIZATION, "Bearer $str");
  }

  void set accept(String str) {
    addHeader(HttpHeaders.ACCEPT, str);
  }

  void set json(dynamic v) {
    _bodyBytes = UTF8.encode(JSON.encode(v));
    contentType = ContentType.JSON;
  }

  void set formData(Map<String, dynamic> args) {
    _bodyBytes = UTF8.encode(args.keys.map((key) => "$key=${Uri.encodeQueryComponent(args[key])}").join("&"));
    contentType = new ContentType("application", "x-www-form-urlencoded", charset: "utf-8");
  }

  void addHeader(String name, String value) {
    headers[name] = value;
  }

  Future<TestResponse> post() {
    return _executeRequest("POST");
  }

  Future<TestResponse> put() {
    return _executeRequest("PUT");
  }

  Future<TestResponse> get() {
    return _executeRequest("GET");
  }

  Future<TestResponse> delete() {
    return _executeRequest("DELETE");
  }

  Future<TestResponse> _executeRequest(String method) async {
    var request = await _client.openUrl(method, Uri.parse(requestURL));
    headers?.forEach((headerKey, headerValue) {
      request.headers.add(headerKey, headerValue);
    });

    if (_bodyBytes != null) {
      request.headers.contentType = contentType;
      request.headers.contentLength = _bodyBytes.length;
      request.add(_bodyBytes);
    }

    var response = new TestResponse(await request.close());
    await response._bodyDecodeCompleter;

    return response;
  }
}

class TestResponse {
  TestResponse(this._innerResponse) {
    if (_innerResponse.contentLength > 0) {
      _bodyDecodeCompleter = new Completer();
      _innerResponse.transform(UTF8.decoder).listen((contents) {
        body = contents;
        _decodeBody();
        _bodyDecodeCompleter.complete();
      });
    }
  }

  final HttpClientResponse _innerResponse;
  Completer _bodyDecodeCompleter;
  dynamic decodedBody;
  String body;
  HttpHeaders get headers => _innerResponse.headers;
  int get contentLength => _innerResponse.contentLength;
  int get statusCode => _innerResponse.statusCode;
  bool get isRedirect => _innerResponse.isRedirect;
  bool get persistentConnection => _innerResponse.persistentConnection;

  List<dynamic> get asList => decodedBody as List;
  Map<dynamic, dynamic> get asMap => decodedBody as Map;

  void _decodeBody() {
    var contentType = this._innerResponse.headers.contentType;
    if (contentType.primaryType == "application" && contentType.subType == "json") {
      decodedBody = JSON.decode(body);
    } else if (contentType.primaryType == "application" && contentType.subType == "x-www-form-urlencoded") {
      var split = body.split("&");
      var map = {};
      split.forEach((str) {
        var innerSplit = str.split("=");
        if (innerSplit.length == 2) {
          map[innerSplit[0]] = innerSplit[1];
        } else {
          map[innerSplit[0]] = true;
        }
      });
      decodedBody = map;
    } else {
      decodedBody = body;
    }
  }

  String toString() {
    var headerItems = headers.toString().split("\n");
    headerItems.removeWhere((str) => str == "");
    var headerString = headerItems.join("\n\t\t\t ");
    return "\n\tStatus Code: $statusCode\n\tHeaders: ${headerString}\n\tBody: $body";
  }
}