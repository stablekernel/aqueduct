part of aqueduct;

class TestClient {
  String host;
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
      .._innerClient = _innerClient
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
}

class TestRequest {
  http.Client _innerClient;
  String host;
  String path;
  String body;
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

  void set contentType(String str) {
    addHeader(HttpHeaders.CONTENT_TYPE, str);
  }

  void set accept(String str) {
    addHeader(HttpHeaders.ACCEPT, str);
  }

  void set json(dynamic v) {
    body = JSON.encode(v);
    contentType = "application/json";
  }

  void set formData(Map<String, dynamic> args) {
    body = args.keys.map((key) => "$key=${Uri.encodeQueryComponent(args[key])}").join("&");
    contentType = "application/x-www-form-urlencoded";
  }

  void addHeader(String name, String value) {
    headers[name] = value;
  }

  Future<TestResponse> post() {
    return _wrap(_innerClient.post(requestURL, headers: headers, body: body));
  }

  Future<TestResponse> put() {
    return _wrap(_innerClient.put(requestURL, headers: headers, body: body));
  }

  Future<TestResponse> get() {
    return _wrap(_innerClient.get(requestURL, headers: headers));
  }

  Future<TestResponse> delete() {
    return _wrap(_innerClient.delete(requestURL, headers: headers));
  }

  Future<TestResponse> _wrap(Future<http.Response> req) async {
    return new TestResponse(await req);
  }
}

class TestResponse {
  TestResponse(this._innerResponse) {
    body = _innerResponse.body;

    if (contentLength > 0) {
      var contentType = this._innerResponse.headers["content-type"];
      if (contentType == ContentType.JSON) {
        _decodedBody = JSON.decode(body);
      } else if (contentType == "application/x-www-form-urlencoded") {
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
        _decodedBody = map;
      }
    }
  }

  dynamic _decodedBody;
  String body;
  Map<String, String> get headers => _innerResponse.headers;
  int get contentLength => _innerResponse.contentLength;
  int get statusCode => _innerResponse.statusCode;
  final http.Response _innerResponse;
  bool get isRedirect => _innerResponse.isRedirect;
  bool get persistentConnection => _innerResponse.persistentConnection;

  List<dynamic> asList() {
    return _decodedBody;
  }

  Map<dynamic, dynamic> asMap() {
    return _decodedBody;
  }

  String asString() {
    return _decodedBody;
  }
}

HTTPResponseMatcher hasStatus(int v) => new HTTPResponseMatcher(v, [], null);
HTTPResponseMatcher hasResponse(int statusCode, List<HTTPHeaderMatcher> headers, HTTPBodyMatcher body) => new HTTPResponseMatcher(statusCode, headers, body);

class HTTPResponseMatcher extends Matcher {
  HTTPResponseMatcher(this.statusCode, this.headers, this.body);

  int statusCode = null;
  List<HTTPHeaderMatcher> headers = [];
  HTTPBodyMatcher body = null;

  bool matches(item, Map matchState) {
    if (item is! http.Response) {
      matchState["Response Type Is Actually"] = "${item.runtimeType}";
      return false;
    }

    if (item.body != null) {
      matchState["Response Body"] = item.body;
    }

    var tr = item as http.Response;
    if (tr.statusCode != statusCode) {
      matchState["Status Code Is Actually"] = "${tr.statusCode}";
      return false;
    }


    if (body != null) {
      body.contentType = ContentType.parse(tr.headers["content-type"]);
      if (!body.matches(tr.body, matchState)) {
        return false;
      }
    }

    return true;
  }

  Description describe(Description description) {
    if (statusCode != null) {
      description.add("Status Code: $statusCode");
    }

    headers.forEach((h) => h.describe(description));
    if (body != null) {
      body.describe(description);
    }

    return description;
  }

  Description describeMismatch(item, Description mismatchDescription, Map matchState, bool verbose) {
    mismatchDescription.add(matchState.keys.map((key) {
      return "${key}: ${matchState[key]}";
    }).join(", "));
    return mismatchDescription;
  }
}

HTTPBodyMatcher matchesJSONExactly(dynamic jsonMatchSpec) => new HTTPBodyMatcher()
  ..requiresExactMatch = true
  ..contentMatcher = jsonMatchSpec
  ..expectedContentType = ContentType.JSON;

HTTPBodyMatcher matchesJSON(dynamic jsonMatchSpec) => new HTTPBodyMatcher()
  ..requiresExactMatch = false
  ..contentMatcher = jsonMatchSpec
  ..expectedContentType = ContentType.JSON;

HTTPBodyMatcher matchesForm(dynamic jsonMatchSpec) => new HTTPBodyMatcher()
  ..contentMatcher = jsonMatchSpec
  ..expectedContentType = new ContentType("application", "x-www-form-urlencoded");


class HTTPBodyMatcher extends Matcher {
  dynamic contentMatcher;
  ContentType expectedContentType;
  ContentType contentType;
  bool requiresExactMatch = false;

  bool matches(dynamic incomingItem, Map matchState) {
    if (contentType != null && expectedContentType != null
    && (contentType.primaryType != expectedContentType.primaryType || contentType.subType != expectedContentType.subType)) {
      matchState["Content Type Is Actually"] = "${contentType}";
      return false;
    }

    var decodedData = incomingItem;
    if (contentType.primaryType == "application" && contentType.subType == "json") {
      decodedData = JSON.decode(decodedData);
    } else if (contentType.primaryType == "application" && contentType.subType == "x-www-form-urlencoded") {
      var split = (decodedData as String).split("&");
      var map = {};
      split.forEach((str) {
        var innerSplit = str.split("=");
        if (innerSplit.length == 2) {
          map[innerSplit[0]] = innerSplit[1];
        } else {
          map[innerSplit[0]] = true;
        }
      });
      decodedData = map;
    }

    if (contentMatcher is List && decodedData is List) {
      var dataIterator = decodedData.iterator;
      if (requiresExactMatch) {
        for (var matcher in contentMatcher) {
          dataIterator.moveNext();
          var element = dataIterator.current;
          if (matcher is Matcher) {
            if (!matcher.matches(element, matchState)) {
              return false;
            }
          } else {
            if (!mapMatches(element, matcher, matchState)) {
              return false;
            }
          }
        }
      } else {
        var matcher = contentMatcher.first;
        for (var element in decodedData) {
          if (matcher is Matcher) {
            if (!matcher.matches(element, matchState)) {
              return false;
            } else {
              if (!mapMatches(element, matcher, matchState)) {
                return false;
              }
            }
          }
        }
      }
      return true;
    } else if (contentMatcher is Map && decodedData is Map) {
      return mapMatches(decodedData, contentMatcher, matchState);
    } else if (contentMatcher is Matcher) {
      return contentMatcher.matches(decodedData, matchState);
    }

    return false;
  }

  bool mapMatches(Map<String, dynamic> item, Map<String, Matcher> keyMatches, Map matchState) {
    return !keyMatches.keys.map((str) {
      var matcher = keyMatches[str];
      var value = item[str];

      var matches = false;
      if (matcher is Matcher) {
        matches = matcher.matches(value, matchState);
      } else {
        matches = value == matcher;
      }

      if (!matches) {
        matchState["Value for $str Actually Is"] = value;
      }

      return matches;
    }).any((b) => b == false);
  }

  Description describe(Description description) {
    return description;
  }
}

class HTTPHeaderMatcher extends Matcher {
  bool matches(item, Map matchState) {
    return false;
  }

  Description describe(Description description) {
    return description;
  }
}