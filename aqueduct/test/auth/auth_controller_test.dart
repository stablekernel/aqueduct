import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  HttpServer server;
  AuthServer authenticationServer;
  Router router;
  ////////////

  setUp(() async {
    var storage = InMemoryAuthStorage();
    storage.createUsers(3);
    authenticationServer = AuthServer(storage);

    router = Router();
    router
        .route("/auth/token")
        .link(() => AuthController(authenticationServer));
    router.didAddToChannel();

    server =
        await HttpServer.bind("localhost", 8888, v6Only: false, shared: false);
    server.map((req) => Request(req)).listen(router.receive);
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  ///////

  group("Success Cases: password", () {
    test("Confidental Client has all parameters including refresh_token",
        () async {
      var res = await grant("com.stablekernel.app1", "kilimanjaro", user1);

      expect(res, hasAuthResponse(200, bearerTokenMatcher));
    });

    test("Public Client has all parameters except refresh_token", () async {
      var res = await grant("com.stablekernel.public", "", user1);

      expect(res, hasAuthResponse(200, bearerTokenWithoutRefreshMatcher));
    });

    test(
        "Can authenticate with resource owner grant with client ID that has redirect url",
        () async {
      var res = await grant("com.stablekernel.redirect", "mckinley", user1);
      expect(res, hasAuthResponse(200, bearerTokenMatcher));
    });

    test("Can be scoped", () async {
      var m = Map<String, String>.from(user1);
      m["scope"] = "user";

      var res = await grant("com.stablekernel.scoped", "kilimanjaro", m);
      expect(res, hasAuthResponse(200, bearerTokenMatcherWithScope("user")));

      m["scope"] = "user other_scope";
      res = await grant("com.stablekernel.scoped", "kilimanjaro", m);
      expect(
          res,
          hasAuthResponse(
              200, bearerTokenMatcherWithScope("user other_scope")));
    });
  });

  group("Success Cases: refresh_token", () {
    test(
        "Confidental Client gets a new access token, retains same access token",
        () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro", user1);

      var resRefresh = await refresh("com.stablekernel.app1", "kilimanjaro",
          refreshTokenMapFromTokenResponse(resToken));
      expect(
          resRefresh,
          hasResponse(200, body: {
            "access_token": isString,
            "refresh_token":
                resToken.body.as<Map<String, dynamic>>()["refresh_token"],
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

    test("If token is scoped and scope is omitted, get same token back",
        () async {
      var m = Map<String, String>.from(user1);
      m["scope"] = "user";

      var resToken = await grant("com.stablekernel.scoped", "kilimanjaro", m);

      var resRefresh = await refresh("com.stablekernel.scoped", "kilimanjaro",
          refreshTokenMapFromTokenResponse(resToken));
      expect(
          resRefresh,
          hasResponse(200, body: {
            "access_token": isString,
            "refresh_token":
                resToken.body.as<Map<String, dynamic>>()["refresh_token"],
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

    test("If token is scoped and scope is part of request, get rescoped token",
        () async {
      var m = Map<String, String>.from(user1);
      m["scope"] = "user other_scope";

      var resToken = await grant("com.stablekernel.scoped", "kilimanjaro", m);

      var refreshMap = refreshTokenMapFromTokenResponse(resToken);
      refreshMap["scope"] = "user";
      var resRefresh =
          await refresh("com.stablekernel.scoped", "kilimanjaro", refreshMap);
      expect(
          resRefresh,
          hasResponse(200, body: {
            "access_token": isString,
            "refresh_token":
                resToken.body.as<Map<String, dynamic>>()["refresh_token"],
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
      var res =
          await exchange("com.stablekernel.redirect", "mckinley", code.code);
      expect(res, hasAuthResponse(200, bearerTokenMatcher));
    });

    test("If code is scoped, token has same scope", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.scoped",
          requestedScopes: [AuthScope("user")]);

      var res =
          await exchange("com.stablekernel.scoped", "kilimanjaro", code.code);
      expect(res, hasAuthResponse(200, bearerTokenMatcherWithScope("user")));
    });
  });

  group("username Failure Cases", () {
    test("Username does not exist yields 400", () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro",
          substituteUser(user1, username: "foobar"));
      expect(resToken, hasResponse(400, body: {"error": "invalid_grant"}));
    });

    test("Username is empty returns 400", () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro",
          substituteUser(user1, username: ""));
      expect(resToken, hasResponse(400, body: {"error": "invalid_grant"}));
    });

    test("Username is missing returns 400", () async {
      var resToken = await grant(
          "com.stablekernel.app1", "kilimanjaro", {"password": "doesntmatter"});
      expect(resToken, hasResponse(400, body: {"error": "invalid_request"}));
    });

    test("Username is repeated returns 400", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongUsername = Uri.encodeQueryComponent("!@#kjasd");
      final client = Agent.onPort(8888)
        ..headers["authorization"] =
            "Basic ${base64.encode("com.stablekernel.app1:kilimanjaro".codeUnits)}";

      var req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&username=$encodedWrongUsername&password=$encodedPassword&grant_type=password")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasResponse(400, body: {"error": "invalid_request"}));

      req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedWrongUsername&username=$encodedUsername&password=$encodedPassword&grant_type=password")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasResponse(400, body: {"error": "invalid_request"}));
    });
  });

  group("password Failure Cases", () {
    test("password is incorrect yields 400", () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro",
          substituteUser(user1, password: "!@#\$%^&*()"));
      expect(resToken, hasResponse(400, body: {"error": "invalid_grant"}));
    });

    test("password is empty returns 400", () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro",
          substituteUser(user1, password: ""));
      expect(resToken, hasResponse(400, body: {"error": "invalid_grant"}));
    });

    test("password is missing returns 400", () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro",
          {"username": "${user1["username"]}"});
      expect(resToken, hasResponse(400, body: {"error": "invalid_request"}));
    });

    test("password is repeated returns 400", () async {
      var encodedUsername = Uri.encodeQueryComponent(user1["username"]);
      var encodedPassword = Uri.encodeQueryComponent(user1["password"]);
      var encodedWrongPassword = Uri.encodeQueryComponent("!@#kjasd");

      final client = Agent.onPort(8888)
        ..headers["authorization"] =
            "Basic ${base64.encode("com.stablekernel.app1:kilimanjaro".codeUnits)}";

      var req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedPassword&password=$encodedWrongPassword&grant_type=password")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasResponse(400, body: {"error": "invalid_request"}));

      req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8.encode(
            "username=$encodedUsername&password=$encodedWrongPassword&password=$encodedPassword&grant_type=password")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasResponse(400, body: {"error": "invalid_request"}));
    });
  });

  group("code Failure Cases", () {
    test("code is invalid (not issued)", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.redirect");
      var res = await exchange(
          "com.stablekernel.redirect", "mckinley", "a${code.code}");
      expect(res, hasResponse(400, body: {"error": "invalid_grant"}));
    });

    test("code is missing", () async {
      var res = await exchange("com.stablekernel.redirect", "mckinley", null);
      expect(res, hasResponse(400, body: {"error": "invalid_request"}));
    });

    test("code is empty", () async {
      var res = await exchange("com.stablekernel.redirect", "mckinley", "");
      expect(res, hasResponse(400, body: {"error": "invalid_grant"}));
    });

    test("code is duplicated", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.redirect");
      var encodedCode = Uri.encodeQueryComponent(code.code);

      final client = Agent.onPort(8888)
        ..setBasicAuthorization("com.stablekernel.redirect", "mckinley");

      var req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8
            .encode("code=$encodedCode&code=abcd&grant_type=authorization_code")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasResponse(400, body: {"error": "invalid_request"}));

      req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8
            .encode("code=abcd&code=$encodedCode&grant_type=authorization_code")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasResponse(400, body: {"error": "invalid_request"}));
    });

    test("code is from a different client", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.redirect");
      var res =
          await exchange("com.stablekernel.redirect2", "gibraltar", code.code);
      expect(res, hasResponse(400, body: {"error": "invalid_grant"}));
    });
  });

  group("grant_type Failure Cases", () {
    Agent client;

    setUp(() {
      client = Agent.onPort(8888)
        ..setBasicAuthorization("com.stablekernel.app1", "kilimanjaro");
    });

    test("Unknown grant_type", () async {
      var req = client.request("/auth/token")
        ..contentType = ContentType("application", "x-www-form-urlencoded")
        ..body = {
          "username": user1["username"],
          "password": user1["password"],
          "grant_type": "nonsense"
        };

      var res = await req.post();

      expect(res, hasResponse(400, body: {"error": "unsupported_grant_type"}));
    });

    test("Missing grant_type", () async {
      var req = client.request("/auth/token")
        ..contentType = ContentType("application", "x-www-form-urlencoded")
        ..body = {"username": user1["username"], "password": user1["password"]};

      var res = await req.post();

      expect(res, hasResponse(400, body: {"error": "invalid_request"}));
    });

    test("Duplicate grant_type", () async {
      client.setBasicAuthorization("com.stablekernel.redirect", "mckinley");

      var req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8.encode(
            "code=abcd&grant_type=authorization_code&grant_type=whatever")
        ..contentType = ContentType("application", "x-www-form-urlencoded");

      var res = await req.post();
      expect(res, hasResponse(400, body: {"error": "invalid_request"}));

      req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8.encode(
            "grant_type=authorization_code&code=abcd&grant_type=whatever")
        ..contentType = ContentType("application", "x-www-form-urlencoded");

      res = await req.post();
      expect(res, hasResponse(400, body: {"error": "invalid_request"}));
    });
  });

  group("refresh_token Failure Cases", () {
    Agent client;

    setUp(() {
      client = Agent.onPort(8888)
        ..setBasicAuthorization("com.stablekernel.app1", "kilimanjaro");
    });

    test("refresh_token is omitted", () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro", user1);

      var m = refreshTokenMapFromTokenResponse(resToken);
      m.remove("refresh_token");
      var resRefresh = await refresh("com.stablekernel.app1", "kilimanjaro", m);
      expect(resRefresh, hasResponse(400, body: {"error": "invalid_request"}));
    });

    test("refresh_token appears more than once", () async {
      final Map<String, dynamic> grantMap =
          (await grant("com.stablekernel.app1", "kilimanjaro", user1))
              .body
              .as();
      final refreshToken =
          Uri.encodeQueryComponent(grantMap["refresh_token"] as String);

      var req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8.encode(
            "refresh_token=$refreshToken&refresh_token=abcdefg&grant_type=refresh_token")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      var resp = await req.post();
      expect(resp, hasResponse(400, body: {"error": "invalid_request"}));

      req = client.request("/auth/token")
        ..encodeBody = false
        ..body = utf8.encode(
            "refresh_token=abcdefg&refresh_token=$refreshToken&grant_type=refresh_token")
        ..contentType = ContentType("application", "x-www-form-urlencoded");
      resp = await req.post();
      expect(resp, hasResponse(400, body: {"error": "invalid_request"}));
    });

    test("refresh_token is empty", () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro", user1);

      var m = refreshTokenMapFromTokenResponse(resToken);
      m["refresh_token"] = "";
      var resRefresh = await refresh("com.stablekernel.app1", "kilimanjaro", m);
      expect(resRefresh, hasResponse(400, body: {"error": "invalid_grant"}));
    });

    test("Refresh token doesn't exist (was not issued)", () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro", user1);

      var m = refreshTokenMapFromTokenResponse(resToken);
      m["refresh_token"] = "${m["refresh_token"]}a";
      var resRefresh = await refresh("com.stablekernel.app1", "kilimanjaro", m);
      expect(resRefresh, hasResponse(400, body: {"error": "invalid_grant"}));
    });

    test("Client id/secret pair is different than original", () async {
      var resToken = await grant("com.stablekernel.app1", "kilimanjaro", user1);

      var resRefresh = await refresh("com.stablekernel.app2", "fuji",
          refreshTokenMapFromTokenResponse(resToken));
      expect(resRefresh, hasResponse(400, body: {"error": "invalid_grant"}));
    });
  });

  group("Authorization Header Failure Cases (password grant_type)", () {
    Agent client;

    setUp(() {
      client = Agent.onPort(8888);
    });

    test("Client omits authorization header", () async {
      var m = Map<String, String>.from(user1);
      m["grant_type"] = "password";
      var req = client.request("/auth/token")
        ..contentType = ContentType("application", "x-www-form-urlencoded")
        ..body = m;

      var resToken = await req.post();
      expect(resToken, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential client has malformed authorization header", () async {
      var m = Map<String, String>.from(user1);
      m["grant_type"] = "password";
      var req = client.request("/auth/token")
        ..headers["Authorization"] = "Basic "
        ..contentType = ContentType("application", "x-www-form-urlencoded")
        ..body = m;

      var resToken = await req.post();
      expect(resToken, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential client has wrong secret", () async {
      var resp = await grant("com.stablekernel.app1", "notright", user1);
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test(
        "Confidential client can't be used as a public client (i.e. without secret)",
        () async {
      var resp = await grant("com.stablekernel.app1", "", user1);
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Public client has wrong secret (any secret)", () async {
      var resp = await grant("com.stablekernel.public", "foo", user1);
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential Client ID doesn't exist", () async {
      var resp = await grant("com.stablekernel.app123", "foo", user1);
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Public Client ID doesn't exist", () async {
      var resp = await grant("com.stablekernel.app123", "", user1);
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });
  });

  group("Authorization Header Failure Cases (refresh_token grant_type)", () {
    String refreshTokenString;
    Agent client;

    setUp(() async {
      client = Agent.onPort(8888);

      refreshTokenString = (await authenticationServer.authenticate(
              user1["username"],
              user1["password"],
              "com.stablekernel.app1",
              "kilimanjaro"))
          .refreshToken;
    });

    test("Client omits authorization header", () async {
      var req = client.request("/auth/token")
        ..contentType = ContentType("application", "x-www-form-urlencoded")
        ..body = {
          "refresh_token": refreshTokenString,
          "grant_type": "refresh_token"
        };

      var resToken = await req.post();
      expect(resToken, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential client has malformed authorization header", () async {
      var req = client.request("/auth/token")
        ..headers["Authorization"] = "Basic "
        ..contentType = ContentType("application", "x-www-form-urlencoded")
        ..body = {
          "refresh_token": refreshTokenString,
          "grant_type": "refresh_token"
        };

      var resToken = await req.post();
      expect(resToken, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential client has wrong secret", () async {
      var resp = await refresh("com.stablekernel.app1", "notright",
          {"refresh_token": refreshTokenString});
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential client can't be used as a public client", () async {
      var resp = await refresh(
          "com.stablekernel.app1", "", {"refresh_token": refreshTokenString});
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential Client ID doesn't exist", () async {
      var resp = await refresh("com.stablekernel.app123", "foo",
          {"refresh_token": refreshTokenString});
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("client id is different than one that generated token", () async {
      var resp = await refresh("com.stablekernel.app2", "fuji",
          {"refresh_token": refreshTokenString});
      expect(resp, hasResponse(400, body: {"error": "invalid_grant"}));
    });
  });

  group("Authorization Header Failure Cases (authorization_code grant_type)",
      () {
    String code;
    Agent client;

    setUp(() async {
      client = Agent.onPort(8888);

      code = (await authenticationServer.authenticateForCode(user1["username"],
              user1["password"], "com.stablekernel.redirect"))
          .code;
    });

    test("Client omits authorization header", () async {
      var req = client.request("/auth/token")
        ..contentType = ContentType("application", "x-www-form-urlencoded")
        ..body = {"code": code, "grant_type": "authorization_code"};

      var resToken = await req.post();
      expect(resToken, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential client has malformed authorization header", () async {
      var req = client.request("/auth/token")
        ..headers["Authorization"] = "Basic "
        ..contentType = ContentType("application", "x-www-form-urlencoded")
        ..body = {"code": code, "grant_type": "authorization_code"};

      var resToken = await req.post();
      expect(resToken, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential client has wrong secret", () async {
      var resp = await exchange("com.stablekernel.redirect", "notright", code);
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential client can't be used as a public client", () async {
      var resp = await exchange("com.stablekernel.redirect", "", code);
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("Confidential Client ID doesn't exist", () async {
      var resp = await exchange("com.stablekernel.app123", "foo", code);
      expect(resp, hasResponse(400, body: {"error": "invalid_client"}));
    });

    test("client id is different than one that generated token", () async {
      var resp =
          await exchange("com.stablekernel.redirect2", "gibraltar", code);
      expect(resp, hasResponse(400, body: {"error": "invalid_grant"}));
    });
  });

  group("Scope failure cases", () {
    test("Try to add scope to code exchange is invalid_request", () async {
      var code = await authenticationServer.authenticateForCode(
          user1["username"], user1["password"], "com.stablekernel.scoped",
          requestedScopes: [AuthScope("user")]);

      var m = {
        "grant_type": "authorization_code",
        "code": Uri.encodeQueryComponent(code.code),
        "scope": "other_scope"
      };

      final client = Agent.onPort(8888)
        ..setBasicAuthorization("com.stablekernel.scoped", "kilimanjaro");
      var req = client.request("/auth/token")
        ..contentType = ContentType("application", "x-www-form-urlencoded")
        ..body = m;

      var res = await req.post();

      expect(res, hasResponse(400, body: {"error": "invalid_request"}));
    });

    test("Malformed scope is invalid_scope error", () async {
      var m = Map<String, String>.from(user1);
      m["scope"] = "\"user";

      var res = await grant("com.stablekernel.scoped", "kilimanjaro", m);
      expect(res, hasResponse(400, body: {"error": "invalid_scope"}));
    });

    test("Malformed refresh scope is invalid_scope error", () async {
      var m = Map<String, String>.from(user1);
      m["scope"] = "user other_scope";

      var resToken = await grant("com.stablekernel.scoped", "kilimanjaro", m);

      var refreshMap = refreshTokenMapFromTokenResponse(resToken);
      refreshMap["scope"] = "\"user";
      var resRefresh =
          await refresh("com.stablekernel.scoped", "kilimanjaro", refreshMap);
      expect(resRefresh, hasResponse(400, body: {"error": "invalid_scope"}));
    });

    test("Invalid scope for client is invalid_scope error", () async {
      var m = Map<String, String>.from(user1);
      m["scope"] = "not_valid";

      var res = await grant("com.stablekernel.scoped", "kilimanjaro", m);
      expect(res, hasResponse(400, body: {"error": "invalid_scope"}));
    });
  });
}

Map<String, String> substituteUser(Map<String, String> initial,
    {String username, String password}) {
  var m = Map<String, String>.from(initial);

  if (username != null) {
    m["username"] = username;
  }

  if (password != null) {
    m["password"] = password;
  }
  return m;
}

Map<String, String> refreshTokenMapFromTokenResponse(TestResponse resp) {
  return {
    "refresh_token":
        resp.body.as<Map<String, dynamic>>()["refresh_token"] as String
  };
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
    hasResponse(statusCode, body: body, headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "content-encoding": "gzip",
      "pragma": "no-cache",
      "x-frame-options": isString,
      "x-xss-protection": isString,
      "x-content-type-options": isString,
      "content-length": greaterThan(0)
    });

Future<TestResponse> grant(
    String clientID, String clientSecret, Map<String, String> form) {
  Agent client = Agent.onPort(8888)
    ..setBasicAuthorization(clientID, clientSecret);

  final m = Map<String, String>.from(form);
  m.addAll({"grant_type": "password"});

  final req = client.request("/auth/token")
    ..contentType = ContentType("application", "x-www-form-urlencoded")
    ..body = m;

  return req.post();
}

Future<TestResponse> refresh(
    String clientID, String clientSecret, Map<String, String> form) {
  Agent client = Agent.onPort(8888)
    ..setBasicAuthorization(clientID, clientSecret);

  final m = Map<String, String>.from(form);
  m.addAll({"grant_type": "refresh_token"});

  final req = client.request("/auth/token")
    ..contentType = ContentType("application", "x-www-form-urlencoded")
    ..body = m;

  return req.post();
}

Future<TestResponse> exchange(
    String clientID, String clientSecret, String code) {
  Agent client = Agent.onPort(8888)
    ..setBasicAuthorization(clientID, clientSecret);

  var m = {"grant_type": "authorization_code"};

  if (code != null) {
    m["code"] = Uri.encodeQueryComponent(code);
  }

  var req = client.request("/auth/token")
    ..contentType = ContentType("application", "x-www-form-urlencoded")
    ..body = m;

  return req.post();
}
