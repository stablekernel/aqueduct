import 'dart:async';
import "dart:core";

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  APIDocument doc;
  setUpAll(() async {
    doc = await Application.document(
        Channel, ApplicationOptions(), {"version": "1.0", "name": "desc"});
  });

  test(
      "If method has scopes, add them to list of scopes if does not exist in Authorizer",
      () {
    expect(
        doc.paths["/level1-authorizer"].operations["get"].security.length, 1);
    expect(
        doc.paths["/level1-authorizer"].operations["get"].security.first
            .requirements.length,
        1);
    expect(
        doc.paths["/level1-authorizer"].operations["get"].security.first
            .requirements["oauth2"],
        ["level1"]);

    expect(
        doc.paths["/level1-authorizer"].operations["post"].security.length, 1);
    expect(
        doc.paths["/level1-authorizer"].operations["post"].security.first
            .requirements.length,
        1);
    expect(
        doc.paths["/level1-authorizer"].operations["post"].security.first
            .requirements["oauth2"],
        ["level1", "level2"]);

    expect(doc.paths["/level1-authorizer"].operations["delete"].security.length,
        1);
    expect(
        doc.paths["/level1-authorizer"].operations["delete"].security.first
            .requirements.length,
        1);
    expect(
        doc.paths["/level1-authorizer"].operations["delete"].security.first
            .requirements["oauth2"],
        ["level1", "level2"]);

    expect(
        doc.paths["/level1-authorizer"].operations["put"].security.length, 1);
    expect(
        doc.paths["/level1-authorizer"].operations["put"].security.first
            .requirements.length,
        1);
    expect(
        doc.paths["/level1-authorizer"].operations["put"].security.first
            .requirements["oauth2"],
        ["level1"]);
  });

  test("If authorizer has less scope than method scope, method scope is used",
      () {
    expect(
        doc.paths["/level1-subscope-authorizer"].operations["get"].security
            .length,
        1);
    expect(
        doc.paths["/level1-subscope-authorizer"].operations["get"].security
            .first.requirements.length,
        1);
    expect(
        doc.paths["/level1-subscope-authorizer"].operations["get"].security
            .first.requirements["oauth2"],
        ["level1:subscope"]);

    expect(
        doc.paths["/level1-subscope-authorizer"].operations["post"].security
            .length,
        1);
    expect(
        doc.paths["/level1-subscope-authorizer"].operations["post"].security
            .first.requirements.length,
        1);
    expect(
        doc.paths["/level1-subscope-authorizer"].operations["post"].security
            .first.requirements["oauth2"],
        ["level1:subscope", "level2"]);

    expect(
        doc.paths["/level1-subscope-authorizer"].operations["put"].security
            .length,
        1);
    expect(
        doc.paths["/level1-subscope-authorizer"].operations["put"].security
            .first.requirements.length,
        1);
    expect(
        doc.paths["/level1-subscope-authorizer"].operations["put"].security
            .first.requirements["oauth2"],
        ["level1"]);

    expect(
        doc.paths["/level1-subscope-authorizer"].operations["delete"].security
            .length,
        1);
    expect(
        doc.paths["/level1-subscope-authorizer"].operations["delete"].security
            .first.requirements.length,
        1);
    expect(
        doc.paths["/level1-subscope-authorizer"].operations["delete"].security
            .first.requirements["oauth2"],
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
