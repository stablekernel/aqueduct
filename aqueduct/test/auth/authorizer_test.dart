import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  InMemoryAuthStorage delegate;
  AuthServer authServer;
  HttpServer server;
  String accessToken;
  String expiredErrorToken;

  setUp(() async {
    delegate = InMemoryAuthStorage();
    delegate.createUsers(1);

    authServer = AuthServer(delegate);

    accessToken = (await authServer.authenticate(
            delegate.users[1].username,
            InMemoryAuthStorage.defaultPassword,
            "com.stablekernel.app1",
            "kilimanjaro"))
        .accessToken;
    expiredErrorToken = (await authServer.authenticate(
            delegate.users[1].username,
            InMemoryAuthStorage.defaultPassword,
            "com.stablekernel.app1",
            "kilimanjaro",
            expiration: const Duration(seconds: 0)))
        .accessToken;
  });

  tearDown(() async {
    await server?.close();
  });

  group("Bearer Token", () {
    test("No bearer token returns 401", () async {
      var authorizer = Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000");
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Malformed authorization bearer header returns 400", () async {
      var authorizer = Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.authorizationHeader: "Notbearer"});
      expect(res.statusCode, 400);
      expect(json.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test(
        "Malformed, but has credential identifier, authorization bearer header returns 400",
        () async {
      var authorizer = Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.authorizationHeader: "Bearer "});
      expect(res.statusCode, 400);
      expect(json.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test("Invalid bearer token returns 401", () async {
      var authorizer = Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer 1234567890asdfghjkl"
      });
      expect(res.statusCode, 401);
    });

    test("Expired bearer token returns 401", () async {
      var authorizer = Authorizer.bearer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $expiredErrorToken"
      });
      expect(res.statusCode, 401);
    });

    test("Valid bearer token returns authorization object", () async {
      var authorizer = Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.authorizationHeader: "Bearer $accessToken"});
      expect(res.statusCode, 200);
      expect(json.decode(res.body), {
        "clientID": "com.stablekernel.app1",
        "resourceOwnerIdentifier": 1,
        "credentials": null
      });
    });
  });

  group("Basic Credentials", () {
    test("No basic auth header returns 401", () async {
      var authorizer = Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000");
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Malformed basic authorization header returns 400", () async {
      var authorizer = Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.authorizationHeader: "Notright"});
      expect(res.statusCode, 400);
      expect(json.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test("Basic authorization, but empty, header returns 400", () async {
      var authorizer = Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.authorizationHeader: "Basic "});
      expect(res.statusCode, 400);
      expect(json.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test(
        "Basic authorization, but bad data after Basic identifier, header returns 400",
        () async {
      var authorizer = Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.authorizationHeader: "Basic asasd"});
      expect(res.statusCode, 400);
      expect(json.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test("Invalid client id returns 401", () async {
      var authorizer = Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader:
            "Basic ${const Base64Encoder().convert("abcd:kilimanjaro".codeUnits)}"
      });
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Invalid client secret returns 401", () async {
      var authorizer = Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader:
            "Basic ${const Base64Encoder().convert("com.stablekernel.app1:foobar".codeUnits)}"
      });
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Valid client ID returns 200 with authorization", () async {
      var authorizer = Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader:
            "Basic ${const Base64Encoder().convert("com.stablekernel.app1:kilimanjaro".codeUnits)}"
      });
      expect(res.statusCode, 200);
      expect(json.decode(res.body), {
        "clientID": "com.stablekernel.app1",
        "resourceOwnerIdentifier": null,
        "credentials": "com.stablekernel.app1:kilimanjaro"
      });
    });

    test("Public client can only be authorized with no password", () async {
      var authorizer = Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader:
            "Basic ${const Base64Encoder().convert("com.stablekernel.public:".codeUnits)}"
      });
      expect(res.statusCode, 200);
      expect(json.decode(res.body), {
        "clientID": "com.stablekernel.public",
        "resourceOwnerIdentifier": null,
        "credentials": "com.stablekernel.public:"
      });

      res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader:
            "Basic ${const Base64Encoder().convert("com.stablekernel.public:password".codeUnits)}"
      });
      expect(res.statusCode, 401);
    });

    test("Confidential client can never be authorized with no password",
        () async {
      var authorizer = Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader:
            "Basic ${const Base64Encoder().convert("com.stablekernel.app1:".codeUnits)}"
      });
      expect(res.statusCode, 401);

      res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader:
            "Basic ${const Base64Encoder().convert("com.stablekernel.app1".codeUnits)}"
      });
      expect(res.statusCode, 400);
    });
  });

  group("Scoping", () {
    String userScopedAccessToken;
    String userAndOtherScopedAccessToken;
    String userReadOnlyScopedAccessToken;
    String userAndOtherReadOnlyScopedAccessToken;

    setUp(() async {
      userReadOnlyScopedAccessToken = (await authServer.authenticate(
              delegate.users[1].username,
              InMemoryAuthStorage.defaultPassword,
              "com.stablekernel.scoped",
              "kilimanjaro",
              requestedScopes: [AuthScope("user.readonly")]))
          .accessToken;

      userScopedAccessToken = (await authServer.authenticate(
              delegate.users[1].username,
              InMemoryAuthStorage.defaultPassword,
              "com.stablekernel.scoped",
              "kilimanjaro",
              requestedScopes: [AuthScope("user")]))
          .accessToken;

      userAndOtherScopedAccessToken = (await authServer.authenticate(
              delegate.users[1].username,
              InMemoryAuthStorage.defaultPassword,
              "com.stablekernel.scoped",
              "kilimanjaro",
              requestedScopes: [AuthScope("user"), AuthScope("other_scope")]))
          .accessToken;

      userAndOtherReadOnlyScopedAccessToken = (await authServer.authenticate(
              delegate.users[1].username,
              InMemoryAuthStorage.defaultPassword,
              "com.stablekernel.scoped",
              "kilimanjaro",
              requestedScopes: [
            AuthScope("user"),
            AuthScope("other_scope.readonly")
          ]))
          .accessToken;
    });

    test("Single scoped authorizer, valid single scoped token pass authorizer",
        () async {
      var authorizer = Authorizer.bearer(authServer, scopes: ["user"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(json.decode(res.body)["scopes"], ["user"]);
    });

    test(
        "Single scoped authorizer requiring less privileges, valid higher privileged token pass authorizer",
        () async {
      var authorizer = Authorizer.bearer(authServer, scopes: ["user.readonly"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(json.decode(res.body)["scopes"], ["user"]);
    });

    test(
        "Single scoped authorizer, multiple scoped valid token pass authorizer",
        () async {
      var authorizer = Authorizer.bearer(authServer, scopes: ["user"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $userAndOtherScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(json.decode(res.body)["scopes"], ["user", "other_scope"]);
    });

    test("Multi-scoped authorizer, multi-scoped valid token pass authorizer",
        () async {
      var authorizer =
          Authorizer.bearer(authServer, scopes: ["user", "other_scope"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $userAndOtherScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(json.decode(res.body)["scopes"], ["user", "other_scope"]);
    });

    test(
        "Multi-scoped authorizer, multi-scoped valid token with more privilegs than necessary pass authorizer",
        () async {
      var authorizer = Authorizer.bearer(authServer,
          scopes: ["user:foo", "other_scope.readonly"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $userAndOtherScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(json.decode(res.body)["scopes"], ["user", "other_scope"]);
    });

    // non-passing

    test(
        "Singled scoped authorizer requiring more privileges does not pass authorizer",
        () async {
      var authorizer = Authorizer.bearer(authServer, scopes: ["user"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $userReadOnlyScopedAccessToken"
      });
      expect(res.statusCode, 403);
      expect(json.decode(res.body),
          {"error": "insufficient_scope", "scope": "user"});
    });

    test(
        "Singled scoped authorized requiring different privileges does not pass authorizer",
        () async {
      var authorizer = Authorizer.bearer(authServer, scopes: ["other_scope"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 403);
      expect(json.decode(res.body),
          {"error": "insufficient_scope", "scope": "other_scope"});
    });

    test("Multi-scoped authorizer, single scoped token do not pass authorizer",
        () async {
      var authorizer =
          Authorizer.bearer(authServer, scopes: ["user", "other_scope"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 403);
      expect(json.decode(res.body),
          {"error": "insufficient_scope", "scope": "user other_scope"});
    });

    test(
        "Multi-scoped authorizer, multi-scoped token but with different scopes do not pass authorzer",
        () async {
      var authorizer =
          Authorizer.bearer(authServer, scopes: ["other", "something_else"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 403);
      expect(json.decode(res.body),
          {"error": "insufficient_scope", "scope": "other something_else"});
    });

    test(
        "Multi-scoped authorizer, multi-scoped token but with less privileges on one scope do not pass authorizer",
        () async {
      var authorizer =
          Authorizer.bearer(authServer, scopes: ["user", "other_scope"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader:
            "Bearer $userAndOtherReadOnlyScopedAccessToken"
      });
      expect(res.statusCode, 403);
      expect(json.decode(res.body),
          {"error": "insufficient_scope", "scope": "user other_scope"});
    });
  });

  group("Exceptions", () {
    test("Actual status code returned for exception in basic authorizer",
        () async {
      var anotherAuthServer = AuthServer(CrashingStorage());
      server = await enableAuthorizer(Authorizer.basic(anotherAuthServer));
      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.authorizationHeader:
            "Basic ${const Base64Encoder().convert("a:".codeUnits)}"
      });
      expect(res.statusCode, 504);
    });

    test("Actual status code returned for exception in bearer authorizer",
        () async {
      var anotherAuthServer = AuthServer(CrashingStorage());
      server = await enableAuthorizer(Authorizer.bearer(anotherAuthServer));
      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.authorizationHeader: "Bearer axy"});
      expect(res.statusCode, 504);
    });
  });

  group("Authorization objects", () {
    test("Authorization has scope for exact scope", () {
      var auth = Authorization("id", 1, null, scopes: [AuthScope("a")]);
      expect(auth.isAuthorizedForScope("a"), true);
    });

    test("Authorization has scope for scope with more privileges", () {
      var auth = Authorization("id", 1, null, scopes: [AuthScope("a")]);
      expect(auth.isAuthorizedForScope("a:foo"), true);
    });

    test("Authorization does not have access to different scope", () {
      var auth = Authorization("id", 1, null, scopes: [AuthScope("a")]);
      expect(auth.isAuthorizedForScope("b"), false);
    });

    test("Authorization does not have access to higher privileged scope",
        () async {
      var auth = Authorization("id", 1, null, scopes: [AuthScope("a:foo")]);
      expect(auth.isAuthorizedForScope("a"), false);
    });
  });
}

Future<HttpServer> enableAuthorizer(Authorizer authorizer) async {
  var router = Router();
  router.route("/").link(() => authorizer).linkFunction(respond);
  router.didAddToChannel();

  var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8000);
  server.map((httpReq) => Request(httpReq)).listen((r) {
    router.receive(r);
  });

  return server;
}

Future<RequestOrResponse> respond(Request req) async {
  var map = {
    "clientID": req.authorization.clientID,
    "resourceOwnerIdentifier": req.authorization.ownerID,
    "credentials": req.authorization.credentials?.toString()
  };

  if ((req.authorization.scopes?.length ?? 0) > 0) {
    map["scopes"] = req.authorization.scopes.map((s) => s.toString()).toList();
  }

  return Response.ok(map);
}

class CrashingStorage extends InMemoryAuthStorage {
  @override
  Future<AuthToken> getToken(AuthServer server,
      {String byAccessToken, String byRefreshToken}) async {
    throw Response(504, null, "ok");
  }

  @override
  Future<AuthClient> getClient(AuthServer server, String id) async {
    throw Response(504, null, "ok");
  }
}
