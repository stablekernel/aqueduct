import 'dart:async';
import "dart:core";

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final app = new Application<Channel>();
  final client = new TestClient(app);

  setUpAll(() async {
    await app.test();
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

  test("If token has sufficient scope for method, allow it", () async {
    expectResponse(await client.authenticatedRequest("/level1-authorizer", accessToken: "level1").put(), 200);
  });

  test("If token does not have sufficient scope for method, return 403 and include required scope in body", () async {
    expectResponse(await client.authenticatedRequest("/level1-authorizer", accessToken: "level1").post(), 403,
        body: {"error": "insufficient_scope", "scope": "level1 level2"});
  });

  test("If token has sufficient scope for method requiring multiple scopes, allow it", () async {
    expectResponse(await client.authenticatedRequest("/level1-authorizer", accessToken: "level1 level2").delete(), 200);
  });

  test("If token has sufficient scope for only ONE of required scopes, do not allow it", () async {
    expectResponse(await client.authenticatedRequest("/level1-authorizer", accessToken: "level1").delete(), 403,
        body: {"error": "insufficient_scope", "scope": "level1 level2"});
  });

  test("If token does not have any sufficient scopes for method requiring multiple scopes, do not allow it", () async {
    expectResponse(await client.authenticatedRequest("/authorizer", accessToken: "no-scope").delete(), 403,
        body: {"error": "insufficient_scope", "scope": "level1 level2"});
  });

  group("OpenAPI", () {
    APIDocument doc;
    setUpAll(() async {
      doc = await Application.document(Channel, new ApplicationOptions(), {"version": "1.0", "name": "desc"});
    });

    test("If method has scopes, add them to list of scopes if does not exist in Authorizer", () {
      expect(doc.paths["/level1-authorizer"].operations["get"].security.length, 1);
      expect(doc.paths["/level1-authorizer"].operations["get"].security.first.requirements.length, 1);
      expect(doc.paths["/level1-authorizer"].operations["get"].security.first.requirements["oauth2"], ["level1"]);

      expect(doc.paths["/level1-authorizer"].operations["post"].security.length, 1);
      expect(doc.paths["/level1-authorizer"].operations["post"].security.first.requirements.length, 1);
      expect(doc.paths["/level1-authorizer"].operations["post"].security.first.requirements["oauth2"],
          ["level1", "level2"]);

      expect(doc.paths["/level1-authorizer"].operations["delete"].security.length, 1);
      expect(doc.paths["/level1-authorizer"].operations["delete"].security.first.requirements.length, 1);
      expect(doc.paths["/level1-authorizer"].operations["delete"].security.first.requirements["oauth2"],
          ["level1", "level2"]);

      expect(doc.paths["/level1-authorizer"].operations["put"].security.length, 1);
      expect(doc.paths["/level1-authorizer"].operations["put"].security.first.requirements.length, 1);
      expect(doc.paths["/level1-authorizer"].operations["put"].security.first.requirements["oauth2"], ["level1"]);
    });

    test("If authorizer has less scope than method scope, method scope is used", () {
      expect(doc.paths["/level1-subscope-authorizer"].operations["get"].security.length, 1);
      expect(doc.paths["/level1-subscope-authorizer"].operations["get"].security.first.requirements.length, 1);
      expect(doc.paths["/level1-subscope-authorizer"].operations["get"].security.first.requirements["oauth2"],
          ["level1:subscope"]);

      expect(doc.paths["/level1-subscope-authorizer"].operations["post"].security.length, 1);
      expect(doc.paths["/level1-subscope-authorizer"].operations["post"].security.first.requirements.length, 1);
      expect(doc.paths["/level1-subscope-authorizer"].operations["post"].security.first.requirements["oauth2"],
          ["level1:subscope", "level2"]);

      expect(doc.paths["/level1-subscope-authorizer"].operations["put"].security.length, 1);
      expect(doc.paths["/level1-subscope-authorizer"].operations["put"].security.first.requirements.length, 1);
      expect(
          doc.paths["/level1-subscope-authorizer"].operations["put"].security.first.requirements["oauth2"], ["level1"]);

      expect(doc.paths["/level1-subscope-authorizer"].operations["delete"].security.length, 1);
      expect(doc.paths["/level1-subscope-authorizer"].operations["delete"].security.first.requirements.length, 1);
      expect(doc.paths["/level1-subscope-authorizer"].operations["delete"].security.first.requirements["oauth2"],
          ["level1", "level2"]);
    });

    test("Scopes are available in securityScheme object", () {
      final flows = doc.components.securitySchemes["oauth2"].flows;
      expect(flows.length, 1);

      final flow = flows.values.first;
      expect(flow.scopes.length, 3);
      expect(flow.scopes.containsKey("level1"), true);
      expect(flow.scopes.containsKey("level2"), true);
      expect(flow.scopes.containsKey("level1:subscope"), true);
    });
  });
}

class Channel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/auth/token").link(() => new AuthController(authServer));

    router.route("/no-authorizer").link(() => new C1());
    router
        .route("/level1-authorizer")
        .link(() => new Authorizer.bearer(authServer, scopes: ["level1"]))
        .link(() => new C1());
    router
        .route("/level1-subscope-authorizer")
        .link(() => new Authorizer.bearer(authServer, scopes: ["level1:subscope"]))
        .link(() => new C1());
    router.route("/authorizer").link(() => new Authorizer.bearer(authServer)).link(() => new C1());

    return router;
  }

  @override
  Future prepare() async {
    final storage = new InMemoryAuthStorage();

    storage.tokens = [
      new TestToken()
        ..issueDate = new DateTime.now()
        ..expirationDate = new DateTime.now().add(new Duration(days: 1))
        ..resourceOwnerIdentifier = 1
        ..clientID = "whocares"
        ..type = "bearer"
        ..accessToken = "no-scope"
        ..scopes = [],
      new TestToken()
        ..issueDate = new DateTime.now()
        ..expirationDate = new DateTime.now().add(new Duration(days: 1))
        ..resourceOwnerIdentifier = 1
        ..clientID = "whocares"
        ..type = "bearer"
        ..accessToken = "level1"
        ..scopes = [new AuthScope("level1")],
      new TestToken()
        ..issueDate = new DateTime.now()
        ..expirationDate = new DateTime.now().add(new Duration(days: 1))
        ..resourceOwnerIdentifier = 1
        ..clientID = "whocares"
        ..type = "bearer"
        ..accessToken = "level1 level2"
        ..scopes = [new AuthScope("level1"), new AuthScope("level2")]
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

  @Operation.delete()
  @Scope(const ["level1", "level2"])
  Future<Response> bothScopes() async => new Response.ok(null);
}

