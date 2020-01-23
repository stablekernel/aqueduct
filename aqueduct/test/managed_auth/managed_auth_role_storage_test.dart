import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/context_helpers.dart';

// These tests are similar to managed_auth_storage_test, but handle the cases where authenticatables
// have scope rules.
void main() {
  RoleBasedAuthStorage storage;
  ManagedContext context;
  AuthServer auth;
  List<User> createdUsers;

  setUpAll(() async {
    context =
        await contextWithModels([User, ManagedAuthClient, ManagedAuthToken]);
    storage = RoleBasedAuthStorage(context);
    auth = AuthServer(storage);
    createdUsers = await createUsers(context, 5);

    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";

    var clients = [
      AuthClient.withRedirectURI("redirect",
          AuthUtility.generatePasswordHash("a", salt), salt, "http://a.com",
          allowedScopes: [AuthScope("user"), AuthScope("location:add")]),
    ];

    await Future.wait(clients
        .map((ac) => ManagedAuthClient()
          ..id = ac.id
          ..salt = ac.salt
          ..allowedScope = ac.allowedScopes.map((a) => a.toString()).join(" ")
          ..hashedSecret = ac.hashedSecret
          ..redirectURI = ac.redirectURI)
        .map((mc) {
      var q = Query<ManagedAuthClient>(context)..values = mc;
      return q.insert();
    }));
  });

  tearDownAll(() async {
    await context?.close();
    context = null;
  });

  group("Resource owner", () {
    test("AuthScope.Any allows all client scopes", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "admin").username,
          User.defaultPassword,
          "redirect",
          "a",
          requestedScopes: [AuthScope("user"), AuthScope("location:add")]);

      expect(t.scopes.length, 2);
      expect(t.scopes.any((s) => s.isExactly("user")), true);
      expect(t.scopes.any((s) => s.isExactly("location:add")), true);
    });

    test("Restricted role scopes prevents allowed client scopes", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "user").username,
          User.defaultPassword,
          "redirect",
          "a",
          requestedScopes: [AuthScope("user"), AuthScope("location:add")]);

      expect(t.scopes.length, 1);
      expect(t.scopes.any((s) => s.isExactly("user")), true);
    });

    test(
        "Role that allows scope but not requested, netting no scope, prevents access token from being granted",
        () async {
      try {
        await auth.authenticate(
            createdUsers.firstWhere((u) => u.role == "user").username,
            User.defaultPassword,
            "redirect",
            "a",
            requestedScopes: [AuthScope("location:add")]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Role that allows no scope prevents access token from being granted",
        () async {
      try {
        await auth.authenticate(
            createdUsers.firstWhere((u) => u.role == null).username,
            User.defaultPassword,
            "redirect",
            "a",
            requestedScopes: [AuthScope("location:add")]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test(
        "Client allows full scope, role restricts it to a subset, can only grant subset",
        () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.defaultPassword,
          "redirect",
          "a",
          requestedScopes: [
            AuthScope("user.readonly"),
            AuthScope("location:add:xyz")
          ]);

      expect(t.scopes.length, 2);
      expect(t.scopes.any((s) => s.isExactly("user.readonly")), true);
      expect(t.scopes.any((s) => s.isExactly("location:add:xyz")), true);
    });

    test("User allowed scopes can't grant higher privileges than client",
        () async {
      try {
        await auth.authenticate(
            createdUsers.firstWhere((u) => u.role == "invalid").username,
            User.defaultPassword,
            "redirect",
            "a",
            requestedScopes: [AuthScope("location")]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });
  });

  group("Refresh", () {
    test("Can't upgrade scope if it allowed by client, but restricted by role",
        () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.defaultPassword,
          "redirect",
          "a",
          requestedScopes: [AuthScope("user.readonly")]);

      try {
        await auth.refresh(t.refreshToken, "redirect", "a",
            requestedScopes: [AuthScope("user")]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Can't upgrade scope even if client/user allow it", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.defaultPassword,
          "redirect",
          "a",
          requestedScopes: [AuthScope("user.readonly")]);

      try {
        await auth.refresh(t.refreshToken, "redirect", "a", requestedScopes: [
          AuthScope("user.readonly"),
          AuthScope("location:add:xyz")
        ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Not specifying scope returns same scope", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.defaultPassword,
          "redirect",
          "a",
          requestedScopes: [
            AuthScope("user.readonly"),
            AuthScope("location:add:xyz")
          ]);

      t = await auth.refresh(t.refreshToken, t.clientID, "a");
      expect(t.scopes.length, 2);
      expect(t.scopes.any((s) => s.isExactly("user.readonly")), true);
      expect(t.scopes.any((s) => s.isExactly("location:add:xyz")), true);
    });
  });

  group("Auth code", () {
    test("AuthScope.Any allows all client scopes", () async {
      var code = await auth.authenticateForCode(
          createdUsers.firstWhere((u) => u.role == "admin").username,
          User.defaultPassword,
          "redirect",
          requestedScopes: [AuthScope("user"), AuthScope("location:add")]);
      var t = await auth.exchange(code.code, "redirect", "a");

      expect(t.scopes.length, 2);
      expect(t.scopes.any((s) => s.isExactly("user")), true);
      expect(t.scopes.any((s) => s.isExactly("location:add")), true);
    });

    test("Restricted role scopes prevents allowed client scopes", () async {
      var code = await auth.authenticateForCode(
          createdUsers.firstWhere((u) => u.role == "user").username,
          User.defaultPassword,
          "redirect",
          requestedScopes: [AuthScope("user"), AuthScope("location:add")]);
      var t = await auth.exchange(code.code, "redirect", "a");

      expect(t.scopes.length, 1);
      expect(t.scopes.any((s) => s.isExactly("user")), true);
    });

    test(
        "Role that allows scope but not requested, netting no scope, prevents access token from being granted",
        () async {
      try {
        await auth.authenticateForCode(
            createdUsers.firstWhere((u) => u.role == "user").username,
            User.defaultPassword,
            "redirect",
            requestedScopes: [AuthScope("location:add")]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Role that allows no scope prevents access token from being granted",
        () async {
      try {
        await auth.authenticateForCode(
            createdUsers.firstWhere((u) => u.role == null).username,
            User.defaultPassword,
            "redirect",
            requestedScopes: [AuthScope("location:add")]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test(
        "Client allows full scope, role restricts it to a subset, can only grant subset",
        () async {
      var code = await auth.authenticateForCode(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.defaultPassword,
          "redirect",
          requestedScopes: [
            AuthScope("user.readonly"),
            AuthScope("location:add:xyz")
          ]);
      var t = await auth.exchange(code.code, "redirect", "a");

      expect(t.scopes.length, 2);
      expect(t.scopes.any((s) => s.isExactly("user.readonly")), true);
      expect(t.scopes.any((s) => s.isExactly("location:add:xyz")), true);
    });

    test("User allowed scopes can't grant higher privileges than client",
        () async {
      try {
        await auth.authenticateForCode(
            createdUsers.firstWhere((u) => u.role == "invalid").username,
            User.defaultPassword,
            "redirect",
            requestedScopes: [AuthScope("location")]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });
  });
}

class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner<_User> {
  static const String defaultPassword = "foobaraxegrind!%12";
}

class _User extends ResourceOwnerTableDefinition {
  @Column(nullable: true)
  String role;
}

Future<List<User>> createUsers(ManagedContext ctx, int count) async {
  var list = <User>[];
  for (int i = 0; i < count; i++) {
    var salt = AuthUtility.generateRandomSalt();
    var u = User()
      ..username = "bob+$i@stablekernel.com"
      ..salt = salt
      ..hashedPassword =
          AuthUtility.generatePasswordHash(User.defaultPassword, salt);

    if (u.username.startsWith("bob+0")) {
      u.role = "admin";
    } else if (u.username.startsWith("bob+1")) {
      u.role = "user";
    } else if (u.username.startsWith("bob+2")) {
      u.role = "viewer";
    } else if (u.username.startsWith("bob+3")) {
      u.role = null;
    } else if (u.username.startsWith("bob+4")) {
      u.role = "invalid";
    }

    var q = Query<User>(ctx)..values = u;

    list.add(await q.insert());
  }
  return list;
}

class RoleBasedAuthStorage extends ManagedAuthDelegate<User> {
  RoleBasedAuthStorage(ManagedContext context, {int tokenLimit = 40})
      : super(context, tokenLimit: tokenLimit);

  @override
  Future<User> getResourceOwner(AuthServer server, String username) {
    var query = Query<User>(context)
      ..where((o) => o.username).equalTo(username)
      ..returningProperties(
          (t) => [t.id, t.hashedPassword, t.salt, t.username, t.role]);

    return query.fetchOne();
  }

  @override
  List<AuthScope> getAllowedScopes(covariant User user) {
    if (user.role == "admin") {
      return AuthScope.any;
    } else if (user.role == "user") {
      return [AuthScope("user")];
    } else if (user.role == "viewer") {
      return [AuthScope("user.readonly"), AuthScope("location:add:xyz")];
    } else if (user.role == "invalid") {
      return [AuthScope("location")];
    }

    return [];
  }
}
