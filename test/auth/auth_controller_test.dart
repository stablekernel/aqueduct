import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/test.dart';

import '../helpers.dart';

void main() {
  HttpServer server;
  TestClient client = new TestClient.onPort(8888)
    ..clientID = "com.stablekernel.app1"
    ..clientSecret = "kilimanjaro";
  AuthServer authenticationServer;
  Router router;

  var tokenResponse =
      (String clientID, String clientSecret, Map<String, String> form) {
    var m = new Map<String, String>.from(form);
    m.addAll({"grant_type": "password"});

    var req = client.clientAuthenticatedRequest("/auth/token",
        clientID: clientID, clientSecret: clientSecret)..formData = m;

    return req.post();
  };

  var refreshResponse =
      (String clientID, String clientSecret, Map<String, String> form) {
    var m = new Map<String, String>.from(form);
    m.addAll({"grant_type": "refresh_token"});

    var req = client.clientAuthenticatedRequest("/auth/token",
        clientID: clientID, clientSecret: clientSecret)..formData = m;

    return req.post();
  };

  var exchangeResponse = (String clientID, String clientSecret, String code) {
    var m = {"grant_type": "authorization_code"};

    if (code != null) {
      m["code"] = Uri.encodeQueryComponent(code);
    }

    var req = client.clientAuthenticatedRequest("/auth/token",
        clientID: clientID, clientSecret: clientSecret)..formData = m;

    return req.post();
  };

  ////////////

  setUp(() async {
    var storage = new InMemoryAuthStorage();
    storage.createUsers(3);
    authenticationServer = new AuthServer(storage);

    router = new Router();
    router
        .route("/auth/token")
        .link(() => new AuthController(authenticationServer));
    router.prepare();

    server =
        await HttpServer.bind("localhost", 8888, v6Only: false, shared: false);
    server.map((req) => new Request(req)).listen(router.receive);
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  ///////

  group("Success Cases: password", () {
    test("Confidental Client has all parameters including refresh_token",
        () async {
      var res =
          await tokenResponse("com.stablekernel.app1", "kilimanjaro", user1);

      expect(res, hasAuthResponse(200, bearerTokenMatcher));
    });

    test("Public Client has all parameters except refresh_token", () async {
      var res = await tokenResponse("com.stablekernel.public", "", user1);

      expect(res, hasAuthResponse(200, bearerTokenWithoutRefreshMatcher));
    });

    test(
        "Can authenticate with resource owner grant with client ID that has redirect url",
        () async {
      var res =
          await tokenResponse("com.stablekernel.redirect", "mckinley", user1);
      expect(res, hasAuthResponse(200, bearerTokenMatcher));
    });

    test("Can be scoped", () async {
      var m = new Map<String, String>.from(user1);
      m["scope"] = "user";

      var res =
        await tokenResponse("com.stablekernel.scoped", "kilimanjaro", m);
      expect(res, hasAuthResponse(200, bearerTokenMatcherWithScope("user")));

      m["scope"] = "user other_scope";
      res = await tokenResponse("com.stablekernel.scoped", "kilimanjaro", m);
      expect(res, hasAuthResponse(200, bearerTokenMatcherWithScope("user other_scope")));
    });
  });

  group("Success Cases: refresh_token", () {
    test(
        "Confidental Client gets a new access token, retains same access token",
        () async {
      var resToken =
          await tokenResponse("com.stablekernel.app1", "kilimanjaro", user1);

      var resRefresh = await refreshResponse("com.stablekernel.app1",
          "kilimanjaro", refreshTokenMapFromTokenResponse(resToken));
      expect(
          resRefresh,
          hasResponse(200, {
            "access_token": isString,
            "refresh_token": resToken.asMap["refresh_token"],
            "expires_in": greaterThan(3500),
            "token_type": "bearer"
          }, headers: {
            "content-type": "application/json; charset=utf-8",
            "cache-control": "no-store",
            "pragma": "no-cache",
            "content-encoding": "gzip",
            "content-length": greaterThan(0),
            "x-frame-options": isString,
            "x-xss-protection": isString,
            "x-content-type-options": isString
          }));
    });

    test("If token is scoped and scope is omitted, get same token back", () async {
      var m = new Map<String, String>.from(user1);
      m["scope"] = "user";

      var resToken =
      await tokenResponse("com.stablekernel.scoped", "kilimanjaro", m);

      var resRefresh = await refreshResponse("com.stablekernel.scoped",
          "kilimanjaro", refreshTokenMapFromTokenResponse(resToken));
      expect(
          resRefresh,
          hasResponse(200, {
            "access_token": isString,
            "refresh_token": resToken.asMap["refresh_token"],
            "expires_in": greaterThan(3500),
            "token_type": "bearer",
            "scope": "user"
          }, headers: {
            "content-type": "application/json; charset=utf-8",
            "cache-control": "no-store",
            "pragma": "no-cache",
            "content-encoding": "gzip",
            "content-length": greaterThan(0),
            "x-frame-options": isString,
            "x-xss-protection": isString,
            "x-content-type-options": isString
          }));
    });

    test("If token is scoped and scope is part of request, get rescoped token", () async {
      var m = new Map<String, String>.from(user1);
      m["scope"] = "user other_scope";

      var resToken =
        await tokenResponse("com.stablekernel.scoped", "kilimanjaro", m);

      var refreshMap = refreshTokenMapFromTokenResponse(resToken);
      refreshMap["scope"] = "user";
      var resRefresh = await refreshResponse("com.stablekernel.scoped",
          "kilimanjaro", refreshMap);
      expect(
          resRefresh,
          hasResponse(200, {
            "access_token": isString,
            "refresh_token": resToken.asMap["refresh_token"],
            "expires_in": greaterThan(3500),
            "token_type": "bearer",
            "scope": "user"
          }, headers: {
            "content-type": "application/json; charset=utf-8",
            "cache-control": "no-store",
            "pragma": "no-cache",
            "content-encoding": "gzip",
            "content-length": greaterThan(0),
            "x-frame-options": isString,
            "x-xss-protection": isString,
            "x-content-type-options": isString
          }));
    });
  });

  group("Success Cases: authorization_code", () {
    test("Exchange valid code gets new access token with refresh token",
        () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.redirect");
      var res = await exchangeResponse(
          "com.stablekernel.redirect", "mckinley", code.code);
      expect(res, hasAuthResponse(200, bearerTokenMatcher));
    });

    test("If code is scoped, token has same scope", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.scoped",
          requestedScopes: [new AuthScope("user")]);

      var res = await exchangeResponse(
          "com.stablekernel.scoped", "kilimanjaro", code.code);
      expect(res, hasAuthResponse(200, bearerTokenMatcherWithScope("user")));
    });
  });

  group("username Failure Cases", () {
    test("Username does not exist yields 400", () async {
      var resToken = await tokenResponse("com.stablekernel.app1", "kilimanjaro",
          substituteUser(user1, username: "foobar"));
      expect(resToken, hasResponse(400, {"error": "invalid_grant"}));
    });

    test("Username is empty returns 400", () async {
      var resToken = await tokenResponse("com.stablekernel.app1", "kilimanjaro",
          substituteUser(user1, username: ""));
      expect(resToken, hasResponse(400, {"error": "invalid_grant"}));
    });

    test("Username is missing returns 400", () async {
      var resToken = await tokenResponse(
          "com.stablekernel.app1", "kilimanjaro", {"password": "doesntmatter"});
      expect(resToken, hasResponse(400, {"error": "invalid_request"}));
    });

    test("Username is repeated returns 400", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongUsername = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.app1", clientSecret: "kilimanjaro");
      req.body =
          "username=$encodedUsername&username=$encodedWrongUsername&password=$encodedPassword&grant_type=password";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasResponse(400, {"error": "invalid_request"}));

      req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.app1", clientSecret: "kilimanjaro");
      req.body =
          "username=$encodedWrongUsername&username=$encodedUsername&password=$encodedPassword&grant_type=password";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasResponse(400, {"error": "invalid_request"}));
    });
  });

  group("password Failure Cases", () {
    test("password is incorrect yields 400", () async {
      var resToken = await tokenResponse("com.stablekernel.app1", "kilimanjaro",
          substituteUser(user1, password: "!@#\$%^&*()"));
      expect(resToken, hasResponse(400, {"error": "invalid_grant"}));
    });

    test("password is empty returns 400", () async {
      var resToken = await tokenResponse("com.stablekernel.app1", "kilimanjaro",
          substituteUser(user1, password: ""));
      expect(resToken, hasResponse(400, {"error": "invalid_grant"}));
    });

    test("password is missing returns 400", () async {
      var resToken = await tokenResponse("com.stablekernel.app1", "kilimanjaro",
          {"username": "${user1["username"]}"});
      expect(resToken, hasResponse(400, {"error": "invalid_request"}));
    });

    test("password is repeated returns 400", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongPassword = Uri.encodeQueryComponent("!@#kjasd");

      var req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.app1", clientSecret: "kilimanjaro");
      req.body =
          "username=$encodedUsername&password=$encodedPassword&password=$encodedWrongPassword&grant_type=password";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasResponse(400, {"error": "invalid_request"}));

      req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.app1", clientSecret: "kilimanjaro");
      req.body =
          "username=$encodedUsername&password=$encodedWrongPassword&password=$encodedPassword&grant_type=password";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasResponse(400, {"error": "invalid_request"}));
    });
  });

  group("code Failure Cases", () {
    test("code is invalid (not issued)", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.redirect");
      var res = await exchangeResponse(
          "com.stablekernel.redirect", "mckinley", "a" + code.code);
      expect(res, hasResponse(400, {"error": "invalid_grant"}));
    });

    test("code is missing", () async {
      var res =
          await exchangeResponse("com.stablekernel.redirect", "mckinley", null);
      expect(res, hasResponse(400, {"error": "invalid_request"}));
    });

    test("code is empty", () async {
      var res =
          await exchangeResponse("com.stablekernel.redirect", "mckinley", "");
      expect(res, hasResponse(400, {"error": "invalid_grant"}));
    });

    test("code is duplicated", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.redirect");
      var encodedCode = Uri.encodeQueryComponent(code.code);

      var req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.redirect", clientSecret: "mckinley");
      req.body = "code=$encodedCode&code=abcd&grant_type=authorization_code";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasResponse(400, {"error": "invalid_request"}));

      req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.redirect", clientSecret: "mckinley");
      req.body = "code=abcd&code=$encodedCode&grant_type=authorization_code";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasResponse(400, {"error": "invalid_request"}));
    });

    test("code is from a different client", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.redirect");
      var res = await exchangeResponse(
          "com.stablekernel.redirect2", "gibraltar", code.code);
      expect(res, hasResponse(400, {"error": "invalid_grant"}));
    });
  });

  group("grant_type Failure Cases", () {
    test("Unknown grant_type", () async {
      var req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.app1", clientSecret: "kilimanjaro")
        ..formData = {
          "username": user1["username"],
          "password": user1["password"],
          "grant_type": "nonsense"
        };

      var res = await req.post();

      expect(res, hasResponse(400, {"error": "unsupported_grant_type"}));
    });

    test("Missing grant_type", () async {
      var req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.app1", clientSecret: "kilimanjaro")
        ..formData = {
          "username": user1["username"],
          "password": user1["password"]
        };

      var res = await req.post();

      expect(res, hasResponse(400, {"error": "invalid_request"}));
    });

    test("Duplicate grant_type", () async {
      var req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.redirect", clientSecret: "mckinley");
      req.body = "code=abcd&grant_type=authorization_code&grant_type=whatever";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");

      var res = await req.post();
      expect(res, hasResponse(400, {"error": "invalid_request"}));

      req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.redirect", clientSecret: "mckinley");
      req.body = "grant_type=authorization_code&code=abcd&grant_type=whatever";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");

      res = await req.post();
      expect(res, hasResponse(400, {"error": "invalid_request"}));
    });
  });

  group("refresh_token Failure Cases", () {
    test("refresh_token is omitted", () async {
      var resToken =
          await tokenResponse("com.stablekernel.app1", "kilimanjaro", user1);

      var m = refreshTokenMapFromTokenResponse(resToken);
      m.remove("refresh_token");
      var resRefresh =
          await refreshResponse("com.stablekernel.app1", "kilimanjaro", m);
      expect(resRefresh, hasResponse(400, {"error": "invalid_request"}));
    });

    test("refresh_token appears more than once", () async {
      var refreshToken = Uri.encodeQueryComponent(
          (await tokenResponse("com.stablekernel.app1", "kilimanjaro", user1))
              .asMap["refresh_token"]);

      var req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.app1", clientSecret: "kilimanjaro");
      req.body =
          "refresh_token=$refreshToken&refresh_token=abcdefg&grant_type=refresh_token";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasResponse(400, {"error": "invalid_request"}));

      req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.app1", clientSecret: "kilimanjaro");
      req.body =
          "refresh_token=abcdefg&refresh_token=$refreshToken&grant_type=refresh_token";
      req.contentType = new ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasResponse(400, {"error": "invalid_request"}));
    });

    test("refresh_token is empty", () async {
      var resToken =
          await tokenResponse("com.stablekernel.app1", "kilimanjaro", user1);

      var m = refreshTokenMapFromTokenResponse(resToken);
      m["refresh_token"] = "";
      var resRefresh =
          await refreshResponse("com.stablekernel.app1", "kilimanjaro", m);
      expect(resRefresh, hasResponse(400, {"error": "invalid_grant"}));
    });

    test("Refresh token doesn't exist (was not issued)", () async {
      var resToken =
          await tokenResponse("com.stablekernel.app1", "kilimanjaro", user1);

      var m = refreshTokenMapFromTokenResponse(resToken);
      m["refresh_token"] = m["refresh_token"] + "a";
      var resRefresh =
          await refreshResponse("com.stablekernel.app1", "kilimanjaro", m);
      expect(resRefresh, hasResponse(400, {"error": "invalid_grant"}));
    });

    test("Client id/secret pair is different than original", () async {
      var resToken =
          await tokenResponse("com.stablekernel.app1", "kilimanjaro", user1);

      var resRefresh = await refreshResponse("com.stablekernel.app2", "fuji",
          refreshTokenMapFromTokenResponse(resToken));
      expect(resRefresh, hasResponse(400, {"error": "invalid_grant"}));
    });
  });

  group("Authorization Header Failure Cases (password grant_type)", () {
    test("Client omits authorization header", () async {
      var m = new Map<String, String>.from(user1);
      m["grant_type"] = "password";
      var req = client.request("/auth/token")..formData = m;

      var resToken = await req.post();
      expect(resToken, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential client has malformed authorization header", () async {
      var m = new Map<String, String>.from(user1);
      m["grant_type"] = "password";
      var req = client.request("/auth/token")
        ..addHeader("Authorization", "Basic ")
        ..formData = m;

      var resToken = await req.post();
      expect(resToken, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential client has wrong secret", () async {
      var resp =
          await tokenResponse("com.stablekernel.app1", "notright", user1);
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test(
        "Confidential client can't be used as a public client (i.e. without secret)",
        () async {
      var resp = await tokenResponse("com.stablekernel.app1", "", user1);
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Public client has wrong secret (any secret)", () async {
      var resp = await tokenResponse("com.stablekernel.public", "foo", user1);
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential Client ID doesn't exist", () async {
      var resp = await tokenResponse("com.stablekernel.app123", "foo", user1);
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Public Client ID doesn't exist", () async {
      var resp = await tokenResponse("com.stablekernel.app123", "", user1);
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });
  });

  group("Authorization Header Failure Cases (refresh_token grant_type)", () {
    String refreshTokenString;

    setUp(() async {
      refreshTokenString = (await authenticationServer.authenticate(
              user1["username"],
              user1["password"],
              "com.stablekernel.app1",
              "kilimanjaro"))
          .refreshToken;
    });

    test("Client omits authorization header", () async {
      var req = client.request("/auth/token")
        ..formData = {
          "refresh_token": refreshTokenString,
          "grant_type": "refresh_token"
        };

      var resToken = await req.post();
      expect(resToken, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential client has malformed authorization header", () async {
      var req = client.request("/auth/token")
        ..addHeader("Authorization", "Basic ")
        ..formData = {
          "refresh_token": refreshTokenString,
          "grant_type": "refresh_token"
        };

      var resToken = await req.post();
      expect(resToken, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential client has wrong secret", () async {
      var resp = await refreshResponse("com.stablekernel.app1", "notright",
          {"refresh_token": refreshTokenString});
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential client can't be used as a public client", () async {
      var resp = await refreshResponse(
          "com.stablekernel.app1", "", {"refresh_token": refreshTokenString});
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential Client ID doesn't exist", () async {
      var resp = await refreshResponse("com.stablekernel.app123", "foo",
          {"refresh_token": refreshTokenString});
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test("client id is different than one that generated token", () async {
      var resp = await refreshResponse("com.stablekernel.app2", "fuji",
          {"refresh_token": refreshTokenString});
      expect(resp, hasResponse(400, {"error": "invalid_grant"}));
    });
  });

  group("Authorization Header Failure Cases (authorization_code grant_type)",
      () {
    String code;

    setUp(() async {
      code = (await authenticationServer.authenticateForCode(user1["username"],
              user1["password"], "com.stablekernel.redirect"))
          .code;
    });

    test("Client omits authorization header", () async {
      var req = client.request("/auth/token")
        ..formData = {"code": code, "grant_type": "authorization_code"};

      var resToken = await req.post();
      expect(resToken, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential client has malformed authorization header", () async {
      var req = client.request("/auth/token")
        ..addHeader("Authorization", "Basic ")
        ..formData = {"code": code, "grant_type": "authorization_code"};

      var resToken = await req.post();
      expect(resToken, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential client has wrong secret", () async {
      var resp =
          await exchangeResponse("com.stablekernel.redirect", "notright", code);
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential client can't be used as a public client", () async {
      var resp = await exchangeResponse("com.stablekernel.redirect", "", code);
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test("Confidential Client ID doesn't exist", () async {
      var resp = await exchangeResponse("com.stablekernel.app123", "foo", code);
      expect(resp, hasResponse(400, {"error": "invalid_client"}));
    });

    test("client id is different than one that generated token", () async {
      var resp = await exchangeResponse(
          "com.stablekernel.redirect2", "gibraltar", code);
      expect(resp, hasResponse(400, {"error": "invalid_grant"}));
    });
  });

  group("Scope failure cases", () {
    test("Try to add scope to code exchange is invalid_request", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.scoped",
          requestedScopes: [new AuthScope("user")]);

      var m = {
        "grant_type": "authorization_code",
        "code": Uri.encodeQueryComponent(code.code),
        "scope": "other_scope"
      };

      var req = client.clientAuthenticatedRequest("/auth/token",
          clientID: "com.stablekernel.scoped", clientSecret: "kilimanjaro")
        ..formData = m;

      var res = await req.post();

      expect(res, hasResponse(400, {"error": "invalid_request"}));
    });

    test("Malformed scope is invalid_scope error", () async {
      var m = new Map<String, String>.from(user1);
      m["scope"] = "\"user";

      var res =
        await tokenResponse("com.stablekernel.scoped", "kilimanjaro", m);
      expect(res, hasResponse(400, {"error": "invalid_scope"}));
    });

    test("Malformed refresh scope is invalid_scope error", () async {
      var m = new Map<String, String>.from(user1);
      m["scope"] = "user other_scope";

      var resToken =
        await tokenResponse("com.stablekernel.scoped", "kilimanjaro", m);

      var refreshMap = refreshTokenMapFromTokenResponse(resToken);
      refreshMap["scope"] = "\"user";
      var resRefresh = await refreshResponse("com.stablekernel.scoped",
          "kilimanjaro", refreshMap);
      expect(resRefresh, hasResponse(400, {"error": "invalid_scope"}));
    });

    test("Invalid scope for client is invalid_scope error", () async {
      var m = new Map<String, String>.from(user1);
      m["scope"] = "not_valid";

      var res =
        await tokenResponse("com.stablekernel.scoped", "kilimanjaro", m);
      expect(res, hasResponse(400, {"error": "invalid_scope"}));
    });
  });

  group("Documentation", () {
    Map<String, APIOperation> operations;
    setUpAll(() async {
      final context = new APIDocumentContext(new APIDocument()..components = new APIComponents());
      final authServer = new AuthServer(new InMemoryAuthStorage());
      authServer.documentComponents(context);
      AuthController ac = new AuthController(authServer);
      ac.prepare();
      operations = ac.documentOperations(context, new APIPath());
      await context.finalize();
    });

    test("Has POST operation", () {
      expect(operations, {
        "post": isNotNull
      });
    });

    test("POST has body parameteters for username, password, refresh_token, scope, code, grant_type", () {
      final op = operations["post"];
      expect(op.parameters.length, 0);
      expect(op.requestBody.isRequired, true);

      final content = op.requestBody.content["application/x-www-form-urlencoded"];
      expect(content, isNotNull);

      expect(content.schema.type, APIType.object);
      expect(content.schema.properties.length, 6);
      expect(content.schema.properties["refresh_token"].type, APIType.string);
      expect(content.schema.properties["scope"].type, APIType.string);
      expect(content.schema.properties["code"].type, APIType.string);
      expect(content.schema.properties["grant_type"].type, APIType.string);
      expect(content.schema.properties["username"].type, APIType.string);
      expect(content.schema.properties["password"].type, APIType.string);

      expect(content.schema.properties["password"].format, "password");
      expect(content.schema.required, ["grant_type"]);
    });

    test("POST requires client authorization", () {
      expect(operations["post"].security.length, 1);
      expect(operations["post"].security.first.requirements, {"oauth2-client-authentication": []});
    });

    test("Responses", () {
      expect(operations["post"].responses.length, 2);

      expect(operations["post"].responses["200"].content["application/json"].schema.type, APIType.object);
      expect(operations["post"].responses["200"].content["application/json"].schema.properties["access_token"].type, APIType.string);
      expect(operations["post"].responses["200"].content["application/json"].schema.properties["refresh_token"].type, APIType.string);
      expect(operations["post"].responses["200"].content["application/json"].schema.properties["expires_in"].type, APIType.integer);
      expect(operations["post"].responses["200"].content["application/json"].schema.properties["token_type"].type, APIType.string);
      expect(operations["post"].responses["200"].content["application/json"].schema.properties["scope"].type, APIType.string);

      expect(operations["post"].responses["400"].content["application/json"].schema.type, APIType.object);
      expect(operations["post"].responses["400"].content["application/json"].schema.properties["error"].type, APIType.string);

    });
  });
}

Map<String, String> substituteUser(Map<String, String> initial,
    {String username, String password}) {
  var m = new Map<String, String>.from(initial);

  if (username != null) {
    m["username"] = username;
  }

  if (password != null) {
    m["password"] = password;
  }
  return m;
}

Map<String, String> refreshTokenMapFromTokenResponse(TestResponse resp) {
  return {"refresh_token": resp.asMap["refresh_token"] as String};
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

dynamic get bearerTokenMatcher => {
      "access_token": hasLength(greaterThan(0)),
      "refresh_token": hasLength(greaterThan(0)),
      "expires_in": greaterThan(3500),
      "token_type": "bearer"
    };

dynamic bearerTokenMatcherWithScope(String scope) {
  return {
    "access_token": hasLength(greaterThan(0)),
    "refresh_token": hasLength(greaterThan(0)),
    "expires_in": greaterThan(3500),
    "token_type": "bearer",
    "scope": scope
  };
}

dynamic get bearerTokenWithoutRefreshMatcher => partial({
      "access_token": hasLength(greaterThan(0)),
      "refresh_token": isNotPresent,
      "expires_in": greaterThan(3500),
      "token_type": "bearer"
    });

dynamic hasAuthResponse(int statusCode, dynamic body) =>
    hasResponse(statusCode, body, headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "content-encoding": "gzip",
      "pragma": "no-cache",
      "x-frame-options": isString,
      "x-xss-protection": isString,
      "x-content-type-options": isString,
      "content-length": greaterThan(0)
    });
