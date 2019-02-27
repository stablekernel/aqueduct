import 'dart:async';
import 'dart:convert';

import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';
import 'package:test/test.dart';

void main() {
  final harness = HarnessSubclass()..install();

  test("Can use public client to authenticate", () async {
    final public = await harness.addClient("id");
    expect(public.headers["authorization"],
        "Basic ${base64.encode("id:".codeUnits)}");

    final user = await harness.createUser();
    final userClient =
        await harness.loginUser(public, user.username, "password");
    final authHeader = userClient.headers["authorization"];
    expect(authHeader, startsWith("Bearer"));

    final q = Query<ManagedAuthToken>(harness.context)
      ..where((o) => o.accessToken).equalTo((authHeader as String).substring(7));
    final token = await q.fetchOne();
    expect(token.client.id, "id");
  });

  test("Can use confidental client to authenticate", () async {
    final confidential =
        await harness.addClient("confidential-id", secret: "secret");
    expect(confidential.headers["authorization"],
        "Basic ${base64.encode("confidential-id:secret".codeUnits)}");

    final user = await harness.createUser();
    final userClient =
        await harness.loginUser(confidential, user.username, "password");
    final authHeader = userClient.headers["authorization"];
    expect(authHeader, startsWith("Bearer"));

    final q = Query<ManagedAuthToken>(harness.context)
      ..where((o) => o.accessToken).equalTo((authHeader as String).substring(7));
    final token = await q.fetchOne();
    expect(token.client.id, "confidential-id");
  });

  test("Can authenticate user with client and access protected route",
      () async {
    final scopeAgent =
        await harness.addClient("scope", allowedScope: ["scope", "not-scope"]);
    expect(scopeAgent.headers["authorization"],
        "Basic ${base64.encode("scope:".codeUnits)}");

    final user = await harness.createUser();

    final userWithCorrectScope = await harness
        .loginUser(scopeAgent, user.username, "password", scopes: ["scope"]);
    expectResponse(await userWithCorrectScope.request("/endpoint").get(), 200);

    final userWithIncorrectScope = await harness.loginUser(
        scopeAgent, user.username, "password",
        scopes: ["not-scope"]);
    expectResponse(
        await userWithIncorrectScope.request("/endpoint").get(), 403);
  });

  test("Can authenticate user with client and access scope-protected route",
      () async {
    final scopeAgent =
        await harness.addClient("scope", allowedScope: ["scope", "not-scope"]);
    expect(scopeAgent.headers["authorization"],
        "Basic ${base64.encode("scope:".codeUnits)}");

    final user = await harness.createUser();

    final userWithCorrectScope = await harness
        .loginUser(scopeAgent, user.username, "password", scopes: ["scope"]);
    expectResponse(await userWithCorrectScope.request("/endpoint").get(), 200);

    final userWithIncorrectScope = await harness.loginUser(
        scopeAgent, user.username, "password",
        scopes: ["not-scope"]);
    expectResponse(
        await userWithIncorrectScope.request("/endpoint").get(), 403);
  });

  test("If password is incorrect, throw reasonable error message", () async {
    final scopeAgent =
        await harness.addClient("scope", allowedScope: ["scope", "not-scope"]);
    final user = await harness.createUser();
    try {
      await harness.loginUser(scopeAgent, user.username, "incorrect");
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Invalid username/password."));
    }
  });

  test("If requested scope is unavailable, throw reasonable error message",
      () async {
    final scopeAgent =
        await harness.addClient("scope", allowedScope: ["scope", "not-scope"]);
    final user = await harness.createUser();
    try {
      await harness.loginUser(scopeAgent, user.username, "password",
          scopes: ["whatever"]);
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(),
          contains("Scope not permitted for client identifier and/or user."));
    }
  });
}

class Channel extends ApplicationChannel {
  ManagedContext context;
  AuthServer authServer;

  @override
  Future prepare() async {
    context = ManagedContext(
        ManagedDataModel.fromCurrentMirrorSystem(),
        PostgreSQLPersistentStore(
            "dart", "dart", "localhost", 5432, "dart_test"));
    authServer = AuthServer(ManagedAuthDelegate<User>(context));
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router
        .route("/endpoint")
        .link(() => Authorizer.bearer(authServer, scopes: ["scope"]))
        .linkFunction((req) async => Response.ok({"key": "value"}));
    return router;
  }
}

class HarnessSubclass extends TestHarness<Channel>
    with TestHarnessAuthMixin<Channel>, TestHarnessORMMixin {
  @override
  Future seed() async {}

  @override
  AuthServer get authServer => channel.authServer;

  @override
  ManagedContext get context => channel.context;


  @override
  Future onSetUp() async {
    await resetData();
  }

  Future<User> createUser(
      {String username = "username", String password = "password"}) {
    final salt = AuthUtility.generateRandomSalt();
    final user = User()
      ..username = username
      ..salt = salt
      ..hashedPassword = AuthUtility.generatePasswordHash(password, salt);
    return Query.insertObject(context, user);
  }
}

class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner<_User> {}

class _User extends ResourceOwnerTableDefinition {}
