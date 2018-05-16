import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';

import '../context_helpers.dart';

// These tests mostly duplicate authenticate_test.dart, but also add a few more
// to manage long-term storage/cleanup of tokens and related items.
void main() {
  ManagedAuthDelegate<User> storage;
  ManagedContext context;

  setUp(() async {
    context = await contextWithModels([User, ManagedAuthClient, ManagedAuthToken]);

    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    var clients = [
      new AuthClient("com.stablekernel.app1",
          AuthUtility.generatePasswordHash("kilimanjaro", salt), salt),
      new AuthClient("com.stablekernel.app2",
          AuthUtility.generatePasswordHash("fuji", salt), salt),
      new AuthClient.withRedirectURI(
          "com.stablekernel.redirect",
          AuthUtility.generatePasswordHash("mckinley", salt),
          salt,
          "http://stablekernel.com/auth/redirect"),
      new AuthClient.public("com.stablekernel.public"),
      new AuthClient.withRedirectURI(
          "com.stablekernel.redirect2",
          AuthUtility.generatePasswordHash("gibraltar", salt),
          salt,
          "http://stablekernel.com/auth/redirect2")
    ];

    await Future.wait(clients
        .map((ac) => new ManagedAuthClient()
          ..id = ac.id
          ..salt = ac.salt
          ..hashedSecret = ac.hashedSecret
          ..redirectURI = ac.redirectURI)
        .map((mc) {
      var q = new Query<ManagedAuthClient>(context)..values = mc;
      return q.insert();
    }));

    storage = new ManagedAuthDelegate<User>(context);
  });

  tearDown(() async {
    await context?.close();
    context = null;
  });

  group("Client behavior", () {
    AuthServer auth;

    setUp(() async {
      auth = new AuthServer(storage);
    });

    test("Get client for ID", () async {
      var c = await auth.getClient("com.stablekernel.app1");
      expect(c is AuthClient, true);
    });

    test("Revoked client can no longer be accessed", () async {
      expect((await auth.getClient("com.stablekernel.app1")) is AuthClient,
          true);
      await auth.removeClient("com.stablekernel.app1");
      expect(await auth.getClient("com.stablekernel.app1"), isNull);
    });

    test("Cannot revoke null client", () async {
      try {
        await auth.removeClient(null);
        expect(true, false);
      } on AuthServerException {}

      var q = new Query<ManagedAuthClient>(context);
      expect(await q.fetch(), hasLength(5));
    });

    test("Revoking unknown client has no impact", () async {
      await auth.removeClient("nonsense");
      var q = new Query<ManagedAuthClient>(context);
      expect(await q.fetch(), hasLength(5));
    });
    
    test("Can add a new public client", () async {
      var client = AuthUtility.generateAPICredentialPair("pub-id", null, hashLength: auth.hashLength, hashRounds: auth.hashRounds, hashFunction: auth.hashFunction);
      await auth.addClient(client);

      final q = new Query<ManagedAuthClient>(context)
        ..where((o) => o.id).equalTo("pub-id");
      final result = (await q.fetchOne()).asClient();
      expect(result.id, "pub-id");
      expect(result.hashedSecret, isNull);
      expect(result.salt, isNull);
      expect(result.redirectURI, isNull);
      expect(result.supportsScopes, false);
      expect(result.allowedScopes, isNull);
    });

    test("If client already exists, exception is thrown", () async {
      var client = AuthUtility.generateAPICredentialPair("conflict", null, hashLength: auth.hashLength, hashRounds: auth.hashRounds, hashFunction: auth.hashFunction);
      await auth.addClient(client);

      try {
        await auth.addClient(client);
        fail('unreachable');
      } on QueryException catch (e) {
        expect(e.event, QueryExceptionEvent.conflict);
      }
    });

    test("If client id is null, exception is thrown", () async {
      var client = AuthUtility.generateAPICredentialPair(null, null, hashLength: auth.hashLength, hashRounds: auth.hashRounds, hashFunction: auth.hashFunction);

      try {
        await auth.addClient(client);
        fail('unreachable');
      } on QueryException catch (e) {
        expect(e.event, QueryExceptionEvent.input);
      }
    });

    test("If client has redirect uri and no secret, exception is thrown", () async {
      var client = new AuthClient("redirect-public-id", null, null)..redirectURI = "http://localhost";

      try {
        await auth.addClient(client);
        fail('unreachable');
      } on ArgumentError {}
    });

    test("Client retains its allowed scopes", () async {
      var client = AuthUtility.generateAPICredentialPair("confidential-id", "foobar", redirectURI: "http://localhost", hashLength: auth.hashLength, hashRounds: auth.hashRounds, hashFunction: auth.hashFunction)
        ..allowedScopes = ["scope"].map((s) => new AuthScope(s)).toList();
      await auth.addClient(client);

      final q = new Query<ManagedAuthClient>(context)
        ..where((o) => o.id).equalTo("confidential-id");
      final result = (await q.fetchOne()).asClient();
      expect(result.id, "confidential-id");
      expect(result.hashedSecret, isNotNull);
      expect(result.salt, isNotNull);
      expect(result.redirectURI, "http://localhost");
      expect(result.supportsScopes, isTrue);
      expect(result.allowsScope(new AuthScope("scope")), true);
      expect(result.allowsScope(new AuthScope("fooar")), false);
    });
  });

  group("Token behavior via authenticate", () {
    AuthServer auth;
    User createdUser;
    setUp(() async {
      auth = new AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;
    });

    test(
        "Can create token with all information + refresh token if client is confidential",
        () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.app1");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");

      final now = new DateTime.now().toUtc();
      expect(token.issueDate.isBefore(now) || token.issueDate.isAtSameMomentAs(now), true);
      expect(token.expirationDate.isAfter(now), true);
    });

    test(
        "Can create token with all information minus refresh token if client is public",
        () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.public", "");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isNull);
      expect(token.clientID, "com.stablekernel.public");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");

      var now = new DateTime.now().toUtc();
      expect(token.issueDate.isBefore(now) || token.issueDate.isAtSameMomentAs(now), true);
      expect(token.expirationDate.isAfter(now), true);

      token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.public", null);
      expect(token.accessToken, isString);
      expect(token.refreshToken, isNull);
      expect(token.clientID, "com.stablekernel.public");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");

      now = new DateTime.now().toUtc();
      expect(token.issueDate.isBefore(now) || token.issueDate.isAtSameMomentAs(now), true);
      expect(token.expirationDate.isAfter(now), true);
    });

    test("Can create token if client has redirect uri", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.redirect", "mckinley");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.redirect");
    });

    test("Create token fails if username is incorrect", () async {
      try {
        await auth.authenticate("nonsense", User.DefaultPassword,
            "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Create token fails if password is incorrect", () async {
      try {
        await auth.authenticate(createdUser.username, "nonsense",
            "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Create token fails if client ID doesn't exist", () async {
      try {
        await auth.authenticate(createdUser.username, User.DefaultPassword,
            "nonsense", "kilimanjaro");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Create token fails if client secret doesn't match", () async {
      try {
        await auth.authenticate(createdUser.username, User.DefaultPassword,
            "com.stablekernel.app1", "nonsense");
        expect(true, false);
      } on AuthServerException {}
    });

    test(
        "Create token fails if client ID is confidential and secret is omitted",
        () async {
      try {
        await auth.authenticate(createdUser.username, User.DefaultPassword,
            "com.stablekernel.app1", null);
        expect(true, false);
      } on AuthServerException {}

      try {
        await auth.authenticate(createdUser.username, User.DefaultPassword,
            "com.stablekernel.app1", "");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Create token fails if client secret provided for public client",
        () async {
      try {
        await auth.authenticate(createdUser.username, User.DefaultPassword,
            "com.stablekernel.public", "nonsense");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Can create token that is verifiable", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
      expect((await auth.verify(token.accessToken)) is Authorization, true);
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
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro",
          expiration: new Duration(seconds: 1));

      sleep(new Duration(seconds: 1));

      try {
        await auth.verify(token.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });

    test("Cannot verify token if owner authentcatable is 'revoked'", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
      await auth.revokeAllGrantsForResourceOwner(createdUser.id);

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
    User createdUser;
    AuthToken initialToken;

    setUp(() async {
      auth = new AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;
      initialToken = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
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
      expect(token.type, "bearer");

      var now = new DateTime.now().toUtc();
      expect(token.issueDate.isBefore(now) || token.issueDate.isAtSameMomentAs(now), true);
      expect(token.expirationDate.isAfter(now), true);

      expect(token.issueDate.isAfter(initialToken.issueDate), true);
      expect(token.issueDate.difference(token.expirationDate),
          initialToken.issueDate.difference(initialToken.expirationDate));

      var authorization = await auth.verify(token.accessToken);
      expect(authorization.clientID, "com.stablekernel.app1");
      expect(authorization.ownerID,
          initialToken.resourceOwnerIdentifier);
    });

    test("Can refresh token if client has redirect uri", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.redirect", "mckinley");

      var refreshToken = await auth.refresh(
          token.refreshToken, "com.stablekernel.redirect", "mckinley");
      expect(refreshToken.accessToken, isString);
      expect(refreshToken.refreshToken, isString);
      expect(refreshToken.clientID, "com.stablekernel.redirect");
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

      // Make sure we don't have duplicates in the db
      var q = new Query<ManagedAuthToken>(context);
      expect(await q.fetch(), hasLength(1));
    });

    test("Cannot refresh token that has not been issued", () async {
      try {
        await auth.refresh("nonsense", "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Cannot refresh token that is null", () async {
      try {
        await auth.refresh(null, "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Cannot refresh token if client id is missing", () async {
      try {
        await auth.refresh(initialToken.refreshToken, null, "kilimanjaro");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Cannot refresh token if client id does not match issuing client",
        () async {
      try {
        await auth.refresh(
            initialToken.refreshToken, "com.stablekernel.app2", "fuji");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Cannot refresh token if client secret is missing", () async {
      try {
        await auth.refresh(
            initialToken.refreshToken, "com.stablekernel.app1", null);
        expect(true, false);
      } on AuthServerException {}
    });

    test("Cannot refresh token if client secret is incorrect", () async {
      try {
        await auth.refresh(
            initialToken.refreshToken, "com.stablekernel.app1", "nonsense");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Cannot refresh token if owner authentcatable is 'revoked'", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
      await auth.revokeAllGrantsForResourceOwner(createdUser.id);

      try {
        await auth.refresh(
            token.accessToken, "com.stablekernel.redirect", "mckinley");
        expect(true, false);
      } on AuthServerException {}
    });
  });

  group("Generating auth code", () {
    AuthServer auth;
    User createdUser;

    setUp(() async {
      auth = new AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;
    });

    test("Can create an auth code that can be exchanged for a token", () async {
      var authCode = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "com.stablekernel.redirect");

      expect(authCode.code.length, greaterThan(0));
      expect(authCode.resourceOwnerIdentifier, createdUser.id);
      expect(authCode.clientID, "com.stablekernel.redirect");

      final now = new DateTime.now().toUtc();
      expect(authCode.issueDate.isBefore(now) || authCode.issueDate.isAtSameMomentAs(now), true);
      expect(authCode.expirationDate.isAfter(now), true);

      var token = await auth.exchange(
          authCode.code, "com.stablekernel.redirect", "mckinley");
      expect(token.accessToken, isString);
      expect(token.clientID, "com.stablekernel.redirect");
      expect(token.refreshToken, isString);
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");
      expect(
          token.expirationDate.difference(new DateTime.now().toUtc()).inSeconds,
          greaterThan(3500));
      expect(
          token.issueDate
              .difference(new DateTime.now().toUtc())
              .inSeconds
              .abs(),
          lessThan(2));
    });

    test("Generate auth code with bad username fails", () async {
      try {
        await auth.authenticateForCode(
            "bob+0@stable", User.DefaultPassword, "com.stablekernel.redirect");
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
        await auth.authenticateForCode(
            createdUser.username, User.DefaultPassword, "com.stabl");
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client, isNull);
        expect(e.reason, AuthRequestError.invalidClient);
      }
    });

    test("Generate auth code with no redirect uri fails", () async {
      try {
        await auth.authenticateForCode(createdUser.username,
            User.DefaultPassword, "com.stablekernel.app1");
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client.id, "com.stablekernel.app1");
        expect(e.reason, AuthRequestError.unauthorizedClient);
      }
    });

    test("Generate auth code with no client id", () async {
      try {
        await auth.authenticateForCode(
            createdUser.username, User.DefaultPassword, null);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client, isNull);
        expect(e.reason, AuthRequestError.invalidClient);
      }
    });

    test("Code no longer available if owner authentcatable is 'revoked'",
        () async {
      var authCode = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "com.stablekernel.redirect");
      await auth.revokeAllGrantsForResourceOwner(createdUser.id);

      try {
        await auth.exchange(
            authCode.code, "com.stablekernel.redirect", "mckinley");
        expect(true, false);
      } on AuthServerException {}
    });
  });

  group("Exchanging auth code", () {
    AuthServer auth;
    User createdUser;
    AuthCode code;

    setUp(() async {
      auth = new AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;
      code = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "com.stablekernel.redirect");
    });

    test("Can create an auth code that can be exchanged for a token", () async {
      var token = await auth.exchange(
          code.code, "com.stablekernel.redirect", "mckinley");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.redirect");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");

      final now = new DateTime.now().toUtc();
      expect(token.issueDate.isBefore(now) || token.issueDate.isAtSameMomentAs(now), true);
      expect(token.expirationDate.isAfter(now), true);
    });

    test("Null code fails", () async {
      try {
        await auth.exchange(null, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
      } on AuthServerException {}
    });

    test("Code that doesn't exist fails", () async {
      try {
        await auth.exchange("foobar", "com.stablekernel.redirect", "mckinley");

        expect(true, false);
      } on AuthServerException {}
    });

    test("Expired code fails and it gets deleted", () async {
      code = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "com.stablekernel.redirect",
          expirationInSeconds: 1);

      sleep(new Duration(seconds: 1));

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
      } on AuthServerException {}

      var q = new Query<ManagedAuthToken>(context)..where((o) => o.code).equalTo(code.code);
      expect(await q.fetch(), isEmpty);
    });

    test("Code that has been exchanged already fails, issued token is revoked",
        () async {
      var issuedToken = await auth.exchange(
          code.code, "com.stablekernel.redirect", "mckinley");

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
      } on AuthServerException {}

      // Can no longer use issued token
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      // Ensure that the associated auth code is also destroyed
      var authCodeQuery = new Query<ManagedAuthToken>(context);
      expect(await authCodeQuery.fetch(), isEmpty);
    });

    test(
        "Code that has been exchanged already fails, issued and refreshed tokens are revoked",
        () async {
      var issuedToken = await auth.exchange(
          code.code, "com.stablekernel.redirect", "mckinley");
      var refreshedToken = await auth.refresh(
          issuedToken.refreshToken, "com.stablekernel.redirect", "mckinley");

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
      } on AuthServerException {}

      // Can no longer use issued token
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      // Can no longer use refreshed token
      try {
        await auth.verify(refreshedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      // Ensure that the associated auth code is also destroyed
      var authCodeQuery = new Query<ManagedAuthToken>(context);
      expect(await authCodeQuery.fetch(), isEmpty);
    });

    test("Null client ID fails", () async {
      try {
        await auth.exchange(code.code, null, "mckinley");

        expect(true, false);
      } on AuthServerException {}
    });

    test("Unknown client ID fails", () async {
      try {
        await auth.exchange(code.code, "nonsense", "mckinley");

        expect(true, false);
      } on AuthServerException {}
    });

    test("Different client ID than the one that generated code fials",
        () async {
      try {
        await auth.exchange(
            code.code, "com.stablekernel.redirect2", "gibraltar");

        expect(true, false);
      } on AuthServerException {}
    });

    test("No client secret fails", () async {
      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", null);

        expect(true, false);
      } on AuthServerException {}
    });

    test("Wrong client secret fails", () async {
      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "nonsense");

        expect(true, false);
      } on AuthServerException {}
    });
  });

  group("Cleanup/friendly fire scenarios from client", () {
    List<User> createdUsers;

    AuthServer auth;

    setUp(() async {
      auth = new AuthServer(storage);
      createdUsers = await createUsers(context, 3);
    });

    test("Revoking a client revokes all of its tokens and auth codes",
        () async {
      var unusedCode = await auth.authenticateForCode(
          createdUsers.first.username,
          User.DefaultPassword,
          "com.stablekernel.redirect");
      var exchangedCode = await auth.authenticateForCode(
          createdUsers.first.username,
          User.DefaultPassword,
          "com.stablekernel.redirect");
      var exchangedToken = await auth.exchange(
          exchangedCode.code, "com.stablekernel.redirect", "mckinley");
      var issuedToken = await auth.authenticate(createdUsers.first.username,
          User.DefaultPassword, "com.stablekernel.redirect", "mckinley");

      expect(await auth.verify(issuedToken.accessToken), isNotNull);

      await auth.removeClient("com.stablekernel.redirect");
      try {
        await auth.exchange(
            unusedCode.code, "com.stablekernel.redirect", "mckinley");
        expect(true, false);
      } on AuthServerException {}

      try {
        await auth.verify(exchangedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      var tokenQuery = new Query<ManagedAuthToken>(context);
      expect(await tokenQuery.fetch(), isEmpty);
    });

    test(
        "Revoking a client does not invalidate tokens or codes issued by other clients",
        () async {
      var exchangedCodeRevoke = await auth.authenticateForCode(
          createdUsers.first.username,
          User.DefaultPassword,
          "com.stablekernel.redirect");
      await auth.authenticateForCode(createdUsers.first.username,
          User.DefaultPassword, "com.stablekernel.redirect");
      await auth.exchange(
          exchangedCodeRevoke.code, "com.stablekernel.redirect", "mckinley");
      await auth.authenticate(createdUsers.first.username, User.DefaultPassword,
          "com.stablekernel.redirect", "mckinley");

      var unusedCodeKeep = await auth.authenticateForCode(
          createdUsers.first.username,
          User.DefaultPassword,
          "com.stablekernel.redirect2");
      var exchangedCodeKeep = await auth.authenticateForCode(
          createdUsers.first.username,
          User.DefaultPassword,
          "com.stablekernel.redirect2");
      var exchangedTokenKeep = await auth.exchange(
          exchangedCodeKeep.code, "com.stablekernel.redirect2", "gibraltar");
      var issuedTokenKeep = await auth.authenticate(createdUsers.first.username,
          User.DefaultPassword, "com.stablekernel.redirect2", "gibraltar");

      await auth.removeClient("com.stablekernel.redirect");

      var exchangedLater = await auth.exchange(
          unusedCodeKeep.code, "com.stablekernel.redirect2", "gibraltar");
      expect(await auth.verify(exchangedLater.accessToken),
          new isInstanceOf<Authorization>());
      expect(await auth.verify(exchangedTokenKeep.accessToken),
          new isInstanceOf<Authorization>());
      expect(await auth.verify(issuedTokenKeep.accessToken),
          new isInstanceOf<Authorization>());

      var tokenQuery = new Query<ManagedAuthToken>(context);
      expect(await tokenQuery.fetch(), hasLength(3));
    });

    test("Clients retain their token ownership", () async {
      var createdUser = createdUsers.first;

      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
      var p1 = await auth.verify(token.accessToken);
      expect(p1.clientID, "com.stablekernel.app1");
      expect(p1.ownerID, createdUser.id);

      var code = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "com.stablekernel.redirect");
      var token2 = await auth.exchange(
          code.code, "com.stablekernel.redirect", "mckinley");

      p1 = await auth.verify(token.accessToken);
      expect(p1.clientID, "com.stablekernel.app1");
      expect(p1.ownerID, createdUser.id);

      var p2 = await auth.verify(token2.accessToken);
      expect(p2.clientID, "com.stablekernel.redirect");
      expect(p2.ownerID, createdUser.id);
    });
  });

  group("Cleanup/friendly fire on Authenticatable", () {
    List<User> createdUsers;

    AuthServer auth;

    setUp(() async {
      auth = new AuthServer(storage);
      createdUsers = await createUsers(context, 3);
    });

    test(
        "After explicitly invoking 'invalidate resource owner' method, all tokens and codes for that resource owner are no longer in db",
        () async {
      var unusedCode = await auth.authenticateForCode(
          createdUsers.first.username,
          User.DefaultPassword,
          "com.stablekernel.redirect");
      var exchangedCode = await auth.authenticateForCode(
          createdUsers.first.username,
          User.DefaultPassword,
          "com.stablekernel.redirect");
      var exchangedToken = await auth.exchange(
          exchangedCode.code, "com.stablekernel.redirect", "mckinley");
      var issuedToken = await auth.authenticate(createdUsers.first.username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");

      expect(await auth.verify(issuedToken.accessToken), isNotNull);

      await auth
          .revokeAllGrantsForResourceOwner(createdUsers.first.id);

      try {
        await auth.exchange(
            unusedCode.code, "com.stablekernel.redirect", "mckinley");
        expect(true, false);
      } on AuthServerException {}


      try {
        await auth.verify(exchangedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      var tokenQuery = new Query<ManagedAuthToken>(context);
      expect(await tokenQuery.fetch(), isEmpty);
    });
  });

  group("Code friendly fire/cleanup", () {
    List<User> createdUsers;

    AuthServer auth;

    setUp(() async {
      var limitedStorage = new ManagedAuthDelegate<User>(context, tokenLimit: 3);
      auth = new AuthServer(limitedStorage);
      createdUsers = await createUsers(context, 3);
    });

    test("Revoking a token automatically deletes the code that generated it",
        () async {
      var exchangedCode = await auth.authenticateForCode(
          createdUsers.first.username,
          User.DefaultPassword,
          "com.stablekernel.redirect");
      var exchangedToken = await auth.exchange(
          exchangedCode.code, "com.stablekernel.redirect", "mckinley");

      var codeQuery = new Query<ManagedAuthToken>(context)
        ..where((o) => o.code).equalTo(exchangedCode.code);
      expect(await codeQuery.fetch(), hasLength(1));

      var tokenQuery = new Query<ManagedAuthToken>(context)
        ..where((o) => o.accessToken).equalTo(exchangedToken.accessToken);
      await tokenQuery.delete();

      expect(await codeQuery.fetch(), isEmpty);
    });

    test(
        "Oldest codes gets pruned after reaching limit, but only for that user",
        () async {
      // Insert a code manually to simulate a race condition, but insert it after the others have been
      // so they don't strip it when inserted.
      var manualCode = new ManagedAuthToken()
        ..code = "ASDFGHJ"
        ..issueDate = new DateTime.now().toUtc()
        ..expirationDate =
            new DateTime.now().add(new Duration(seconds: 60)).toUtc()
        ..client = (new ManagedAuthClient()..id = "com.stablekernel.redirect")
        ..resourceOwner = (new User()..id = createdUsers.first.id);

      // Insert a code for a different user to make sure it doesn't get pruned.
      var otherUserCode = await auth.authenticateForCode(
          createdUsers[1].username,
          User.DefaultPassword,
          "com.stablekernel.redirect");

      // Insert the max number of codes
      var codes = <AuthCode>[];
      for (var i = 0; i < 3; i++) {
        var c = await auth.authenticateForCode(createdUsers.first.username,
            User.DefaultPassword, "com.stablekernel.redirect");
        codes.add(c);
      }

      // Insert the 'race condition' code
      var manualInsertQuery = new Query<ManagedAuthToken>(context)..values = manualCode;
      manualCode = await manualInsertQuery.insert();

      // Make a new code, should kill the race condition code and the first generated code in the loop.
      // Other user codes remain
      var newCode = await auth.authenticateForCode(createdUsers.first.username,
          User.DefaultPassword, "com.stablekernel.redirect");
      var codeQuery = new Query<ManagedAuthToken>(context);
      var codesInDB = (await codeQuery.fetch()).map((ac) => ac.code).toList();

      // These codes are in chronological order
      expect(codesInDB.contains(otherUserCode.code), true);

      expect(codesInDB.contains(manualCode.code), false);
      expect(codesInDB.contains(codes.first.code), false);
      expect(codesInDB.contains(codes[1].code), true);
      expect(codesInDB.contains(codes.last.code), true);
      expect(codesInDB.contains(newCode.code), true);

      // Make a new code, but with a different client, should still kill off the oldest expiring code.
      var lastCode = await auth.authenticateForCode(createdUsers.first.username,
          User.DefaultPassword, "com.stablekernel.redirect2");
      codesInDB = (await codeQuery.fetch()).map((ac) => ac.code).toList();

      // These codes are in chronological order
      expect(codesInDB.contains(otherUserCode.code), true);

      expect(codesInDB.contains(codes[1].code), false);
      expect(codesInDB.contains(codes.last.code), true);
      expect(codesInDB.contains(newCode.code), true);
      expect(codesInDB.contains(lastCode.code), true);
    });
  });

  group("Token friendly fire/cleanup", () {
    List<User> createdUsers;

    AuthServer auth;

    setUp(() async {
      var limitedStorage = new ManagedAuthDelegate<User>(context, tokenLimit: 3);
      auth = new AuthServer(limitedStorage);
      createdUsers = await createUsers(context, 10);
    });

    test(
        "Oldest tokens gets pruned after reaching tokenLimit, but only for that user",
        () async {
      // Insert a token manually to simulate a race condition, but insert it after the others have been
      // so they don't strip it when inserted.
      var manualToken = new ManagedAuthToken()
        ..accessToken = "ASDFGHJ"
        ..refreshToken = "ABCHASDS"
        ..issueDate = new DateTime.now().toUtc()
        ..expirationDate =
            new DateTime.now().add(new Duration(seconds: 60)).toUtc()
        ..client = (new ManagedAuthClient()..id = "com.stablekernel.app1")
        ..resourceOwner = (new User()..id = createdUsers.first.id);

      // Insert a token for a different user to make sure it doesn't get pruned.
      var otherUserToken = await auth.authenticate(createdUsers[1].username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");

      // Insert the max number of token
      var tokens = <AuthToken>[];
      for (var i = 0; i < 3; i++) {
        var c = await auth.authenticate(createdUsers.first.username,
            User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
        tokens.add(c);
      }

      // Insert the 'race condition' token
      var manualInsertQuery = new Query<ManagedAuthToken>(context)..values = manualToken;
      manualToken = await manualInsertQuery.insert();

      // Make a new token, should kill the race condition token and the first generated token in the loop.
      // Other user token remain
      var newToken = await auth.authenticate(createdUsers.first.username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
      var tokenQuery = new Query<ManagedAuthToken>(context);
      var tokensInDB =
          (await tokenQuery.fetch()).map((ac) => ac.accessToken).toList();

      // These token are in chronological order
      expect(tokensInDB.contains(otherUserToken.accessToken), true);

      expect(tokensInDB.contains(manualToken.accessToken), false);
      expect(tokensInDB.contains(tokens.first.accessToken), false);
      expect(tokensInDB.contains(tokens[1].accessToken), true);
      expect(tokensInDB.contains(tokens.last.accessToken), true);
      expect(tokensInDB.contains(newToken.accessToken), true);

      // Make a new token, but with a different client, should still kill off the oldest token code.
      var lastToken = await auth.authenticate(createdUsers.first.username,
          User.DefaultPassword, "com.stablekernel.app2", "fuji");
      tokensInDB =
          (await tokenQuery.fetch()).map((ac) => ac.accessToken).toList();

      // These token are in chronological order
      expect(tokensInDB.contains(otherUserToken.accessToken), true);

      expect(tokensInDB.contains(tokens[1].accessToken), false);
      expect(tokensInDB.contains(tokens.last.accessToken), true);
      expect(tokensInDB.contains(newToken.accessToken), true);
      expect(tokensInDB.contains(lastToken.accessToken), true);
    });

    test("Ensure users aren't authenticated by other users", () async {
      var t1 = await auth.authenticate(createdUsers[0].username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
      var t2 = await auth.authenticate(createdUsers[4].username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");

      var permission = await auth.verify(t1.accessToken);
      expect(permission.clientID, "com.stablekernel.app1");
      expect(permission.ownerID, createdUsers[0].id);

      permission = await auth.verify(t2.accessToken);
      expect(permission.clientID, "com.stablekernel.app1");
      expect(permission.ownerID, createdUsers[4].id);
    });

    test(
        "Revoking tokens/codes for Authenticatable does not impact other Authenticatables",
        () async {
      var t1 = await auth.authenticate(createdUsers[0].username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
      var t2 = await auth.authenticate(createdUsers[4].username,
          User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");

      await auth.revokeAllGrantsForResourceOwner(createdUsers[0].id);
      expect(await auth.verify(t2.accessToken), isNotNull);

      try {
        await auth.verify(t1.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });
  });

  group("Scoping cases", () {
    AuthServer auth;
    User createdUser;
    setUp(() async {
      auth = new AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;

      var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";

      var clients = [
        new AuthClient.public("all", allowedScopes: [
          new AuthScope("user"),
          new AuthScope("location:add"),
          new AuthScope("admin:settings.readonly")
        ]),
        new AuthClient.public("subset", allowedScopes: [
          new AuthScope("user.readonly"),
          new AuthScope("location:view")
        ]),
        new AuthClient.public("subset.multiple", allowedScopes: [
          new AuthScope("user:a"),
          new AuthScope("user:b")
        ]),
        new AuthClient.withRedirectURI("all.redirect",
            AuthUtility.generatePasswordHash("a", salt), salt, "http://a.com", allowedScopes: [
              new AuthScope("user"),
              new AuthScope("location:add"),
              new AuthScope("admin:settings.readonly")
            ]),
        new AuthClient.withRedirectURI("subset.redirect",
            AuthUtility.generatePasswordHash("b", salt), salt, "http://b.com", allowedScopes: [
              new AuthScope("user.readonly"),
              new AuthScope("location:view")
            ]),
      ];

      await Future.wait(clients
          .map((ac) => new ManagedAuthClient()
            ..id = ac.id
            ..salt = ac.salt
            ..allowedScope = ac.allowedScopes.map((a) => a.toString()).join(" ")
            ..hashedSecret = ac.hashedSecret
            ..redirectURI = ac.redirectURI)
          .map((mc) {
        var q = new Query<ManagedAuthClient>(context)..values = mc;
        return q.insert();
      }));
    });

    // -- Password grant --

    test("Client can issue tokens for valid scope, only include specified scope", () async {
      var token1 = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all", null, requestedScopes: [
            new AuthScope("user")
          ]);

      expect(token1.scopes.length, 1);
      expect(token1.accessToken, isNotNull);
      expect(token1.scopes.first.isExactly("user"), true);

      var token2 = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all", null, requestedScopes: [
            new AuthScope("user:sub")
          ]);

      expect(token2.scopes.length, 1);
      expect(token2.accessToken, isNotNull);
      expect(token2.scopes.first.isExactly("user:sub"), true);
    });

    test("Client can request multiple scopes and if all are valid, get token and all specified scopes", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all", null, requestedScopes: [
            new AuthScope("user"),
            new AuthScope("location:add")
          ]);

      expect(token.scopes.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user")), true);
      expect(token.scopes.any((s) => s.isExactly("location:add")), true);
    });

    test("Client that requests multiple scopes for token where one is not valid, only get valid scopes", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all", null, requestedScopes: [
            new AuthScope("user"),
            new AuthScope("unknown")
          ]);

      expect(token.scopes.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user")), true);
    });

    test("Client that requests multiple scopes where they are subsets of valid scopes, gets subsets back", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all", null, requestedScopes: [
            new AuthScope("user:sub"),
            new AuthScope("location:add:sub")
          ]);

      expect(token.scopes.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user:sub")), true);
      expect(token.scopes.any((s) => s.isExactly("location:add:sub")), true);
    });

    test("Client that requests allowed nested scope gets token", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "subset.multiple", null, requestedScopes: [
            new AuthScope("user:a"),
          ]);
      expect(token.scopes.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user:a")), true);

      token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "subset.multiple", null, requestedScopes: [
            new AuthScope("user:b"),
          ]);
      expect(token.scopes.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user:b")), true);

      try {
        var _ = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "subset.multiple", null, requestedScopes: [
            new AuthScope("user"),
          ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Client will reject token request for unknown scope", () async {
      try {
        var _ = await auth.authenticate(createdUser.username,
            User.DefaultPassword, "all", null, requestedScopes: [
              new AuthScope("unknown")
            ]);

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Client will reject token request for scope with too high of privileges", () async {
      try {
        var _ = await auth.authenticate(createdUser.username,
            User.DefaultPassword, "all", null, requestedScopes: [
              new AuthScope("location")
            ]);

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Client will reject token request for scope that has limiting modifier", () async {
      try {
        var _ = await auth.authenticate(createdUser.username,
            User.DefaultPassword, "all", null, requestedScopes: [
              new AuthScope("admin:settings")
            ]);

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    // --- Refresh ---

    test("Refresh token without scope specified returns same scope", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all.redirect", "a", requestedScopes: [
            new AuthScope("user"),
            new AuthScope("location:add")
          ]);

      token = await auth.refresh(token.refreshToken, "all.redirect", "a");
      expect(token.scopes.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user")), true);
      expect(token.scopes.any((s) => s.isExactly("location:add")), true);
    });

    test("Refresh token with lesser scope specified returns specified scope", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all.redirect", "a", requestedScopes: [
            new AuthScope("user"),
            new AuthScope("location:add")
          ]);

      token = await auth.refresh(token.refreshToken, "all.redirect", "a", requestedScopes: [
        new AuthScope("user"),
        new AuthScope("location:add.modifier")
      ]);
      expect(token.scopes.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user")), true);
      expect(token.scopes.any((s) => s.isExactly("location:add.modifier")), true);

      token = await auth.refresh(token.refreshToken, "all.redirect", "a", requestedScopes: [
        new AuthScope("user:under"),
      ]);
      expect(token.scopes.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user:under")), true);
    });

    test("Refresh token with new, valid scope fails because refresh can't upgrade scope", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all.redirect", "a", requestedScopes: [
            new AuthScope("user"),
            new AuthScope("location:add")
          ]);

      try {
        var _ = await auth.refresh(token.refreshToken, "all.redirect", "a", requestedScopes: [
          new AuthScope("user"),
          new AuthScope("location:add"),
          new AuthScope("admin:settings.readonly")
        ]);

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Refresh token request with higher privileged scope does not include that scope because refresh can't upgrade scope", () async {
      var token = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all.redirect", "a", requestedScopes: [
            new AuthScope("user:foo"),
            new AuthScope("location:add")
          ]);

      try {
        var _ = await auth.refresh(token.refreshToken, "all.redirect", "a", requestedScopes: [
          new AuthScope("user")
        ]);

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Refresh token request after client has been modified to limit previous granted scope fails", () async {
      // token1 will have explicit refresh scope, token2 will have implicit refresh scope
      var token1 = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all.redirect", "a", requestedScopes: [
            new AuthScope("user"),
            new AuthScope("location:add")
          ]);
      var token2 = await auth.authenticate(createdUser.username,
          User.DefaultPassword, "all.redirect", "a", requestedScopes: [
            new AuthScope("user"),
            new AuthScope("location:add")
          ]);

      var q = new Query<ManagedAuthClient>(context)
        ..where((o) => o.id).equalTo("all.redirect")
        ..values.allowedScope = "user location:add.readonly";
      await q.updateOne();

      try {
        var _ = await auth.refresh(token1.refreshToken, "all.redirect", "a", requestedScopes: [
          new AuthScope("user"),
          new AuthScope("location:add")
        ]);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }

      try {
        var _ = await auth.refresh(token2.refreshToken, "all.redirect", "a");
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    // --- Auth code ---

    test("Client can issue auth code for valid scope", () async {
      var code1 = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "all.redirect", requestedScopes: [
            new AuthScope("user")
          ]);
      var token1 = await auth.exchange(code1.code, "all.redirect", "a");

      expect(token1.scopes.length, 1);
      expect(token1.accessToken, isNotNull);
      expect(token1.scopes.first.isExactly("user"), true);

      var code2 = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "all.redirect", requestedScopes: [
            new AuthScope("user:sub")
          ]);
      var token2 = await auth.exchange(code2.code, "all.redirect", "a");

      expect(token2.scopes.length, 1);
      expect(token2.accessToken, isNotNull);
      expect(token2.scopes.first.isExactly("user:sub"), true);
    });

    test("Client that requests multiple scopes for auth code where they are subsets of valid scopes, gets subsets back", () async {
      var code = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "all.redirect", requestedScopes: [
            new AuthScope("user:sub"),
            new AuthScope("location:add:sub")
          ]);
      var token = await auth.exchange(code.code, "all.redirect", "a");

      expect(token.scopes.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user:sub")), true);
      expect(token.scopes.any((s) => s.isExactly("location:add:sub")), true);
    });

    test("Client can request multiple scopes and if all are valid, get auth code", () async {
      var code = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "all.redirect", requestedScopes: [
            new AuthScope("user"),
            new AuthScope("location:add")
          ]);

      var token = await auth.exchange(code.code, "all.redirect", "a");

      expect(token.scopes.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user")), true);
      expect(token.scopes.any((s) => s.isExactly("location:add")), true);
    });

    test("Client that requests multiple scopes for auth code where one is not valid, only get valid scopes", () async {
      var code = await auth.authenticateForCode(createdUser.username,
          User.DefaultPassword, "all.redirect", requestedScopes: [
            new AuthScope("user"),
            new AuthScope("unknown")
          ]);

      var token = await auth.exchange(code.code, "all.redirect", "a");
      expect(token.scopes.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes.any((s) => s.isExactly("user")), true);
    });

    test("Client will reject auth code request for unknown scope", () async {
      try {
        var _ = await auth.authenticateForCode(createdUser.username,
            User.DefaultPassword, "all.redirect", requestedScopes: [
              new AuthScope("unknown")
            ]);

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Client will reject auth code request for scope with too high of privileges", () async {
      try {
        var _ = await auth.authenticateForCode(createdUser.username,
            User.DefaultPassword, "all.redirect", requestedScopes: [
              new AuthScope("location")
            ]);

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Client will reject auth code request for scope that has limiting modifier", () async {
      try {
        var _ = await auth.authenticateForCode(createdUser.username,
            User.DefaultPassword, "all.redirect", requestedScopes: [
              new AuthScope("admin:settings")
            ]);

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });
  });
}

class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner<_User> {
  static const String DefaultPassword = "foobaraxegrind!%12";
}

class _User extends ResourceOwnerTableDefinition {}

Future<List<User>> createUsers(ManagedContext ctx, int count) async {
  var list = <User>[];
  for (int i = 0; i < count; i++) {
    var salt = AuthUtility.generateRandomSalt();
    var u = new User()
      ..username = "bob+$i@stablekernel.com"
      ..salt = salt
      ..hashedPassword =
          AuthUtility.generatePasswordHash(User.DefaultPassword, salt);

    var q = new Query<User>(ctx)..values = u;

    list.add(await q.insert());
  }
  return list;
}