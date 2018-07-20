import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/utilities/documented_element.dart';
import 'package:aqueduct/src/utilities/documented_element_analyzer_bridge.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  DocumentedElement.provider = AnalyzerDocumentedElementProvider();
  Application<TestChannel> application;
  Agent client = Agent.onPort(8888);

  var codeResponse = (Map<String, String> form) {
    var m = Map<String, String>.from(form);
    m.addAll({"response_type": "code"});

    var req = client.request("/auth/code")
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
        "GET login form with valid values returns a 'page' with the provided values",
        () async {
      var req = client.request("/auth/code")
        ..query = {
          "client_id": "com.stablekernel.redirect",
          "response_type": "code"
        };

      var res = await req.get();
      expect(
          res,
          hasResponse(200,
              body: null,
              headers: {"content-type": "text/html; charset=utf-8"}));

      // The data is actually JSON for purposes of this test, just makes it easier to validate here.
      expect(json.decode(res.body.as<String>()), {
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
        ..query = {
          "client_id": "com.stablekernel.redirect",
          "state": "Alaska",
          "response_type": "code",
          "scope": "readonly viewonly"
        };
      var res = await req.get();
      expect(res, hasStatus(200));
      expect(res, hasHeaders({"content-type": "text/html; charset=utf-8"}));
      expect(json.decode(res.body.as<String>()), {
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
        ..query = {
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
        "password": InMemoryAuthStorage.defaultPassword
      });

      expectRedirect(res, Uri.http("stablekernel.com", "/auth/redirect"),
          state: "Wisconsin@&");
    });

    test("With scope", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "user"
      });

      expectRedirect(res, Uri.http("stablekernel.com", "/auth/scoped"),
          state: "Wisconsin@&");

      var redirectURI = Uri.parse(res.headers["location"].first);
      var codeParam = redirectURI.queryParameters["code"];
      var token = await application.channel.authServer
          .exchange(codeParam, "com.stablekernel.scoped", "kilimanjaro");
      expect(token.scopes.length, 1);
      expect(token.scopes.first.isExactly("user"), true);
    });

    test("With multiple scopes", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "user other_scope"
      });

      expectRedirect(res, Uri.http("stablekernel.com", "/auth/scoped"),
          state: "Wisconsin@&");

      var redirectURI = Uri.parse(res.headers["location"].first);
      var codeParam = redirectURI.queryParameters["code"];
      var token = await application.channel.authServer
          .exchange(codeParam, "com.stablekernel.scoped", "kilimanjaro");
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
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "a"
      });
      expectErrorRedirect(
          res, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("Username is empty returns 302 with error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": "",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "a"
      });
      expectErrorRedirect(
          res, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "a");
    });

    test("Username is missing returns 302 with error", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "a"
      });
      expectErrorRedirect(res, Uri.http("stablekernel.com", "/auth/redirect"),
          "invalid_request",
          state: "a");
    });

    test("Username is repeated returns 400", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongUsername = Uri.encodeQueryComponent("!@#kjasd");

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

  group("password Failure Cases", () {
    test("password is incorrect yields 302 with error", () async {
      var resp = await codeResponse({
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
      var resp = await codeResponse({
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
      var resp = await codeResponse({
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

      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongPassword = Uri.encodeQueryComponent("!@#kjasd");

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

  group("response_type failures", () {
    test("response_type is invalid returns 302 with error", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&response_type=notcode&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expectErrorRedirect(resp, Uri.http("stablekernel.com", "/auth/redirect"),
          "invalid_request",
          state: "a");
    });

    test("response_type is duplicated returns 302 with error", () async {
      // This isn't precisely to the OAuth 2.0 spec, but doing otherwise
      // would get a bit ugly.
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&response_type=notcode&response_type=code&client_id=com.stablekernel.redirect&state=a")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasStatus(400));

      req = client.request("/auth/code")
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

      var req = client.request("/auth/code")
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
        "password": InMemoryAuthStorage.defaultPassword
      });

      expect(resp, hasStatus(HttpStatus.movedTemporarily));

      var location = resp.headers.value(HttpHeaders.locationHeader);
      var uri = Uri.parse(location);
      var requestURI = Uri.http("stablekernel.com", "/auth/redirect");
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
        "password": InMemoryAuthStorage.defaultPassword,
        "state": "xyz"
      });
      expectErrorRedirect(
          res, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "xyz");
    });

    test("Failed password + state still returns state in error", () async {
      var resp = await codeResponse({
        "client_id": "com.stablekernel.redirect",
        "username": user1["username"],
        "password": "nonsense",
        "state": "xyz"
      });
      expectErrorRedirect(
          resp, Uri.http("stablekernel.com", "/auth/redirect"), "access_denied",
          state: "xyz");
    });

    test("Failed response_type + state still returns state in error", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);

      var req = client.request("/auth/code")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&response_type=notcode&client_id=com.stablekernel.redirect&state=xyz")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expectErrorRedirect(resp, Uri.http("stablekernel.com", "/auth/redirect"),
          "invalid_request",
          state: "xyz");
    });
  });

  group("Scope failure cases", () {
    test("Malformed scope", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "u\"ser"
      });

      expectErrorRedirect(
          res, Uri.http("stablekernel.com", "/auth/scoped"), "invalid_scope",
          state: "Wisconsin@&");
    });

    test("Scope that client can't grant", () async {
      var res = await codeResponse({
        "client_id": "com.stablekernel.scoped",
        "state": "Wisconsin@&",
        "username": "bob+0@stablekernel.com",
        "password": InMemoryAuthStorage.defaultPassword,
        "scope": "invalid"
      });

      expectErrorRedirect(
          res, Uri.http("stablekernel.com", "/auth/scoped"), "invalid_scope",
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
      AuthCodeController ac =
          AuthCodeController(AuthServer(InMemoryAuthStorage()));
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
    implements AuthCodeControllerDelegate {
  AuthServer authServer;

  @override
  Future prepare() async {
    var storage = InMemoryAuthStorage();
    authServer = AuthServer(storage);
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router
        .route("/auth/code")
        .link(() => AuthCodeController(authServer, delegate: this));

    router.route("/nopage").link(() => AuthCodeController(authServer));
    return router;
  }

  @override
  Future<String> render(AuthCodeController forController, Uri requestUri,
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

void expectRedirect(TestResponse resp, Uri requestURI, {String state}) {
  expect(resp, hasStatus(HttpStatus.movedTemporarily));

  var location = resp.headers.value(HttpHeaders.locationHeader);
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
  expect(resp, hasStatus(HttpStatus.movedTemporarily));

  var location = resp.headers.value(HttpHeaders.locationHeader);
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
