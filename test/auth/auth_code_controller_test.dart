import 'package:test/test.dart';
import 'dart:io';
import 'package:aqueduct/aqueduct.dart';
import '../helpers.dart';
import 'dart:convert';

void main() {
  Application<TestSink> application;
  ManagedContext ctx = null;
  TestClient client = new TestClient.onPort(8080);


  var codeResponse =
      (Map<String, String> form) {
    var m = new Map<String, String>.from(form);
    m.addAll({"response_type": "code"});

    var req = client.request("/auth/code")..formData = m;

    return req.post();
  };

  setUp(() async {
    application = new Application<TestSink>();
    ctx = await contextWithModels([TestUser, Token, AuthCode]);
    await application.start(runOnMainIsolate: true);

    await createUsers(2);
  });

  tearDown(() async {
    await application?.stop();
    await ctx?.persistentStore?.close();
  });

  /////////
  ///// GET - login form
  /////////

  group("GET success case", () {
    test("GET login form with valid values returns a 'page' with the provided values", () async {
      var req = client.request("/auth/code")
        ..formData = {
          "client_id": "com.stablekernel.redirect",
          "response_type" : "code"
        };

      var res = await req.get();
      expect(res, hasResponse(200, null, headers: {
        "content-type" : "text/html; charset=utf-8"
      }));
      // The data is actually JSON, just makes it easier to validate here.
      var decoded = JSON.decode(res.body);
      expect(decoded, {
        "response_type": "code",
        "client_id" : "com.stablekernel.redirect",
        "state" : null,
        "scope" : null,
        "path" : "/auth/code"
      });
    });

    test("GET login form with valid values returns a 'page' with the provided values + state + scope", () async {
      var req = client.request("/auth/code")
        ..formData = {
          "client_id": "com.stablekernel.redirect",
          "state": "Alaska",
          "response_type": "code",
          "scope" : "readonly viewonly"
        };
      var res = await req.get();
      expect(res, hasStatus(200));
      expect(res, hasHeaders({
        "content-type" : "text/html; charset=utf-8"
      }));
      var decoded = JSON.decode(res.body);
      expect(decoded, {
        "response_type": "code",
        "client_id" : "com.stablekernel.redirect",
        "state" : "Alaska",
        "scope" : "readonly viewonly",
        "path" : "/auth/code"
      });
    });
  });

  group("GET failure cases", () {
    test("No registered rendered returns 405", () async {
      var req = client.request("/nopage")
        ..formData = {
          "client_id" : "com.stablekernel.redirect",
          "response_type" : "code"
        };
      var res = await req.get();
      expect(res, hasStatus(405));
    });
  });

  ///////
  /// POST - authenticate
  ///////
  group("Success cases", () {
    test("With only required values", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "bob+0@stablekernel.com",
        "password": "foobaraxegrind21%"
      });
      expectRedirect(res, new Uri.http("stablekernel.com", "/auth/redirect"));
    });

    test("With required values + state", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "state" : "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": "foobaraxegrind21%"
      });

      expectRedirect(res, new Uri.http("stablekernel.com", "/auth/redirect"), state: "Wisconsin@&");
    });
  });

  group("username Failure Cases", () {
    test("Username does not exist yields 302 with error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "FOOBAR",
        "password": "foobaraxegrind21%"
      });
      expectErrorRedirect(res, new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied");
    });

    test("Username is empty returns 302 with error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "",
        "password": "foobaraxegrind21%"
      });
      expectErrorRedirect(res, new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied");
    });

    test("Username is missing returns 302 with error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "password": "foobaraxegrind21%"
      });
      expectErrorRedirect(res, new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");
    });

    test("Username is repeated returns 302 with error", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongUsername = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.request("/auth/code")
        ..body = "username=$encodedUsername&username=$encodedWrongUsername&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");

      req = client.request("/auth/code")
        ..body = "username=$encodedWrongUsername&username=$encodedUsername&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");
    });
  });

  group("password Failure Cases", () {
    test("password is incorrect yields 302 with error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": "nonsense"
      });
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied");
    });

    test("password is empty returns 302 with error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": ""
      });
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied");
    });

    test("password is missing returns 302 with error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
      });
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");
    });

    test("password is repeated returns 302 with error", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongPassword = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.request("/auth/code")
        ..body = "username=$encodedUsername&password=$encodedWrongPassword&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");

      req = client.request("/auth/code")
        ..body = "username=$encodedUsername&password=$encodedPassword&password=$encodedWrongPassword&response_type=code&client_id=com.stablekernel.redirect"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");
    });
  });

  group("response_type failures", () {
    test("response_type is invalid returns 302 with error", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code")
          ..body = "username=$encodedUsername&password=$encodedPassword&response_type=notcode&client_id=com.stablekernel.redirect"
          ..contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");
    });

    test("response_type is duplicated returns 302 with error", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code");
      req.body = "username=$encodedUsername&password=$encodedPassword&response_type=notcode&response_type=code&client_id=com.stablekernel.redirect";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");

      req = client.request("/auth/code");
      req.body = "username=$encodedUsername&password=$encodedPassword&response_type=code&response_type=notcode&client_id=com.stablekernel.redirect";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");
    });
  });

  group("client_id failures", () {
    test("Omit client_id returns 400", () async {
      var resp = await codeResponse({
        "username": user1["username"],
        "password": user1["password"],
      });
      expect(resp, hasStatus(400));
    });

    test("client_id does not exist for app returns 400", () async {
      var resp = await codeResponse({
        "client_id": "abc",
        "username": user1["username"],
        "password": user1["password"],
      });
      expect(resp, hasStatus(400));
    });

    test("client_id that does not have redirectURI returns 400", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.app1",
        "username": user1["username"],
        "password": user1["password"],
      });
      expect(resp, hasStatus(400));
    });

    test("client_id is duplicated returns 400", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code");
      req.body = "username=$encodedUsername&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect&client_id=foobar";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/code");
      req.body = "username=$encodedUsername&password=$encodedPassword&response_type=code&client_id=foobar&client_id=com.stablekernel.redirect";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });

    test("client_id is empty returns 400", () async {
      var resp = await codeResponse({
        "client_id": "",
        "username": user1["username"],
        "password": user1["password"],
      });
      expect(resp, hasStatus(400));
    });
  });

  group("Invalid requests and state", () {
    test("Failed username + state still returns state in error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "FOOBAR",
        "password": "foobaraxegrind21%",
        "state": "xyz"
      });
      expectErrorRedirect(res, new Uri.http("stablekernel.com", "/auth/redirect"),
          "access_denied", state: "xyz");
    });

    test("Failed password + state still returns state in error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": "nonsense",
        "state": "xyz"
      });
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"),
          "access_denied", state: "xyz");

    });

    test("Failed response_type + state still returns state in error", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code")
        ..body = "username=$encodedUsername&password=$encodedPassword&response_type=notcode&client_id=com.stablekernel.redirect&state=xyz"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expectErrorRedirect(resp, new Uri.http("stablekernel.com", "/auth/redirect"),
          "invalid_request", state: "xyz");
    });
  });

  ///////
  /// Doc gen
  ///////

  test("Response documentation", () {
    AuthCodeController ac = new AuthCodeController(
        new AuthServer(new AuthDelegate(ManagedContext.defaultContext)));
    var resolver = new PackagePathResolver(new File(".packages").path);
    var operations = ac.documentOperations(resolver);

    expect(operations.length, 1);

    List<APIResponse> responses =
        ac.documentResponsesForOperation(operations.first);
    expect(responses.any((ar) => ar.key == "${HttpStatus.MOVED_TEMPORARILY}"),
        true);
    expect(responses.any((ar) => ar.key == "${HttpStatus.BAD_REQUEST}"), true);
    expect(
        responses.any((ar) => ar.key == "${HttpStatus.INTERNAL_SERVER_ERROR}"),
        true);
    expect(responses.any((ar) => ar.key == "${HttpStatus.UNAUTHORIZED}"), true);
  });
}

class TestSink extends RequestSink {
  TestSink(Map<String, dynamic> opts) : super(opts) {
    authServer = new AuthServer<TestUser, Token, AuthCode>(
        new AuthDelegate(ManagedContext.defaultContext));
  }

  AuthServer authServer;

  void setupRouter(Router router) {
    router
        .route("/auth/code")
        .generate(() => new AuthCodeController(authServer, renderAuthorizationPageHTML: (AuthCodeController c, Uri uri, Map<String, String> queryParams) async {
          queryParams.addAll({
            "path" : uri.path
          });
          return JSON.encode(queryParams);
        }));;
    router
        .route("/nopage")
        .generate(() => new AuthCodeController(authServer));

  }
}

expectRedirect(TestResponse resp, Uri requestURI, {String state}) {
  expect(resp, hasStatus(HttpStatus.MOVED_TEMPORARILY));

  var location = resp.headers.value(HttpHeaders.LOCATION);
  var uri = Uri.parse(location);

  expect(uri.queryParameters["code"], hasLength(greaterThan(0)));
  expect(uri.queryParameters["state"], state);
  expect(uri.authority, equals(requestURI.authority));
  expect(uri.path, equals(requestURI.path));
}

expectErrorRedirect(TestResponse resp, Uri requestURI, String errorReason, {String state}) {
  expect(resp, hasStatus(HttpStatus.MOVED_TEMPORARILY));

  var location = resp.headers.value(HttpHeaders.LOCATION);
  var uri = Uri.parse(location);
  expect(uri.authority, requestURI.authority);
  expect(uri.path, requestURI.path);
  expect(uri.queryParameters["error"], errorReason);
  expect(uri.queryParameters["state"], state);
  if (state != null) {
    expect(uri.queryParameters.length, 2);
  } else {
    expect(uri.queryParameters.length, 1);
  }
}

Map<String, String> get user1 => const {
  "username": "bob+0@stablekernel.com",
  "password": "foobaraxegrind21%"
};

Map<String, String> get user2 => const {
  "username": "bob+1@stablekernel.com",
  "password": "foobaraxegrind21%"
};

Map<String, String> get user3 => const {
  "username": "bob+2@stablekernel.com",
  "password": "foobaraxegrind21%"
};