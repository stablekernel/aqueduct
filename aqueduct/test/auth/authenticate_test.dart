import 'dart:io';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  InMemoryAuthStorage delegate;

  setUp(() async {
    delegate = InMemoryAuthStorage();
  });

  test("isTokenExpired works correctly", () {
    var oldToken = AuthToken()
      ..expirationDate = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    var futureToken = AuthToken()
      ..expirationDate = DateTime.now().toUtc().add(const Duration(seconds: 10));

    expect(oldToken.isExpired, true);
    expect(futureToken.isExpired, false);
  });

  test("isAuthCodeExpired works correctly", () {
    var oldCode = AuthCode()
      ..expirationDate = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    var futureCode = AuthCode()
      ..expirationDate = DateTime.now().toUtc().add(const Duration(seconds: 10));

    expect(oldCode.isExpired, true);
    expect(futureCode.isExpired, false);
  });

  group("Client behavior", () {
    AuthServer auth;

    setUp(() async {
      auth = AuthServer(delegate);
    });

    test("Get client for ID", () async {
      var c = await auth.getClient("com.stablekernel.app1");
      expect(c is AuthClient, true);
    });

    test("Revoked client can no longer be accessed", () async {
      expect(
          await auth.getClient("com.stablekernel.app1") is AuthClient, true);
      await auth.removeClient("com.stablekernel.app1");
      expect(await auth.getClient("com.stablekernel.app1"), isNull);
    });

    test("Cannot revoke null client", () async {
      try {
        await auth.removeClient(null);
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });
  });

  group("Token behavior via authenticate", () {
    AuthServer auth;
    TestUser createdUser;
    setUp(() async {
      auth = AuthServer(delegate);
      delegate.createUsers(1);
      createdUser = delegate.users[1];
    });

    test(
        "Can create token with all information + refresh token if client is confidential",
        () async {
      var token = await auth.authenticate(
          createdUser.username,
          InMemoryAuthStorage.defaultPassword,
          "com.stablekernel.app1",
          "kilimanjaro");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.app1");
      expect(token.resourceOwnerIdentifier, createdUser.id);

      final now = DateTime.now().toUtc();
      expect(token.issueDate.difference(now).inSeconds.abs(), lessThan(5));
      expect(
          token.issueDate.isBefore(now) ||
              token.issueDate.isAtSameMomentAs(now),
          true);
      expect(token.expirationDate.isAfter(now), true);
      expect(token.type, "bearer");

      expect(token.issueDate.difference(token.expirationDate).inSeconds.abs(),
          greaterThan(86399));
      expect(token.issueDate.difference(token.expirationDate).inSeconds.abs(),
          lessThan(86401));
    });

    test(
        "Can create token with all information minus refresh token if client is public",
        () async {
      var token = await auth.authenticate(createdUser.username,
          InMemoryAuthStorage.defaultPassword, "com.stablekernel.public", "");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isNull);
      expect(token.clientID, "com.stablekernel.public");
      expect(token.resourceOwnerIdentifier, createdUser.id);

      var now = DateTime.now().toUtc();
      expect(
          token.issueDate.isBefore(now) ||
              token.issueDate.isAtSameMomentAs(now),
          true);
      expect(token.expirationDate.isAfter(now), true);
      expect(token.type, "bearer");

      token = await auth.authenticate(createdUser.username,
          InMemoryAuthStorage.defaultPassword, "com.stablekernel.public", null);
      expect(token.accessToken, isString);
      expect(token.refreshToken, isNull);
      expect(token.clientID, "com.stablekernel.public");
      expect(token.resourceOwnerIdentifier, createdUser.id);

      now = DateTime.now().toUtc();
      expect(
          token.issueDate.isBefore(now) ||
              token.issueDate.isAtSameMomentAs(now),
          true);
      expect(token.expirationDate.isAfter(now), true);
      expect(token.type, "bearer");
    });

    test("Create token fails if username is incorrect", () async {
      try {
        await auth.authenticate("nonsense", InMemoryAuthStorage.defaultPassword,
            "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails if password is incorrect", () async {
      try {
        await auth.authenticate(createdUser.username, "nonsense",
            "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails if client ID doesn't exist", () async {
      try {
        await auth.authenticate(createdUser.username,
            InMemoryAuthStorage.defaultPassword, "nonsense", "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails if client secret doesn't match", () async {
      try {
        await auth.authenticate(
            createdUser.username,
            InMemoryAuthStorage.defaultPassword,
            "com.stablekernel.app1",
            "nonsense");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test(
        "Create token fails if client ID is confidential and secret is omitted",
        () async {
      try {
        await auth.authenticate(createdUser.username,
            InMemoryAuthStorage.defaultPassword, "com.stablekernel.app1", null);
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      try {
        await auth.authenticate(createdUser.username,
            InMemoryAuthStorage.defaultPassword, "com.stablekernel.app1", "");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails if client secret provided for public client",
        () async {
      try {
        await auth.authenticate(
            createdUser.username,
            InMemoryAuthStorage.defaultPassword,
            "com.stablekernel.public",
            "nonsense");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Can create token that is verifiable", () async {
      var token = await auth.authenticate(
          createdUser.username,
          InMemoryAuthStorage.defaultPassword,
          "com.stablekernel.app1",
          "kilimanjaro");
      expect(await auth.verify(token.accessToken) is Authorization, true);
    });

    test("Can't create token without scope if client has scope", () async {
      try {
        await auth.authenticate(
            createdUser.username,
            InMemoryAuthStorage.defaultPassword,
            "com.stablekernel.public.scoped",
            null);
        fail("Should throw AuthServerException");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Can create token with sub-scope of client scope", () async {
      delegate.allowedScopes = [AuthScope("user")];
      var token = await auth.authenticate(
          createdUser.username,
          InMemoryAuthStorage.defaultPassword,
          "com.stablekernel.public.scoped",
          null,
          requestedScopes: [AuthScope("user.self")]);
      expect(token.scopes, [AuthScope("user.self")]);
    });

    test("Don't grant requested scope if it exceeds client scope", () async {
      try {
        await auth.authenticate(
            createdUser.username,
            InMemoryAuthStorage.defaultPassword,
            "com.stablekernel.public.scoped",
            null,
            requestedScopes: [AuthScope("admin")]);
        fail("Should throw AuthServerException");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test(
        "Don't grant requested scope if it exceeds allowed scope of ResourceOwner",
        () async {
      delegate.allowedScopes = [AuthScope("user.self")];
      try {
        await auth.authenticate(
            createdUser.username,
            InMemoryAuthStorage.defaultPassword,
            "com.stablekernel.public.scoped",
            null,
            requestedScopes: [AuthScope("user")]);
        fail("Should throw AuthServerException");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Cannot verify token that doesn't exist", () async {
      try {
        await auth.verify("nonsense");
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });

    test("Expired token cannot be verified", () async {
      var token = await auth.authenticate(
          createdUser.username,
          InMemoryAuthStorage.defaultPassword,
          "com.stablekernel.app1",
          "kilimanjaro",
          expiration: const Duration(seconds: 1));

      sleep(const Duration(seconds: 1));

      try {
        await auth.verify(token.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });
  });

  group("Refreshing token", () {
    AuthServer auth;
    TestUser createdUser;
    AuthToken initialToken;

    setUp(() async {
      auth = AuthServer(delegate);
      delegate.createUsers(1);
      createdUser = delegate.users[1];
      initialToken = await auth.authenticate(
          createdUser.username,
          InMemoryAuthStorage.defaultPassword,
          "com.stablekernel.app1",
          "kilimanjaro");
    });

    test(
        "Can refresh token with all information + refresh token if token had refresh token",
        () async {
      var token = await auth.refresh(
          initialToken.refreshToken, "com.stablekernel.app1", "kilimanjaro");
      expect(token.accessToken, isNot(initialToken.accessToken));
      expect(token.refreshToken, initialToken.refreshToken);
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.app1");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.issueDate.difference(DateTime.now().toUtc()).inSeconds.abs(),
          lessThan(5));

      final now = DateTime.now().toUtc();
      expect(
          token.issueDate.isBefore(now) ||
              token.issueDate.isAtSameMomentAs(now),
          true);
      expect(token.expirationDate.isAfter(now), true);
      expect(token.type, "bearer");

      expect(
          token.issueDate.isAfter(initialToken.issueDate) ||
              token.issueDate.isAtSameMomentAs(initialToken.issueDate),
          true);
      expect(token.issueDate.difference(token.expirationDate),
          initialToken.issueDate.difference(initialToken.expirationDate));

      var authorization = await auth.verify(token.accessToken);
      expect(authorization.clientID, "com.stablekernel.app1");
      expect(authorization.ownerID, initialToken.resourceOwnerIdentifier);
    });

    test("After refresh, the previous token cannot be used", () async {
      await auth.refresh(
          initialToken.refreshToken, "com.stablekernel.app1", "kilimanjaro");

      try {
        await auth.verify(initialToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });

    test("Cannot refresh token that has not been issued", () async {
      try {
        await auth.refresh("nonsense", "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token that is null", () async {
      try {
        await auth.refresh(null, "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token if client id is missing", () async {
      try {
        await auth.refresh(initialToken.refreshToken, null, "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token if client id does not match issuing client",
        () async {
      try {
        await auth.refresh(
            initialToken.refreshToken, "com.stablekernel.app2", "fuji");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token if client secret is missing", () async {
      try {
        await auth.refresh(
            initialToken.refreshToken, "com.stablekernel.app1", null);
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token if client secret is incorrect", () async {
      try {
        await auth.refresh(
            initialToken.refreshToken, "com.stablekernel.app1", "nonsense");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });
  });

  group("Generating auth code", () {
    AuthServer auth;
    TestUser createdUser;

    setUp(() async {
      auth = AuthServer(delegate);
      delegate.createUsers(1);
      createdUser = delegate.users[1];
    });

    test("Can create an auth code that can be exchanged for a token", () async {
      var authCode = await auth.authenticateForCode(createdUser.username,
          InMemoryAuthStorage.defaultPassword, "com.stablekernel.redirect");

      expect(authCode.code.length, greaterThan(0));
      final now = DateTime.now().toUtc();
      expect(authCode.issueDate.difference(now).inSeconds.abs(), lessThan(5));
      expect(
          authCode.issueDate.isBefore(now) ||
              authCode.issueDate.isAtSameMomentAs(now),
          true);
      expect(authCode.resourceOwnerIdentifier, createdUser.id);
      expect(authCode.clientID, "com.stablekernel.redirect");
      expect(authCode.expirationDate.isAfter(now), true);
      expect(
          authCode.issueDate
              .difference(authCode.expirationDate)
              .inSeconds
              .abs(),
          greaterThan(599));
      expect(
          authCode.issueDate
              .difference(authCode.expirationDate)
              .inSeconds
              .abs(),
          lessThan(601));

      var token = await auth.exchange(
          authCode.code, "com.stablekernel.redirect", "mckinley");
      expect(token, isNotNull);
    });

    test("Generate auth code with bad username fails", () async {
      try {
        await auth.authenticateForCode("bob+0@stable",
            InMemoryAuthStorage.defaultPassword, "com.stablekernel.redirect");
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client.id, "com.stablekernel.redirect");
        expect(e.reason, AuthRequestError.accessDenied);
      }
    });

    test("Generate auth code with bad password fails", () async {
      try {
        await auth.authenticateForCode(
            createdUser.username, "foobaraxegri%", "com.stablekernel.redirect");
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client.id, "com.stablekernel.redirect");
        expect(e.reason, AuthRequestError.accessDenied);
      }
    });

    test("Generate auth code with unknown client id fails", () async {
      try {
        await auth.authenticateForCode(createdUser.username,
            InMemoryAuthStorage.defaultPassword, "com.stabl");
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client, isNull);
        expect(e.reason, AuthRequestError.invalidClient);
      }
    });

    test("Generate auth code with no redirect uri fails", () async {
      try {
        await auth.authenticateForCode(createdUser.username,
            InMemoryAuthStorage.defaultPassword, "com.stablekernel.app1");
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client.id, "com.stablekernel.app1");
        expect(e.reason, AuthRequestError.unauthorizedClient);
      }
    });

    test("Generate auth code with no client id", () async {
      try {
        await auth.authenticateForCode(
            createdUser.username, InMemoryAuthStorage.defaultPassword, null);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client, isNull);
        expect(e.reason, AuthRequestError.invalidClient);
      }
    });
  });

  group("Exchanging auth code", () {
    AuthServer auth;
    TestUser createdUser;
    AuthCode code;

    setUp(() async {
      auth = AuthServer(delegate);
      delegate.createUsers(1);
      createdUser = delegate.users[1];
      code = await auth.authenticateForCode(createdUser.username,
          InMemoryAuthStorage.defaultPassword, "com.stablekernel.redirect");
    });

    test("Can create an auth code that can be exchanged for a token", () async {
      var token = await auth.exchange(
          code.code, "com.stablekernel.redirect", "mckinley");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.redirect");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      final now = DateTime.now().toUtc();
      expect(
          token.issueDate.isBefore(now) ||
              token.issueDate.isAtSameMomentAs(now),
          true);
      expect(token.expirationDate.isAfter(now), true);
      expect(token.type, "bearer");
    });

    test("Null code fails", () async {
      try {
        await auth.exchange(null, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Code that doesn't exist fails", () async {
      try {
        await auth.exchange("foobar", "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Expired code fails", () async {
      code = await auth.authenticateForCode(createdUser.username,
          InMemoryAuthStorage.defaultPassword, "com.stablekernel.redirect",
          expirationInSeconds: 1);

      sleep(const Duration(seconds: 1));

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Code that has been exchanged already fails, issued token is revoked",
        () async {
      var issuedToken = await auth.exchange(
          code.code, "com.stablekernel.redirect", "mckinley");

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      // Can no longer use issued token
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });

    test(
        "Code that has been exchanged already fails, issued and refreshed token is revoked",
        () async {
      var issuedToken = await auth.exchange(
          code.code, "com.stablekernel.redirect", "mckinley");
      var refreshedToken = await auth.refresh(
          issuedToken.refreshToken, "com.stablekernel.redirect", "mckinley");

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      // Can no longer use issued token
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      try {
        await auth.verify(refreshedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });

    test("Null client ID fails", () async {
      try {
        await auth.exchange(code.code, null, "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Unknown client ID fails", () async {
      try {
        await auth.exchange(code.code, "nonsense", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Different client ID than the one that generated code fials",
        () async {
      try {
        await auth.exchange(
            code.code, "com.stablekernel.redirect2", "gibraltar");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("No client secret fails", () async {
      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", null);

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Wrong client secret fails", () async {
      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "nonsense");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });
  });

  test("Clients have separate tokens", () async {
    var auth = AuthServer(delegate);

    delegate.createUsers(1);
    TestUser createdUser = delegate.users[1];

    var token = await auth.authenticate(
        "bob+0@stablekernel.com",
        InMemoryAuthStorage.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro");
    var p1 = await auth.verify(token.accessToken);
    expect(p1.clientID, "com.stablekernel.app1");
    expect(p1.ownerID, createdUser.id);

    var token2 = await auth.authenticate("bob+0@stablekernel.com",
        InMemoryAuthStorage.defaultPassword, "com.stablekernel.app2", "fuji");
    var p2 = await auth.verify(token2.accessToken);
    expect(p2.clientID, "com.stablekernel.app2");
    expect(p2.ownerID, createdUser.id);

    p1 = await auth.verify(token.accessToken);
    expect(p1.clientID, "com.stablekernel.app1");
    expect(p1.ownerID, createdUser.id);
  });

  test("Ensure users aren't authenticated by other users", () async {
    var auth = AuthServer(delegate);
    delegate.createUsers(10);
    var users = delegate.users.values.toList();
    var t1 = await auth.authenticate(
        "bob+0@stablekernel.com",
        InMemoryAuthStorage.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro");
    var t2 = await auth.authenticate(
        "bob+4@stablekernel.com",
        InMemoryAuthStorage.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro");

    var permission = await auth.verify(t1.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.ownerID, users[0].id);

    permission = await auth.verify(t2.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.ownerID, users[4].id);
  });
}
