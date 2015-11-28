part of monadart;

/*
      var response = client.json("/users")
        ..auth = ClientAuth(client.baseClientID, client.baseClientSecret)
        ..body = {"username" : "bob"}
        .post();
      expect(response.statusCode, 200);
      expect(response.jsonObject.hasKeys(["id", "name", "email"]), true);
     */

class TestClient {
  String host;

  String defaultClientID;
  String defaultClientSecret;

  Map<String, dynamic> token;

  JSONTestRequest jsonRequest(String path) {
    JSONTestRequest r = new JSONTestRequest()
      ..host = this.host
      ..path = path
      ..contentType = "application/json;charset=utf-8"
      ..accept = "application/json";
    return r;
  }

  TestRequest request(String path) {
    TestRequest r = new TestRequest()
      ..host = this.host
      ..path = path;
    return r;
  }

  TestRequest clientAuthenticatedRequest(String path, {String clientID: null, String clientSecret: null}) {
    clientID ??= defaultClientID;
    clientSecret ??= defaultClientSecret;

    var req = request(path)..basicAuthorization = "$clientID:$clientSecret";
    return req;
  }

  TestRequest authenticatedRequest(String path, {String accessToken: null}) {
    accessToken ??= token["access_token"];

    var req = request(path)..bearerAuthorization = accessToken;
    return req;
  }

  JSONTestRequest clientAuthenticatedJSONRequest(String path, {String clientID: null, String clientSecret: null}) {
    clientID ??= defaultClientID;
    clientSecret ??= defaultClientSecret;

    var req = jsonRequest(path)..basicAuthorization = "$clientID:$clientSecret";
    return req;
  }

  JSONTestRequest authenticatedJSONRequest(String path, {String accessToken: null}) {
    accessToken ??= token["access_token"];

    var req = jsonRequest(path)..bearerAuthorization = accessToken;
    return req;
  }
}

class TestRequest<ResponseType extends TestResponse> {
  String host;
  void set basicAuthorization(String str) {
    addHeader(HttpHeaders.AUTHORIZATION, "Basic ${CryptoUtils.bytesToBase64(str.codeUnits)}");
  }

  void set bearerAuthorization(String str) {
    addHeader(HttpHeaders.AUTHORIZATION, "Bearer $str");
  }

  void set contentType(String str) {
    addHeader(HttpHeaders.CONTENT_TYPE, str);
  }

  void set accept(String str) {
    addHeader(HttpHeaders.ACCEPT, str);
  }

  String path;
  String body;
  Map<String, String> headers = {};

  void addHeader(String name, String value) {
    headers[name] = value;
  }

  Future<ResponseType> post() {
    return wrapResponse(http.post("$host$path", headers: headers, body: body));
  }

  Future<ResponseType> put() {
    return wrapResponse(http.put("$host$path", headers: headers, body: body));
  }

  Future<ResponseType> get() {
    return wrapResponse(http.get("$host$path", headers: headers));
  }

  Future<ResponseType> delete() {
    return wrapResponse(http.delete("$host$path", headers: headers));
  }

  Future<ResponseType> wrapResponse(Future<http.Response> response) async {
    var res = await response;
    return new TestResponse(res.statusCode, res.headers, res.body);
  }
}

class JSONTestRequest extends TestRequest<JSONTestResponse> {
  void set json(dynamic map) {
    if (map != null) {
      body = JSON.encode(map);
    }
  }

  @override
  Future<JSONTestResponse> wrapResponse(Future<http.Response> response) async {
    var res = await response;
    return new JSONTestResponse(res.statusCode, res.headers, res.body);
  }
}

class TestResponse {
  final int statusCode;
  final dynamic body;
  final Map<String, String> headers;

  TestResponse(this.statusCode, this.headers, this.body);

  String toString() {
    return "$statusCode - $headers - $body";
  }
}

class JSONTestResponse extends TestResponse {
  dynamic json;

  JSONTestResponse(int statusCode, Map<String, String> headers, dynamic responseBody) : super(statusCode, headers, responseBody) {
    if (responseBody != null && (responseBody as String).length > 0) {
      json = JSON.decode(responseBody);
    }
  }

  String toString() {
    return "${super.toString()} $json";
  }

  bool hasKeys(List<String> keys) {
    var map = json as Map<String, dynamic>;
    for (var k in keys) {
      if (map[k] == null) {
        print("Expected $k in $map");
        return false;
      }
    }
    return true;
  }

  bool hasOnlyKeys(List<String> keys) {
    var map = json as Map<String, dynamic>;
    if (map.keys.length != keys.length) {
      return false;
    }

    return hasKeys(keys);
  }

  bool hasValues(Map<String, dynamic> values) {
    var map = json as Map<String, dynamic>;
    var success = true;
    values.forEach((k, v) {
      if (map[k] != v) {
        success = false;
        print("Expected $k : $v in $json");
      }
    });
    return success;
  }

  bool hasOnlyValues(Map<String, dynamic> values) {
    var map = json as Map<String, dynamic>;
    if (map.keys.length != values.keys.length) {
      return false;
    }

    return hasValues(values);
  }
}
