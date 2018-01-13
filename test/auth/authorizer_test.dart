import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:io';
import '../helpers.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  Controller.letUncaughtExceptionsEscape = true;
  InMemoryAuthStorage delegate;
  AuthServer authServer;
  HttpServer server;
  String accessToken;
  String expiredErrorToken;

  setUp(() async {
    delegate = new InMemoryAuthStorage();
    delegate.createUsers(1);

    authServer = new AuthServer(delegate);

    accessToken = (await authServer.authenticate(
            delegate.users[1].username,
            InMemoryAuthStorage.DefaultPassword,
            "com.stablekernel.app1",
            "kilimanjaro"))
        .accessToken;
    expiredErrorToken = (await authServer.authenticate(
            delegate.users[1].username,
            InMemoryAuthStorage.DefaultPassword,
            "com.stablekernel.app1",
            "kilimanjaro",
            expiration: new Duration(seconds: 0)))
        .accessToken;
  });

  tearDown(() async {
    await server?.close();
  });

  group("Bearer Token", () {
    test("No bearer token returns 401", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000");
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Malformed authorization bearer header returns 400", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Notbearer"});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test(
        "Malformed, but has credential identifier, authorization bearer header returns 400",
        () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Bearer "});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test("Invalid bearer token returns 401", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Bearer 1234567890asdfghjkl"});
      expect(res.statusCode, 401);
    });

    test("Expired bearer token returns 401", () async {
      var authorizer = new Authorizer.bearer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Bearer $expiredErrorToken"});
      expect(res.statusCode, 401);
    });

    test("Valid bearer token returns authorization object", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Bearer $accessToken"});
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body),
          {"clientID": "com.stablekernel.app1", "resourceOwnerIdentifier": 1, "credentials": null});
    });
  });

  group("Basic Credentials", () {
    test("No basic auth header returns 401", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000");
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Malformed basic authorization header returns 400", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Notright"});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test("Basic authorization, but empty, header returns 400", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Basic "});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test(
        "Basic authorization, but bad data after Basic identifier, header returns 400",
        () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Basic asasd"});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test("Invalid client id returns 401", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("abcd:kilimanjaro".codeUnits)}"
      });
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Invalid client secret returns 401", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.app1:foobar".codeUnits)}"
      });
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Valid client ID returns 200 with authorization", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.app1:kilimanjaro".codeUnits)}"
      });
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body), {
        "clientID": "com.stablekernel.app1",
        "resourceOwnerIdentifier": null,
        "credentials": "com.stablekernel.app1:kilimanjaro"
      });
    });

    test("Public client can only be authorized with no password", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.public:".codeUnits)}"
      });
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body), {
        "clientID": "com.stablekernel.public",
        "resourceOwnerIdentifier": null,
        "credentials": "com.stablekernel.public:"
      });

      res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.public:password".codeUnits)}"
      });
      expect(res.statusCode, 401);
    });

    test("Confidential client can never be authorized with no password",
        () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.app1:".codeUnits)}"
      });
      expect(res.statusCode, 401);

      res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.app1".codeUnits)}"
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
            InMemoryAuthStorage.DefaultPassword,
            "com.stablekernel.scoped",
            "kilimanjaro", requestedScopes: [new AuthScope("user.readonly")]))
          .accessToken;

      userScopedAccessToken = (await authServer.authenticate(
            delegate.users[1].username,
            InMemoryAuthStorage.DefaultPassword,
            "com.stablekernel.scoped",
            "kilimanjaro", requestedScopes: [new AuthScope("user")]))
          .accessToken;

      userAndOtherScopedAccessToken = (await authServer.authenticate(
            delegate.users[1].username,
            InMemoryAuthStorage.DefaultPassword,
            "com.stablekernel.scoped",
            "kilimanjaro", requestedScopes: [new AuthScope("user"), new AuthScope("other_scope")]))
          .accessToken;

      userAndOtherReadOnlyScopedAccessToken = (await authServer.authenticate(
            delegate.users[1].username,
            InMemoryAuthStorage.DefaultPassword,
            "com.stablekernel.scoped",
            "kilimanjaro", requestedScopes: [new AuthScope("user"), new AuthScope("other_scope.readonly")]))
          .accessToken;
    });

    test("Single scoped authorizer, valid single scoped token pass authorizer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["user"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body)["scopes"], ["user"]);
    });

    test("Single scoped authorizer requiring less privileges, valid higher privileged token pass authorizer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["user.readonly"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body)["scopes"], ["user"]);
    });

    test("Single scoped authorizer, multiple scoped valid token pass authorizer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["user"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userAndOtherScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body)["scopes"], ["user", "other_scope"]);
    });

    test("Multi-scoped authorizer, multi-scoped valid token pass authorizer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["user", "other_scope"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userAndOtherScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body)["scopes"], ["user", "other_scope"]);
    });

    test("Multi-scoped authorizer, multi-scoped valid token with more privilegs than necessary pass authorizer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["user:foo", "other_scope.readonly"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userAndOtherScopedAccessToken"
      });
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body)["scopes"], ["user", "other_scope"]);
    });

    // non-passing

    test("Singled scoped authorizer requiring more privileges does not pass authorizer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["user"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userReadOnlyScopedAccessToken"
      });
      expect(res.statusCode, 401);
    });

    test("Singled scoped authorized requiring different privileges does not pass authorizer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["other_scope"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 401);
    });

    test("Multi-scoped authorizer, single scoped token do not pass authorizer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["user", "other_scope"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 401);
    });

    test("Multi-scoped authorizer, multi-scoped token but with different scopes do not pass authorzer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["other", "something_else"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userScopedAccessToken"
      });
      expect(res.statusCode, 401);
    });

    test("Multi-scoped authorizer, multi-scoped token but with less privileges on one scope do not pass authorizer", () async {
      var authorizer = new Authorizer.bearer(authServer, scopes: ["user", "other_scope"]);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Bearer $userAndOtherReadOnlyScopedAccessToken"
      });
      expect(res.statusCode, 401);
    });
  });

  group("Exceptions", () {
    test("Actual status code returned for exception in basic authorizer", () async {
      var anotherAuthServer = new AuthServer(new CrashingStorage());
      server = await enableAuthorizer(new Authorizer.basic(anotherAuthServer));
      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION: "Basic ${new Base64Encoder().convert("a:".codeUnits)}"
      });
      expect(res.statusCode, 504);
    });

    test("Actual status code returned for exception in bearer authorizer", () async {
      var anotherAuthServer = new AuthServer(new CrashingStorage());
      server = await enableAuthorizer(new Authorizer.bearer(anotherAuthServer));
      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
        "Bearer axy"
      });
      expect(res.statusCode, 504);
    });
  });

  group("Authorization objects", () {
    test("Authorization has scope for exact scope", () {
      var auth = new Authorization("id", 1, null, scopes: [new AuthScope("a")]);
      expect(auth.authorizedForScope("a"), true);
    });

    test("Authorization has scope for scope with more privileges", () {
      var auth = new Authorization("id", 1, null, scopes: [new AuthScope("a")]);
      expect(auth.authorizedForScope("a:foo"), true);
    });

    test("Authorization does not have access to different scope", () {
      var auth = new Authorization("id", 1, null, scopes: [new AuthScope("a")]);
      expect(auth.authorizedForScope("b"), false);
    });

    test("Authorization does not have access to higher privileged scope", () async {
      var auth = new Authorization("id", 1, null, scopes: [new AuthScope("a:foo")]);
      expect(auth.authorizedForScope("a"), false);
    });
  });
}

Future<HttpServer> enableAuthorizer(Authorizer authorizer) async {
  var router = new Router();
  router.route("/").link(() => authorizer).link(() => new Controller(respond));
  router.prepare();

  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8000);
  server.map((httpReq) => new Request(httpReq)).listen((r) {
    router.receive(r);
  });

  return server;
}

Future<RequestOrResponse> respond(Request req) async {
  var map = {
    "clientID": req.authorization.clientID,
    "resourceOwnerIdentifier": req.authorization.resourceOwnerIdentifier,
    "credentials": req.authorization.credentials?.toString()
  };

  if ((req.authorization.scopes?.length ?? 0) > 0) {
    map["scopes"] = req.authorization.scopes;
  }

  return new Response.ok(map);
}


class CrashingStorage extends InMemoryAuthStorage {
  @override
  Future<AuthToken> fetchTokenByAccessToken(
      AuthServer server, String accessToken) async {
    throw new Response(504, null, "ok");
  }

  @override
  Future<AuthClient> fetchClientByID(AuthServer server, String id) async {
    throw new Response(504, null, "ok");
  }
}