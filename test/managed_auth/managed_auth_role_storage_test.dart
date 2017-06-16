import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';
import 'package:test/test.dart';

import '../context_helpers.dart';

// These tests are similar to managed_auth_storage_test, but handle the cases where authenticatables
// have scope rules.
void main() {
  RoleBasedAuthStorage storage;
  ManagedContext context;
  AuthServer auth;
  List<User> createdUsers;

  setUpAll(() async {
    context = await contextWithModels([User, ManagedClient, ManagedToken]);
    storage = new RoleBasedAuthStorage(context);
    auth = new AuthServer(storage);
    createdUsers = await createUsers(5);

    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";

    var clients = [
      new AuthClient.withRedirectURI("redirect",
          AuthUtility.generatePasswordHash("a", salt), salt, "http://a.com", allowedScopes: [
            new AuthScope("user"),
            new AuthScope("location:add")
          ]),
    ];

    await Future.wait(clients
        .map((ac) => new ManagedClient()
      ..id = ac.id
      ..salt = ac.salt
      ..allowedScope = ac.allowedScopes.map((a) => a.scopeString).join(" ")
      ..hashedSecret = ac.hashedSecret
      ..redirectURI = ac.redirectURI)
        .map((mc) {
      var q = new Query<ManagedClient>()..values = mc;
      return q.insert();
    }));
  });

  tearDownAll(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  group("Resource owner", () {
    test("AuthScope.Any allows all client scopes", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "admin").username,
          User.DefaultPassword, "redirect", "a", requestedScopes: [
        new AuthScope("user"), new AuthScope("location:add")
      ]);

      expect(t.scopes.length, 2);
      expect(t.scopes.any((s) => s.isExactly("user")), true);
      expect(t.scopes.any((s) => s.isExactly("location:add")), true);
    });

    test("Restricted role scopes prevents allowed client scopes", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "user").username,
          User.DefaultPassword, "redirect", "a", requestedScopes: [
        new AuthScope("user"), new AuthScope("location:add")
      ]);

      expect(t.scopes.length, 1);
      expect(t.scopes.any((s) => s.isExactly("user")), true);
    });

    test("Role that allows scope but not requested, netting no scope, prevents access token from being granted", () async {
      try {
        await auth.authenticate(
            createdUsers.firstWhere((u) => u.role == "user").username,
            User.DefaultPassword, "redirect", "a", requestedScopes: [
          new AuthScope("location:add")
        ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Role that allows no scope prevents access token from being granted", () async {
      try {
        await auth.authenticate(
            createdUsers.firstWhere((u) => u.role == null).username,
            User.DefaultPassword, "redirect", "a", requestedScopes: [
          new AuthScope("location:add")
        ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Client allows full scope, role restricts it to a subset, can only grant subset", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.DefaultPassword, "redirect", "a", requestedScopes: [
        new AuthScope("user.readonly"), new AuthScope("location:add:xyz")
      ]);

      expect(t.scopes.length, 2);
      expect(t.scopes.any((s) => s.isExactly("user.readonly")), true);
      expect(t.scopes.any((s) => s.isExactly("location:add:xyz")), true);
    });

    test("User allowed scopes can't grant higher privileges than client", () async {
      try {
        await auth.authenticate(
            createdUsers.firstWhere((u) => u.role == "invalid").username,
            User.DefaultPassword, "redirect", "a", requestedScopes: [
          new AuthScope("location")
        ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });
  });

  group("Refresh", () {
    test("Can't upgrade scope if it allowed by client, but restricted by role", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.DefaultPassword, "redirect", "a", requestedScopes: [
        new AuthScope("user.readonly")
      ]);

      try {
        await auth.refresh(t.refreshToken, "redirect", "a", requestedScopes: [new AuthScope("user")]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Can't upgrade scope even if client/user allow it", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.DefaultPassword, "redirect", "a", requestedScopes: [
        new AuthScope("user.readonly")
      ]);

      try {
        await auth.refresh(t.refreshToken, "redirect", "a", requestedScopes: [
          new AuthScope("user.readonly"), new AuthScope("location:add:xyz")
        ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Not specifying scope returns same scope", () async {
      var t = await auth.authenticate(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.DefaultPassword, "redirect", "a", requestedScopes: [
            new AuthScope("user.readonly"), new AuthScope("location:add:xyz")
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
          User.DefaultPassword, "redirect", requestedScopes: [
        new AuthScope("user"), new AuthScope("location:add")
      ]);
      var t = await auth.exchange(code.code, "redirect", "a");

      expect(t.scopes.length, 2);
      expect(t.scopes.any((s) => s.isExactly("user")), true);
      expect(t.scopes.any((s) => s.isExactly("location:add")), true);
    });

    test("Restricted role scopes prevents allowed client scopes", () async {
      var code = await auth.authenticateForCode(
          createdUsers.firstWhere((u) => u.role == "user").username,
          User.DefaultPassword, "redirect", requestedScopes: [
        new AuthScope("user"), new AuthScope("location:add")
      ]);
      var t = await auth.exchange(code.code, "redirect", "a");

      expect(t.scopes.length, 1);
      expect(t.scopes.any((s) => s.isExactly("user")), true);
    });

    test("Role that allows scope but not requested, netting no scope, prevents access token from being granted", () async {
      try {
        await auth.authenticateForCode(
            createdUsers.firstWhere((u) => u.role == "user").username,
            User.DefaultPassword, "redirect", requestedScopes: [
          new AuthScope("location:add")
        ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Role that allows no scope prevents access token from being granted", () async {
      try {
        await auth.authenticateForCode(
            createdUsers.firstWhere((u) => u.role == null).username,
            User.DefaultPassword, "redirect", requestedScopes: [
          new AuthScope("location:add")
        ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Client allows full scope, role restricts it to a subset, can only grant subset", () async {
      var code = await auth.authenticateForCode(
          createdUsers.firstWhere((u) => u.role == "viewer").username,
          User.DefaultPassword, "redirect", requestedScopes: [
        new AuthScope("user.readonly"), new AuthScope("location:add:xyz")
      ]);
      var t = await auth.exchange(code.code, "redirect", "a");

      expect(t.scopes.length, 2);
      expect(t.scopes.any((s) => s.isExactly("user.readonly")), true);
      expect(t.scopes.any((s) => s.isExactly("location:add:xyz")), true);
    });

    test("User allowed scopes can't grant higher privileges than client", () async {
      try {
        await auth.authenticateForCode(
            createdUsers.firstWhere((u) => u.role == "invalid").username,
            User.DefaultPassword, "redirect", requestedScopes: [
          new AuthScope("location")
        ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

  });
}

class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner {
  static const String DefaultPassword = "foobaraxegrind!%12";
}

class _User extends ManagedAuthenticatable {
  @ManagedColumnAttributes(nullable: true)
  String role;
}

Future<List<User>> createUsers(int count) async {
  var list = <User>[];
  for (int i = 0; i < count; i++) {
    var salt = AuthUtility.generateRandomSalt();
    var u = new User()
      ..username = "bob+$i@stablekernel.com"
      ..salt = salt
      ..hashedPassword =
      AuthUtility.generatePasswordHash(User.DefaultPassword, salt);

    if (u.username.startsWith("bob+0")) {
      u.role = "admin";
    } else if (u.username.startsWith("bob+1")) {
      u.role = "user";
    } else if (u.username.startsWith("bob+2")){
      u.role = "viewer";
    } else if (u.username.startsWith("bob+3")) {
      u.role = null;
    } else if (u.username.startsWith("bob+4")) {
      u.role = "invalid";
    }

    var q = new Query<User>()..values = u;

    list.add(await q.insert());
  }
  return list;
}

class RoleBasedAuthStorage extends ManagedAuthStorage<User> {
  RoleBasedAuthStorage(ManagedContext context, {int tokenLimit: 40}) :
        super(context, tokenLimit: tokenLimit);

  @override
  Future<User> fetchAuthenticatableByUsername(
      AuthServer server, String username) {
    var query = new Query<User>(context)
      ..where.username = username
      ..returningProperties((t) => [t.id, t.hashedPassword, t.salt, t.username, t.role]);

    return query.fetchOne();
  }

  @override
  List<AuthScope> allowedScopesForAuthenticatable(covariant User user) {
    if (user.role == "admin") {
      return AuthScope.Any;
    } else if (user.role == "user") {
      return [new AuthScope("user")];
    } else if (user.role == "viewer") {
      return [new AuthScope("user.readonly"), new AuthScope("location:add:xyz")];
    } else if (user.role == "invalid") {
      return [new AuthScope("location")];
    }

    return [];
  }
}