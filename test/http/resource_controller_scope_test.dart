import 'package:aqueduct/test.dart';
import 'package:test/test.dart';
import "dart:core";
import "dart:io";
import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:mirrors';
import '../helpers.dart';

void main() {
  final app = new Application<Channel>();
  final client = new TestClient(app);
  final tokens = <String, String>{};

  setUpAll(() async {
    await app.test();
  });

  tearDownAll(() async {
    await app.stop();
  });

  test("If method has no scope restrictions (but Authorizer does), allow request if passes authorizer", () async {
    expectResponse(await client.authenticatedRequest("/level1-authorizer", accessToken: "level1").get(), 200);
  });

  test("When no Authorizer and method has scope, a 500 error is thrown", () async {
    // Log warning
    expectResponse(await client.authenticatedRequest("/no-authorizer", accessToken: "level1").put(), 500);
  });

  test("When no Authorizer and method does not have scope, request is successful", () async {
    expectResponse(await client.authenticatedRequest("/no-authorizer", accessToken: "level1").get(), 200);
  });

  group("Exact scope match", () {
    test("If token has sufficient scope for method, allow it", () async {
      expectResponse(await client.authenticatedRequest("/level1-authorizer", accessToken: "level1").put(), 200);
    });

    test("If token does not have sufficient scope for method, return 403 and include required scope in body", () async {
      fail("NEED TO UPDATE OTHER PLACES WHERE WE RETURN 401 INSTEAD OF 403");
      expectResponse(await client.authenticatedRequest("/level1-authorizer", accessToken: "level1").post(), 403, body: {
        "error": "insufficient_scope",
        "scope": "level1 level2"
      });
    });

    test("If token has sufficient scope for method requiring multiple scopes, allow it", () async {});

    test("If token has sufficient scope for only ONE of required scopes, do not allow it", () async {});

    test("If token does not have sufficient scopes for method requiring multiple scopes, do not allow it", () async {});
  });

  group("Superset scope match", () {
    test("If token has sufficient scope for method, allow it", () async {});

    test("If token does not have sufficient scope for method, do not allow it", () async {});

    test("If token has sufficient scope for method requiring multiple scopes, allow it", () async {});

    test("If token has sufficient scope for only ONE of required scopes, do not allow it", () async {});

    test("If token does not have sufficient scopes for method requiring multiple scopes, do not allow it", () async {});
  });

  group("OpenAPI", () {
    test("If method has single scope, add it to list of scopes if does not exist in Authorizer", () {});

    test("If authorizer has same scope as method scope, contains one instance of scope", () {});

    test("If authorizer has less scope than method scope, scope is overridden", () {});
  });
}

class Channel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/no-authorizer").link(() => new C1());
    router.route("/level1-authorizer").link(() => new Authorizer.bearer(authServer, scopes: ["level1"])).link(() => new C1());

    return router;
  }

  @override
  Future prepare() async {
    final storage = new InMemoryAuthStorage();
    final salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    storage.clients = {
      "c1": new AuthClient("c1", AuthUtility.generatePasswordHash("password", salt), salt,
          allowedScopes: [new AuthScope("user"), new AuthScope("other_scope")]),
    };
    storage.tokens = [
      new TestToken()
        ..issueDate = new DateTime.now()
        ..expirationDate = new DateTime.now().add(new Duration(days: 1))
        ..resourceOwnerIdentifier = 1
        ..clientID = "whocares"
        ..type = "bearer"
        ..accessToken = "level1"
        ..scopes = [new AuthScope("level1")]
    ];
    authServer = new AuthServer(storage);
  }
}

class C1 extends ResourceController {
  @Operation.get()
  Future<Response> noScopes() async => new Response.ok(null);

  @Operation.put()
  @Scope(const ["level1"])
  Future<Response> level1Scope() async => new Response.ok(null);

  @Operation.post()
  @Scope(const ["level2"])
  Future<Response> level2Scope() async => new Response.ok(null);
}
