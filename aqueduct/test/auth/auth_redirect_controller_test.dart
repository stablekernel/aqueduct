import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  Application<TestChannel> application;
  Agent client = Agent.onPort(8888);

  final codeResponse = (Map<String, String> form) {
    final m = Map<String, String>.from(form);
    m.addAll({"response_type": "code"});

    final req = client.request("/auth/redirect")
      ..contentType =
          ContentType("application", "x-www-form-urlencoded", charset: "utf-8")
      ..body = m;

    return req.post();
  };

  final tokenResponse = (Map<String, String> form) {
    final m = Map<String, String>.from(form);
    m.addAll({"response_type": "token"});

    final req = client.request("/auth/redirect")
      ..contentType =
          ContentType("application", "x-www-form-urlencoded", charset: "utf-8")
      ..body = m;

    return req.post();
  };

  setUpAll(() async {
    application = Application<TestChannel>();

    await application.startOnCurrentIsolate();
  });

  tearDownAll(() async {
    await application?.stop();
  });

  setUp(() async {
    (application.channel.authServer.delegate as InMemoryAuthStorage).reset();
    (application.channel.authServer.delegate as InMemoryAuthStorage)
        .createUsers(2);
  });

  /////////
  ///// GET - login form
  /////////

  group("GET success case", () {
    test(
        "GET login form with valid code values returns a 'page' with the provided values",
        () async {
      final req = client.request("/auth/code")
        ..query = {
          "client_id": "com.stablekernel.redirect",
          "response_type": "code"
        };

      final resp = await req.get();
      expect(
          resp,
          hasResponse(200,
              body: null,
              headers: {"content-type": "text/html; charset=utf-8"}));

      // The data is actually JSON for purposes of this test, just makes it easier to validate here.
      expect(json.decode(resp.body.as<String>()), {
        "response_type": "code",
        "client_id": "com.stablekernel.redirect",
        "state": null,
        "scope": null,
        "path": "/auth/code"
      });
    });

    test(
        "GET login form with valid token values returns a 'page' with the provided values",
        () async {
      final req = client.request("/auth/redirect")
        ..query = {
          "client_id": "com.stablekernel.public.redirect",
          "response_type": "token"
        };

      final resp = await req.get();
      expect(
          resp,
          hasResponse(200,
              body: null,
              headers: {"content-type": "text/html; charset=utf-8"}));

      // The data is actually JSON for purposes of this test, just makes it easier to validate here.
      expect(json.decode(resp.body.as<String>()), {
        "response_type": "token",
        "client_id": "com.stablekernel.public.redirect",
        "state": null,
        "scope": null,
        "path": "/auth/redirect"
      });
    });

    test(
        "GET login form with valid code values returns a 'page' with the provided values + state + scope",
        () async {
      final req = client.request("/auth/code")
        ..query = {
          "client_id": "com.stablekernel.redirect",
          "state": "Alaska",
          "response_type": "code",
          "scope": "readonly viewonly"
        };
      final resp = await req.get();
      expect(resp, hasStatus(200));
      expect(resp, hasHeaders({"content-type": "text/html; charset=utf-8"}));
      expect(json.decode(resp.body.as<String>()), {
        "response_type": "code",
        "client_id": "com.stablekernel.redirect",
        "state": "Alaska",
        "scope": "readonly viewonly",
        "path": "/auth/code"
      });
    });

    test(
        "GET login form with valid token values returns a 'page' with the provided values + state + scope",
        () async {
      final req = client.request("/auth/redirect")
        ..query = {
          "client_id": "com.stablekernel.public.redirect",
          "state": "Alaska",
          "response_type": "token",
          "scope": "readonly viewonly"
        };
      final resp = await req.get();
      expect(resp, hasStatus(200));
      expect(resp, hasHeaders({"content-type": "text/html; charset=utf-8"}));
      expect(json.decode(resp.body.as<String>()), {
        "response_type": "token",
        "client_id": "com.stablekernel.public.redirect",
        "state": "Alaska",
        "scope": "readonly viewonly",
        "path": "/auth/redirect"
      });
    });
  });

  group("GET failure cases", () {
    test("No registered rendered returns 405", () async {
      final req = client.request("/nopage")
        ..query = {
          "client_id": "com.stablekernel.redirect",
          "response_type": "code"
        };
      final resp = await req.get();
      expect(resp, hasStatus(405));
    });

    test("Invalid response_type yields 400 with error html", () async {
      final req = client.request("/auth/redirect")
        ..query = {
          "client_id": "com.stablekernel.redirect",
          "response_type": "not_a_valid_response_type"
        };
      final resp = await req.get();
      expect(resp, hasStatus(400));
      expect(resp, hasHeaders({"content-type": "text/html; charset=utf-8"}));
    });

    test("Does not allow response_type of token if allowsImplicit is false", () async {
      final req = client.request("/auth/redirect")
        ..query = {
          "client_id": "com.stablekernel.redirect",
          "response_type": "not_a_valid_response_type"
        };
      final resp = await req.get();
      expect(resp, hasStatus(400));
      expect(resp, hasHeaders({"content-type": "text/html; charset=utf-8"}));
    });

    test("Returns 404 when delegate does not render a login page", () async {
      final req = client.request("/bad-delegate")
        ..query = {
          "client_id": "com.stablekernel.redirect",
          "response_type": "code"
        };
      final resp = await req.get();
      expect(resp, hasStatus(404));
    });
  });

  ///////
  /// POST - authenticate
  ///////
  group("Code Success cases", () {
    test("With required values", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword
      });

      expectRedirect(resp, Uri.http("stablekernel.com", "/auth/redirect"),
          state: "Wisconsin@&");
    });

    test("With scope", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "user"
      });

      expectRedirect(resp, Uri.http("stablekernel.com", "/auth/scoped"),
          state: "Wisconsin@&");

      final redirectURI = Uri.parse(resp.headers["location"].first);
      final codeParam = redirectURI.queryParameters["code"];
      final token = await application.channel.authServer
          .exchange(codeParam, "com.stablekernel.scoped", "kilimanjaro");
      expect(token.scopes.length, 1);
      expect(token.scopes.first.isExactly("user"), true);
    });

    test("With multiple scopes", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "user other_scope"
      });

      expectRedirect(resp, Uri.http("stablekernel.com", "/auth/scoped"),
          state: "Wisconsin@&");

      final redirectURI = Uri.parse(resp.headers["location"].first);
      final codeParam = redirectURI.queryParameters["code"];
      final token = await application.channel.authServer
          .exchange(codeParam, "com.stablekernel.scoped", "kilimanjaro");
      expect(token.scopes.length, 2);
      expect(token.scopes.any((s) => s.isExactly("user")), true);
      expect(token.scopes.any((s) => s.isExactly("other_scope")), true);
    });
  });

  group("Token Success cases", () {
    test("With required values", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword
      });

      expectTokenRedirect(resp, Uri.http("stablekernel.com", "/auth/public-redirect"),
          state: "Wisconsin@&");
    });

    test("With scope", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "user"
      });

      expectTokenRedirect(resp, Uri.http("stablekernel.com", "/auth/public-scoped"),
          state: "Wisconsin@&");

      final redirectURI = Uri.parse(resp.headers["location"].first);
      final fragmentParams = parametersFromFragment(redirectURI.fragment);

      expect(fragmentParams["scope"], "user");
    });

    test("With multiple scopes", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "user other_scope"
      });

      expectTokenRedirect(resp, Uri.http("stablekernel.com", "/auth/public-scoped"),
          state: "Wisconsin@&");

      final redirectURI = Uri.parse(resp.headers["location"].first);
      final fragmentParams = parametersFromFragment(redirectURI.fragment);
      final scopes = fragmentParams["scope"].split(" ");

      expect(scopes, unorderedMatches(["user", "other_scope"]));
    });
  });

  group("Code username Failure Cases", () {
    test("Username does not exist yields 302 with error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "FOOBAR",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "a"
      });
      expectErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("Username is empty returns 302 with error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "a"
      });
      expectErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("Username is missing returns 302 with error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "a"
      });
      expectErrorRedirect(resp, Uri.http("stablekernel.com", "/auth/redirect"),
          "invalid_request",
          state: "a");
    });

    test("Username is repeated returns 400", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.
      final encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      final encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      final encodedWrongUsername = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.request("/auth/code")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&username=$encodedWrongUsername&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/code")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedWrongUsername&username=$encodedUsername&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });
  });

  group("Token username Failure Cases", () {
    test("Username does not exist yields 302 with error", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "username": "FOOBAR",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "a"
      });
      expectTokenErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/public-redirect"), "access_denied",
          state: "a");
    });

    test("Username is empty returns 302 with error", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "username": "",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "a"
      });
      expectTokenErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/public-redirect"), "access_denied",
          state: "a");
    });

    test("Username is missing returns 302 with error", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "a"
      });
      expectTokenErrorRedirect(resp, Uri.http("stablekernel.com", "/auth/public-redirect"),
          "invalid_request",
          state: "a");
    });

    test("Username is repeated returns 400", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.
      final encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      final encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      final encodedWrongUsername = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.request("/auth/redirect")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&username=$encodedWrongUsername&password=$encodedPassword&response_type=token&client_id=com.stablekernel.public.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/redirect")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedWrongUsername&username=$encodedUsername&password=$encodedPassword&response_type=token&client_id=com.stablekernel.public.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });
  });

  group("Code password Failure Cases", () {
    test("password is incorrect yields 302 with error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": "nonsense",
        "state": "a"
      });
      expectErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("password is empty returns 302 with error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": "",
        "state": "a"
      });
      expectErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("password is missing returns 302 with error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "state": "a"
      });
      expectErrorRedirect(resp, Uri.http("stablekernel.com", "/auth/redirect"),
          "invalid_request",
          state: "a");
    });

    test("password is repeated returns 302 with error", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.

      final encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      final encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      final encodedWrongPassword = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.request("/auth/code")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedWrongPassword&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/code")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&password=$encodedWrongPassword&response_type=code&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });
  });

  group("Token password Failure Cases", () {
    test("password is incorrect yields 302 with error", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "username": user1["username"],
        "password": "nonsense",
        "state": "a"
      });
      expectTokenErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/public-redirect"), "access_denied",
          state: "a");
    });

    test("password is empty returns 302 with error", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "username": user1["username"],
        "password": "",
        "state": "a"
      });
      expectTokenErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/public-redirect"), "access_denied",
          state: "a");
    });

    test("password is missing returns 302 with error", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "username": user1["username"],
        "state": "a"
      });
      expectTokenErrorRedirect(resp, Uri.http("stablekernel.com", "/auth/public-redirect"),
          "invalid_request",
          state: "a");
    });

    test("password is repeated returns 302 with error", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.

      final encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      final encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      final encodedWrongPassword = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.request("/auth/redirect")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedWrongPassword&password=$encodedPassword&response_type=code&client_id=com.stablekernel.public.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/redirect")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&password=$encodedWrongPassword&response_type=code&client_id=com.stablekernel.public.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });
  });

  group("response_type failures", () {
    test("response_type is invalid returns 400 with error", () async {
      final encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      final encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      final req = client.request("/auth/redirect")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&response_type=notcode&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      final resp = await req.post();
      expect(resp, hasStatus(400));
    });

    test("response_type is duplicated returns 302 with error", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.
      final encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      final encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/redirect")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&response_type=notcode&response_type=code&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/redirect")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&response_type=code&response_type=notcode&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });
  });

  group("client_id failures", () {
    test("Omit client_id returns 400", () async {
      final resp = await tokenResponse({
        "username": user1["username"],
        "password": user1["password"],
        "state": "a"
      });
      expect(resp, hasStatus(400));
    });

    test("client_id does not exist for app returns 400", () async {
      final resp = await tokenResponse({
        "client_id": "abc",
        "username": user1["username"],
        "password": user1["password"],
        "state": "a"
      });
      expect(resp, hasStatus(400));
    });

    test("client_id that does not have redirectURI returns 400", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.app1",
        "username": user1["username"],
        "password": user1["password"],
        "state": "a"
      });
      expect(resp, hasStatus(400));
    });

    test("client_id is duplicated returns 400", () async {
      final encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      final encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/redirect")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&response_type=code&client_id=com.stablekernel.redirect&client_id=foobar&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/code")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&response_type=code&client_id=foobar&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasStatus(400));
    });

    test("client_id is empty returns 400", () async {
      final resp = await tokenResponse({
        "client_id": "",
        "username": user1["username"],
        "password": user1["password"],
        "state": "a"
      });
      expect(resp, hasStatus(400));
    });
  });

  group("Code Invalid requests and state", () {
    test("public client with response type code redirects with error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.public.redirect",
        "username": user1["username"],
        "password": user1["password"],
        "state": "a"
      });
      expectErrorRedirect(resp, Uri.http("stablekernel.com", "/auth/public-redirect"), "unauthorized_client", state: "a");
    });

    test("Omit state is error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": InMemoryAuthStorage.defaultPassword
      });

      expectErrorRedirect(resp, Uri.http("stablekernel.com", "/auth/redirect"), "invalid_request");
    });

    test("Failed username + state still returns state in error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "FOOBAR",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "xyz"
      });
      expectErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "xyz");
    });

    test("Failed password + state still returns state in error", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": "nonsense",
        "state": "xyz"
      });
      expectErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "xyz");
    });
  });

  group("Token Invalid requests and state", () {
    test("Does not allow response_type of token if allowsImplicit is false", () async {
      final encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      final encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      final req = client.request("/auth/code")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&response_type=token&client_id=com.stablekernel.public.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      final resp = await req.post();
      expect(resp, hasStatus(400));
      expect(resp, hasHeaders({"content-type": "text/html; charset=utf-8"}));
    });

    test("Omit state is error", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "username": user1["username"],
        "password": InMemoryAuthStorage.defaultPassword
      });

      expectTokenErrorRedirect(resp, Uri.http("stablekernel.com", "/auth/public-redirect"), "invalid_request");
    });

    test("Failed username + state still returns state in error", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "username": "FOOBAR",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "xyz"
      });
      expectTokenErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/public-redirect"), "access_denied",
          state: "xyz");
    });

    test("Failed password + state still returns state in error", () async {
      final resp = await tokenResponse({
        "client_id": "com.stablekernel.public.redirect",
        "username": user1["username"],
        "password": "nonsense",
        "state": "xyz"
      });
      expectTokenErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/public-redirect"), "access_denied",
          state: "xyz");
    });
  });

  group("Scope failure cases", () {
    test("Malformed scope", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "u\"ser"
      });

      expectErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/scoped"), "invalid_scope",
          state: "Wisconsin@&");
    });

    test("Scope that client can't grant", () async {
      final resp = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "invalid"
      });

      expectErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/scoped"), "invalid_scope",
          state: "Wisconsin@&");
    });
  });

  group("Documentation", () {
    Map<String, APIOperation> operations;
    setUpAll(() async {
      final context = APIDocumentContext(APIDocument()
        ..info = APIInfo("title", "1.0.0")
        ..paths = {}
        ..components = APIComponents());
      AuthRedirectController ac =
          AuthRedirectController(AuthServer(InMemoryAuthStorage()));
      ac.restore(ac.recycledState);
      ac.didAddToChannel();
      operations = ac.documentOperations(context, "/", APIPath());
      await context.finalize();
    });

    test("Has GET and POST operation", () {
      expect(operations, {"get": isNotNull, "post": isNotNull});
    });

    test("GET serves HTML string for only response", () {
      expect(operations["get"].responses.length, 1);
      expect(
          operations["get"].responses["200"].content["text/html"].schema.type,
          APIType.string);
    });

    test("GET has parameters for client_id, state, response_type and scope",
        () {
      final op = operations["get"];
      expect(op.parameters.length, 4);
      expect(
          op.parameters.every((p) => p.location == APIParameterLocation.query),
          true);
      expect(op.parameterNamed("client_id").schema.type, APIType.string);
      expect(op.parameterNamed("scope").schema.type, APIType.string);
      expect(op.parameterNamed("response_type").schema.type, APIType.string);
      expect(op.parameterNamed("state").schema.type, APIType.string);

      expect(op.parameterNamed("client_id").isRequired, true);
      expect(op.parameterNamed("scope").isRequired, false);
      expect(op.parameterNamed("response_type").isRequired, true);
      expect(op.parameterNamed("state").isRequired, true);
    });

    test(
        "POST has body parameteters for client_id, state, response_type, scope, username and password",
        () {
      final op = operations["post"];
      expect(op.parameters.length, 0);
      expect(op.requestBody.isRequired, true);

      final content =
          op.requestBody.content["application/x-www-form-urlencoded"];
      expect(content, isNotNull);

      expect(content.schema.type, APIType.object);
      expect(content.schema.properties.length, 6);
      expect(content.schema.properties["client_id"].type, APIType.string);
      expect(content.schema.properties["scope"].type, APIType.string);
      expect(content.schema.properties["state"].type, APIType.string);
      expect(content.schema.properties["response_type"].type, APIType.string);
      expect(content.schema.properties["username"].type, APIType.string);
      expect(content.schema.properties["password"].type, APIType.string);
      expect(content.schema.properties["password"].format, "password");
      expect(content.schema.required,
          ["client_id", "state", "response_type", "username", "password"]);
    });

    test("POST response can be redirect or bad request", () {
      expect(operations["post"].responses, {
        "${HttpStatus.movedTemporarily}": isNotNull,
        "${HttpStatus.badRequest}": isNotNull,
      });
    });

    test("POST response is a redirect", () {
      final redirectResponse =
          operations["post"].responses["${HttpStatus.movedTemporarily}"];
      expect(redirectResponse.content, isNull);
      expect(redirectResponse.headers["Location"].schema.type, APIType.string);
      expect(redirectResponse.headers["Location"].schema.format, "uri");
    });
  });
}

class TestChannel extends ApplicationChannel
    implements AuthRedirectControllerDelegate {
  AuthServer authServer;
  BadAuthRedirectDelegate badDelegate = BadAuthRedirectDelegate();

  @override
  Future prepare() async {
    final storage = InMemoryAuthStorage();
    authServer = AuthServer(storage);
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router
        .route("/auth/code")
        .link(() => AuthRedirectController(authServer, delegate: this, allowsImplicit: false));

    router
        .route("/auth/redirect")
        .link(() => AuthRedirectController(authServer, delegate: this));

    router.route("/bad-delegate").link(() => AuthRedirectController(authServer, delegate: badDelegate));
    router.route("/nopage").link(() => AuthRedirectController(authServer));
    return router;
  }

  @override
  Future<String> render(AuthRedirectController forController, Uri requestUri,
      String responseType, String clientID, String state, String scope) async {
    return json.encode({
      "response_type": responseType,
      "path": requestUri.path,
      "client_id": clientID,
      "state": state,
      "scope": scope
    });
  }
}

class BadAuthRedirectDelegate implements AuthRedirectControllerDelegate {
  @override
  Future<String> render(AuthRedirectController forController, Uri requestUri,
      String responseType, String clientID, String state, String scope) async {
    return null;
  }
}

void expectRedirect(TestResponse resp, Uri requestURI, {String state}) {
  expect(resp, hasStatus(HttpStatus.movedTemporarily));

  final location = resp.headers.value(HttpHeaders.locationHeader);
  final uri = Uri.parse(location);

  expect(uri.queryParameters["code"], hasLength(greaterThan(0)));
  expect(uri.queryParameters["state"], state);
  expect(uri.authority, equals(requestURI.authority));
  expect(uri.path, equals(requestURI.path));

  expect(uri.queryParametersAll["code"].length, 1);

  if (state != null) {
    expect(uri.queryParametersAll["state"].length, 1);
  }
}

void expectTokenRedirect(TestResponse resp, Uri requestURI, {String state}) {
  expect(resp, hasStatus(HttpStatus.movedTemporarily));

  final location = resp.headers.value(HttpHeaders.locationHeader);
  final uri = Uri.parse(location);

  final fragmentParams = parametersFromFragment(uri.fragment);

  expect(fragmentParams["access_token"], hasLength(greaterThan(0)));
  expect(fragmentParams["token_type"], hasLength(greaterThan(0)));
  expect(fragmentParams["expires_in"], hasLength(greaterThan(0)));
  expect(fragmentParams.containsKey("refresh_token"), false);
  expect(fragmentParams["state"], state);
  expect(uri.authority, equals(requestURI.authority));
  expect(uri.path, equals(requestURI.path));
}

void expectErrorRedirect(TestResponse resp, Uri requestURI, String errorReason,
    {String state}) {
  expect(resp, hasStatus(HttpStatus.movedTemporarily));

  final location = resp.headers.value(HttpHeaders.locationHeader);
  final uri = Uri.parse(location);
  expect(uri.authority, requestURI.authority);
  expect(uri.path, requestURI.path);
  expect(uri.queryParameters["error"], errorReason);
  expect(uri.queryParameters["state"], state);
  expect(uri.queryParametersAll["error"].length, 1);

  if (state != null) {
    expect(uri.queryParametersAll["state"].length, 1);
  }
}

void expectTokenErrorRedirect(TestResponse resp, Uri requestURI, String errorReason,
    {String state}) {
  expect(resp, hasStatus(HttpStatus.movedTemporarily));

  final location = resp.headers.value(HttpHeaders.locationHeader);
  final uri = Uri.parse(location);

  final fragmentParams = parametersFromFragment(uri.fragment);

  expect(fragmentParams["error"], errorReason);
  expect(fragmentParams["state"], state);
  expect(uri.authority, equals(requestURI.authority));
  expect(uri.path, equals(requestURI.path));
}

Map<String, String> parametersFromFragment(String fragment) {
  if (fragment == null || fragment.isEmpty) {
    return {};
  }

  return fragment.split("&").fold({}, (params, param) {
    final components = param.split("=");
    params[components[0]] = Uri.decodeQueryComponent(components[1]);
    return params;
  });
}

Map<String, String> get user1 => const {
      "username": "bob+0@stablekernel.com",
      "password": InMemoryAuthStorage.defaultPassword
    };

Map<String, String> get user2 => const {
      "username": "bob+1@stablekernel.com",
      "password": InMemoryAuthStorage.defaultPassword
    };

Map<String, String> get user3 => const {
      "username": "bob+2@stablekernel.com",
      "password": InMemoryAuthStorage.defaultPassword
    };
