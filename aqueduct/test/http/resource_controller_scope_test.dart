import 'dart:async';
import "dart:core";

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  final app = Application<Channel>();
  Agent client;

  setUpAll(() async {
    await app.startOnCurrentIsolate();
  });

  setUp(() {
    client = Agent(app);
  });

  tearDownAll(() async {
    await app.stop();
  });

  /*
    Following combos show required scopes:

    /level1-authorizer: ["level1"]
    /level1-subscope-authorizer: ["level1:subscope"]

    GET: []
    PUT: ["level1"]
    POST: ["level2"]
    DELETE: ["level1", "level2"]
 */

  test(
      "If method has no scope restrictions (but Authorizer does), allow request if passes authorizer",
      () async {
    client.headers["authorization"] = "Bearer level1";
    expectResponse(await client.request("/level1-authorizer").get(), 200);
  });

  test("When no Authorizer and method has scope, a 500 error is thrown",
      () async {
    // Log warning
    client.headers["authorization"] = "Bearer level1";
    expectResponse(await client.request("/no-authorizer").put(), 500);
  });

  test(
      "When no Authorizer and method does not have scope, request is successful",
      () async {
    client.headers["authorization"] = "Bearer level1";
    expectResponse(await client.request("/no-authorizer").get(), 200);
  });

  test("If token has sufficient scope for method, allow it", () async {
    client.headers["authorization"] = "Bearer level1";
    expectResponse(await client.request("/level1-authorizer").put(), 200);
  });

  test(
      "If token does not have sufficient scope for method, return 403 and include required scope in body",
      () async {
    client.headers["authorization"] = "Bearer level1";
    expectResponse(await client.request("/level1-authorizer").post(), 403,
        body: {"error": "insufficient_scope", "scope": "level1 level2"});
  });

  test(
      "If token has sufficient scope for method requiring multiple scopes, allow it",
      () async {
    client.headers["authorization"] = "Bearer level1 level2";
    expectResponse(await client.request("/level1-authorizer").delete(), 200);
  });

  test(
      "If token has sufficient scope for only ONE of required scopes, do not allow it",
      () async {
    client.headers["authorization"] = "Bearer level1";
    expectResponse(await client.request("/level1-authorizer").delete(), 403,
        body: {"error": "insufficient_scope", "scope": "level1 level2"});
  });

  test(
      "If token does not have any sufficient scopes for method requiring multiple scopes, do not allow it",
      () async {
    client.headers["authorization"] = "Bearer no-scope";
    expectResponse(await client.request("/authorizer").delete(), 403,
        body: {"error": "insufficient_scope", "scope": "level1 level2"});
  });
}

class Channel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Controller get entryPoint {
    final router = Router();

    router.route("/auth/token").link(() => AuthController(authServer));

    router.route("/no-authorizer").link(() => C1());
    router
        .route("/level1-authorizer")
        .link(() => Authorizer.bearer(authServer, scopes: ["level1"]))
        .link(() => C1());
    router
        .route("/level1-subscope-authorizer")
        .link(() => Authorizer.bearer(authServer, scopes: ["level1:subscope"]))
        .link(() => C1());
    router
        .route("/authorizer")
        .link(() => Authorizer.bearer(authServer))
        .link(() => C1());

    return router;
  }

  @override
  Future prepare() async {
    final storage = InMemoryAuthStorage();

    storage.tokens = [
      TestToken()
        ..issueDate = DateTime.now()
        ..expirationDate = DateTime.now().add(const Duration(days: 1))
        ..resourceOwnerIdentifier = 1
        ..clientID = "whocares"
        ..type = "bearer"
        ..accessToken = "no-scope"
        ..scopes = [],
      TestToken()
        ..issueDate = DateTime.now()
        ..expirationDate = DateTime.now().add(const Duration(days: 1))
        ..resourceOwnerIdentifier = 1
        ..clientID = "whocares"
        ..type = "bearer"
        ..accessToken = "level1"
        ..scopes = [AuthScope("level1")],
      TestToken()
        ..issueDate = DateTime.now()
        ..expirationDate = DateTime.now().add(const Duration(days: 1))
        ..resourceOwnerIdentifier = 1
        ..clientID = "whocares"
        ..type = "bearer"
        ..accessToken = "level1 level2"
        ..scopes = [AuthScope("level1"), AuthScope("level2")]
    ];
    authServer = AuthServer(storage);
  }
}

class C1 extends ResourceController {
  @Operation.get()
  Future<Response> noScopes() async => Response.ok(null);

  @Operation.put()
  @Scope(["level1"])
  Future<Response> level1Scope() async => Response.ok(null);

  @Operation.post()
  @Scope(["level2"])
  Future<Response> level2Scope() async => Response.ok(null);

  @Operation.delete()
  @Scope(["level1", "level2"])
  Future<Response> bothScopes() async => Response.ok(null);
}
