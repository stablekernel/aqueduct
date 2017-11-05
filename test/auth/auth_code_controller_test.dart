import 'dart:io';
import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/test.dart';

import '../helpers.dart';
import 'dart:convert';

void main() {
  Application<TestChannel> application;
  TestClient client = new TestClient.onPort(8081);

  var codeResponse = (Map<String, String> form) {
    var m = new Map<String, String>.from(form);
    m.addAll({"response_type": "code"});

    var req = client.request("/auth/code")..formData = m;

    return req.post();
  };

  setUp(() async {
    application = new Application<TestChannel>();

    await application.test();
  });

  tearDown(() async {
    await application?.stop();
  });

  /////////
  ///// GET - login form
  /////////

  group("GET success case", () {
    test(
        "GET login form with valid values returns a 'page' with the provided values",
        () async {
      var req = client.request("/auth/code")
        ..formData = {
          "client_id": "com.stablekernel.redirect",
          "response_type": "code"
        };

      var res = await req.get();
      expect(
          res,
          hasResponse(200, null,
              headers: {"content-type": "text/html; charset=utf-8"}));
      // The data is actually JSON, just makes it easier to validate here.
      var decoded = JSON.decode(res.body);
      expect(decoded, {
        "response_type": "code",
        "client_id": "com.stablekernel.redirect",
        "state": null,
        "scope": null,
        "path": "/auth/code"
      });
    });

    test(
        "GET login form with valid values returns a 'page' with the provided values + state + scope",
        () async {
      var req = client.request("/auth/code")
        ..formData = {
          "client_id": "com.stablekernel.redirect",
          "state": "Alaska",
          "response_type": "code",
          "scope": "readonly viewonly"
        };
      var res = await req.get();
      expect(res, hasStatus(200));
      expect(res, hasHeaders({"content-type": "text/html; charset=utf-8"}));
      var decoded = JSON.decode(res.body);
      expect(decoded, {
        "response_type": "code",
        "client_id": "com.stablekernel.redirect",
        "state": "Alaska",
        "scope": "readonly viewonly",
        "path": "/auth/code"
      });
    });
  });

  group("GET failure cases", () {
    test("No registered rendered returns 405", () async {
      var req = client.request("/nopage")
        ..formData = {
          "client_id": "com.stablekernel.redirect",
          "response_type": "code"
        };
      var res = await req.get();
      expect(res, hasStatus(405));
    });
  });

  ///////
  /// POST - authenticate
  ///////
  group("Success cases", () {
    test("With required values", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.DefaultPassword
      });

      expectRedirect(res, new Uri.http("stablekernel.com", "/auth/redirect"),
          state: "Wisconsin@&");
    });

    test("With scope", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.DefaultPassword,
        "scope": "user"
      });

      expectRedirect(res, new Uri.http("stablekernel.com", "/auth/scoped"),
          state: "Wisconsin@&");

      var redirectURI = Uri.parse(res.headers["location"].first);
      var codeParam = redirectURI.queryParameters["code"];
      var token = await application.channel.authServer.exchange(codeParam, "com.stablekernel.scoped", "kilimanjaro");
      expect(token.scopes.length, 1);
      expect(token.scopes.first.isExactly("user"), true);
    });

    test("With multiple scopes", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.DefaultPassword,
        "scope": "user other_scope"
      });

      expectRedirect(res, new Uri.http("stablekernel.com", "/auth/scoped"),
          state: "Wisconsin@&");

      var redirectURI = Uri.parse(res.headers["location"].first);
      var codeParam = redirectURI.queryParameters["code"];
      var token = await application.channel.authServer.exchange(codeParam, "com.stablekernel.scoped", "kilimanjaro");
      expect(token.scopes.length, 2);
      expect(token.scopes.any((s) => s.isExactly("user")), true);
      expect(token.scopes.any((s) => s.isExactly("other_scope")), true);
    });
  });

  group("username Failure Cases", () {
    test("Username does not exist yields 302 with error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "FOOBAR",
        "password": InMemoryAuthStorage.DefaultPassword,
        "state": "a"
      });
      expectErrorRedirect(res,
          new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("Username is empty returns 302 with error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "",
        "password": InMemoryAuthStorage.DefaultPassword,
        "state": "a"
      });
      expectErrorRedirect(res,
          new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("Username is missing returns 302 with error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "password": InMemoryAuthStorage.DefaultPassword,
        "state": "a"
      });
      expectErrorRedirect(res,
          new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request",
          state: "a");
    });

    test("Username is repeated returns 400", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongUsername = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.request("/auth/code")
        ..body =
            "username=$encodedUsername&username=$encodedWrongUsername&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect&state=a"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/code")
        ..body =
            "username=$encodedWrongUsername&username=$encodedUsername&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect&state=a"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });
  });

  group("password Failure Cases", () {
    test("password is incorrect yields 302 with error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": "nonsense",
        "state": "a"
      });
      expectErrorRedirect(resp,
          new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("password is empty returns 302 with error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": "",
        "state": "a"
      });
      expectErrorRedirect(resp,
          new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("password is missing returns 302 with error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "state": "a"
      });
      expectErrorRedirect(resp,
          new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request",
          state: "a");
    });

    test("password is repeated returns 302 with error", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.

      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongPassword = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.request("/auth/code")
        ..body =
            "username=$encodedUsername&password=$encodedWrongPassword&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect&state=a"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/code")
        ..body =
            "username=$encodedUsername&password=$encodedPassword&password=$encodedWrongPassword&response_type=code&client_id=com.stablekernel.redirect&state=a"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });
  });

  group("response_type failures", () {
    test("response_type is invalid returns 302 with error", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code")
        ..body =
            "username=$encodedUsername&password=$encodedPassword&response_type=notcode&client_id=com.stablekernel.redirect&state=a"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expectErrorRedirect(resp,
          new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request",
          state: "a");
    });

    test("response_type is duplicated returns 302 with error", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code");
      req.body =
          "username=$encodedUsername&password=$encodedPassword&response_type=notcode&response_type=code&client_id=com.stablekernel.redirect&state=a";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/code");
      req.body =
          "username=$encodedUsername&password=$encodedPassword&response_type=code&response_type=notcode&client_id=com.stablekernel.redirect&state=a";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });
  });

  group("client_id failures", () {
    test("Omit client_id returns 400", () async {
      var resp = await codeResponse({
        "username": user1["username"],
        "password": user1["password"],
        "state": "a"
      });
      expect(resp, hasStatus(400));
    });

    test("client_id does not exist for app returns 400", () async {
      var resp = await codeResponse({
        "client_id": "abc",
        "username": user1["username"],
        "password": user1["password"],
        "state": "a"
      });
      expect(resp, hasStatus(400));
    });

    test("client_id that does not have redirectURI returns 400", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.app1",
        "username": user1["username"],
        "password": user1["password"],
        "state": "a"
      });
      expect(resp, hasStatus(400));
    });

    test("client_id is duplicated returns 400", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code");
      req.body =
          "username=$encodedUsername&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect&client_id=foobar&state=a";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/code");
      req.body =
          "username=$encodedUsername&password=$encodedPassword&response_type=code&client_id=foobar&client_id=com.stablekernel.redirect&state=a";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });

    test("client_id is empty returns 400", () async {
      var resp = await codeResponse({
        "client_id": "",
        "username": user1["username"],
        "password": user1["password"],
        "state": "a"
      });
      expect(resp, hasStatus(400));
    });
  });

  group("Invalid requests and state", () {
    test("Omit state is error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": InMemoryAuthStorage.DefaultPassword
      });

      expect(resp, hasStatus(HttpStatus.MOVED_TEMPORARILY));

      var location = resp.headers.value(HttpHeaders.LOCATION);
      var uri = Uri.parse(location);
      var requestURI = new Uri.http("stablekernel.com", "/auth/redirect");
      expect(uri.queryParameters["error"], "invalid_request");
      expect(uri.queryParameters["state"], isNull);
      expect(uri.authority, equals(requestURI.authority));
      expect(uri.path, equals(requestURI.path));
      expect(uri.queryParametersAll["error"].length, 1);
    });

    test("Failed username + state still returns state in error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "FOOBAR",
        "password": InMemoryAuthStorage.DefaultPassword,
        "state": "xyz"
      });
      expectErrorRedirect(res,
          new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "xyz");
    });

    test("Failed password + state still returns state in error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": "nonsense",
        "state": "xyz"
      });
      expectErrorRedirect(resp,
          new Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "xyz");
    });

    test("Failed response_type + state still returns state in error", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code")
        ..body =
            "username=$encodedUsername&password=$encodedPassword&response_type=notcode&client_id=com.stablekernel.redirect&state=xyz"
        ..contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expectErrorRedirect(resp,
          new Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request",
          state: "xyz");
    });
  });

  group("Scope failure cases", () {
    test("Malformed scope", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.DefaultPassword,
        "scope": "u\"ser"
      });

      expectErrorRedirect(res, new Uri.http("stablekernel.com", "/auth/scoped"), "invalid_scope", state: "Wisconsin@&");
    });

    test("Scope that client can't grant", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.DefaultPassword,
        "scope": "invalid"
      });

      expectErrorRedirect(res, new Uri.http("stablekernel.com", "/auth/scoped"), "invalid_scope", state: "Wisconsin@&");
    });
  });

  ///////
  /// Doc gen
  ///////

  test("Response documentation", () {
    AuthCodeController ac =
        new AuthCodeController(new AuthServer(new InMemoryAuthStorage()));
    var resolver = new PackagePathResolver(new File(".packages").path);
    var operations = ac.documentOperations(resolver);

    expect(operations.length, 2);

    var getOp = operations.firstWhere((op) => op.method.toLowerCase() == "get");
    var scopeGet = getOp.parameters.firstWhere((p) => p.name == "scope");
    var clientIDGet = getOp.parameters.firstWhere((p) => p.name == "client_id");
    var stateGet = getOp.parameters.firstWhere((p) => p.name == "state");
    var responseTypeGet =
        getOp.parameters.firstWhere((p) => p.name == "response_type");
    expect(
        getOp.parameters
            .every((p) => p.parameterLocation == APIParameterLocation.query),
        true);
    expect(
        getOp.parameters.every((p) => p.schemaObject.type == "string"), true);
    expect(
        [clientIDGet, responseTypeGet, stateGet]
            .every((p) => p.required == true),
        true);
    expect([scopeGet].every((p) => p.required == false), true);
    expect(getOp.produces.length, 1);
    expect(getOp.produces.first, ContentType.HTML);
    expect(getOp.security, []);

    var postOperation =
        operations.firstWhere((op) => op.method.toLowerCase() == "post");
    var scopePost =
        postOperation.parameters.firstWhere((p) => p.name == "scope");
    var clientIDPost =
        postOperation.parameters.firstWhere((p) => p.name == "client_id");
    var statePost =
        postOperation.parameters.firstWhere((p) => p.name == "state");
    var responseTypePost =
        postOperation.parameters.firstWhere((p) => p.name == "response_type");
    var usernamePost =
        postOperation.parameters.firstWhere((p) => p.name == "username");
    var passwordPost =
        postOperation.parameters.firstWhere((p) => p.name == "password");
    expect(
        postOperation.parameters
            .every((p) => p.parameterLocation == APIParameterLocation.formData),
        true);
    expect(
        postOperation.parameters.every((p) => p.schemaObject.type == "string"),
        true);
    expect(
        [clientIDPost, responseTypePost, usernamePost, passwordPost, statePost]
            .every((p) => p.required == true),
        true);
    expect([scopePost].every((p) => p.required == false), true);
    expect(postOperation.security, []);

    expect(
        postOperation.responses
            .any((ar) => ar.key == "${HttpStatus.MOVED_TEMPORARILY}"),
        true);
    expect(
        postOperation.responses
            .any((ar) => ar.key == "${HttpStatus.BAD_REQUEST}"),
        true);
    expect(
        postOperation.responses
            .any((ar) => ar.key == "${HttpStatus.INTERNAL_SERVER_ERROR}"),
        true);
  });
}

class TestChannel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Future prepare() async {
    var storage = new InMemoryAuthStorage();
    storage.createUsers(2);
    authServer = new AuthServer(storage);
  }

  @override
  RequestController get entryPoint {
    final router = new Router();
    router.route("/auth/code").generate(() => new AuthCodeController(authServer,
            renderAuthorizationPageHTML: (AuthCodeController c, Uri uri,
                Map<String, String> queryParams) async {
          queryParams.addAll({"path": uri.path});
          return JSON.encode(queryParams);
        }));

    router.route("/nopage").generate(() => new AuthCodeController(authServer));
    return router;
  }
}

void expectRedirect(TestResponse resp, Uri requestURI, {String state}) {
  expect(resp, hasStatus(HttpStatus.MOVED_TEMPORARILY));

  var location = resp.headers.value(HttpHeaders.LOCATION);
  var uri = Uri.parse(location);

  expect(uri.queryParameters["code"], hasLength(greaterThan(0)));
  expect(uri.queryParameters["state"], state);
  expect(uri.authority, equals(requestURI.authority));
  expect(uri.path, equals(requestURI.path));

  expect(uri.queryParametersAll["state"].length, 1);
  expect(uri.queryParametersAll["code"].length, 1);
}

void expectErrorRedirect(TestResponse resp, Uri requestURI, String errorReason,
    {String state}) {
  expect(resp, hasStatus(HttpStatus.MOVED_TEMPORARILY));

  var location = resp.headers.value(HttpHeaders.LOCATION);
  var uri = Uri.parse(location);
  expect(uri.authority, requestURI.authority);
  expect(uri.path, requestURI.path);
  expect(uri.queryParameters["error"], errorReason);
  expect(uri.queryParameters["state"], state);
  expect(uri.queryParametersAll["state"].length, 1);
  expect(uri.queryParametersAll["error"].length, 1);
}

Map<String, String> get user1 => const {
      "username": "bob+0@stablekernel.com",
      "password": InMemoryAuthStorage.DefaultPassword
    };

Map<String, String> get user2 => const {
      "username": "bob+1@stablekernel.com",
      "password": InMemoryAuthStorage.DefaultPassword
    };

Map<String, String> get user3 => const {
      "username": "bob+2@stablekernel.com",
      "password": InMemoryAuthStorage.DefaultPassword
    };
