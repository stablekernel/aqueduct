import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';
import 'package:test/test.dart';

import '../context_helpers.dart';

// These tests mostly duplicate authenticate_test.dart, but also add a few more
// to manage long-term storage/cleanup of tokens and related items.
void main() {
  ManagedAuthStorage<User> storage;

  setUp(() async {
    var context = await contextWithModels([User, ManagedClient, ManagedAuthCode, ManagedToken]);

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
      new AuthClient("com.stablekernel.public", null, salt),
      new AuthClient.withRedirectURI(
          "com.stablekernel.redirect2",
          AuthUtility.generatePasswordHash("gibraltar", salt),
          salt,
          "http://stablekernel.com/auth/redirect2")
      ];

    await Future.wait(clients
      .map((ac) => new ManagedClient()
        ..id = ac.id
        ..salt = ac.salt
        ..hashedSecret = ac.hashedSecret
        ..redirectURI = ac.redirectURI)
      .map((mc) {
        var q = new Query<ManagedClient>()
          ..values = mc;
        return q.insert();
      }));

    storage = new ManagedAuthStorage<User>(context);
  });

  group("Client behavior", () {
    AuthServer auth;

    setUp(() async {
      auth = new AuthServer(storage);
    });

    test("Get client for ID", () async {
      var c = await auth.clientForID("com.stablekernel.app1");
      expect(c is AuthClient, true);
    });

    test("Revoked client can no longer be accessed", () async {
      expect((await auth.clientForID("com.stablekernel.app1")) is AuthClient, true);
      await auth.revokeClientID("com.stablekernel.app1");
      expect(await auth.clientForID("com.stablekernel.app1"), isNull);
    });
  });

  group("Token behavior via authenticate", () {
    AuthServer auth;
    User createdUser;
    setUp(() async {
      auth = new AuthServer(storage);
      createdUser = (await createUsers(1)).first;
    });

    test("Can create token with all information + refresh token if client is confidential", () async {
      var token = await auth.authenticate(
          createdUser.username, User.DefaultPassword,
          "com.stablekernel.app1", "kilimanjaro");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.app1");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.issueDate.isBefore(new DateTime.now().toUtc()), true);
      expect(token.expirationDate.isAfter(new DateTime.now().toUtc()), true);
      expect(token.type, "bearer");
    });

    test("Can create token with all information minus refresh token if client is public", () async {
      var token = await auth.authenticate(
          createdUser.username, User.DefaultPassword,
          "com.stablekernel.public", "");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isNull);
      expect(token.clientID, "com.stablekernel.public");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.issueDate.isBefore(new DateTime.now().toUtc()), true);
      expect(token.expirationDate.isAfter(new DateTime.now().toUtc()), true);
      expect(token.type, "bearer");

      token = await auth.authenticate(
          createdUser.username, User.DefaultPassword,
          "com.stablekernel.public", null);
      expect(token.accessToken, isString);
      expect(token.refreshToken, isNull);
      expect(token.clientID, "com.stablekernel.public");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.issueDate.isBefore(new DateTime.now().toUtc()), true);
      expect(token.expirationDate.isAfter(new DateTime.now().toUtc()), true);
      expect(token.type, "bearer");
    });

    test("Create token fails if username is incorrect", () async {
      try {
        await auth.authenticate(
            "nonsense", User.DefaultPassword,
            "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Create token fails if password is incorrect", () async {
      try {
        await auth.authenticate(
            createdUser.username, "nonsense",
            "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Create token fails if client ID doesn't exist", () async {
      try {
        await auth.authenticate(
            createdUser.username, User.DefaultPassword,
            "nonsense", "kilimanjaro");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Create token fails if client secret doesn't match", () async {
      try {
        await auth.authenticate(
            createdUser.username, User.DefaultPassword,
            "com.stablekernel.app1", "nonsense");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Create token fails if client ID is confidential and secret is omitted", () async {
      try {
        await auth.authenticate(
            createdUser.username, User.DefaultPassword,
            "com.stablekernel.app1", null);
        expect(true, false);
      } on AuthServerException {}

      try {
        await auth.authenticate(
            createdUser.username, User.DefaultPassword,
            "com.stablekernel.app1", "");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Create token fails if client secret provided for public client", () async {
      try {
        await auth.authenticate(
            createdUser.username, User.DefaultPassword,
            "com.stablekernel.public", "nonsense");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Can create token that is verifiable", () async {
      var token = await auth.authenticate(
          createdUser.username, User.DefaultPassword,
          "com.stablekernel.app1", "kilimanjaro");
      expect((await auth.verify(token.accessToken)) is Authorization, true);
    });

    test("Cannot verify token that doesn't exist", () async {
      try {
        await auth.verify("nonsense");
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client, isNull);
        expect(e.reason, AuthRequestError.invalidToken);
      }
    });

    test("Expired token cannot be verified", () async {
      var token = await auth.authenticate(
          createdUser.username, User.DefaultPassword,
          "com.stablekernel.app1", "kilimanjaro",
          expirationInSeconds: 1);

      sleep(new Duration(seconds: 1));

      try {
        await auth.verify(token.accessToken);
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidToken);
      }
    });
  });

  group("Refreshing token", () {
    AuthServer auth;
    User createdUser;
    AuthToken initialToken;

    setUp(() async {
      auth = new AuthServer(storage);
      createdUser = (await createUsers(1)).first;
      initialToken = await auth.authenticate(
          createdUser.username, User.DefaultPassword,
          "com.stablekernel.app1", "kilimanjaro");
    });

    test("Can refresh token with all information + refresh token if token had refresh token", () async {
      var token = await auth.refresh(initialToken.refreshToken, "com.stablekernel.app1", "kilimanjaro");
      expect(token.accessToken, isNot(initialToken.accessToken));
      expect(token.refreshToken, initialToken.refreshToken);
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.app1");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.issueDate.isBefore(new DateTime.now().toUtc()), true);
      expect(token.expirationDate.isAfter(new DateTime.now().toUtc()), true);
      expect(token.type, "bearer");

      expect(token.issueDate.isAfter(initialToken.issueDate), true);
      expect(token.issueDate.difference(token.expirationDate), initialToken.issueDate.difference(initialToken.expirationDate));

      var authorization = await auth.verify(token.accessToken);
      expect(authorization.clientID, "com.stablekernel.app1");
      expect(authorization.resourceOwnerIdentifier, initialToken.resourceOwnerIdentifier);

      try {
        await auth.verify(initialToken.accessToken);
        expect(true, false);
      } on AuthServerException {}
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

    test("Cannot refresh token if client id does not match issuing client", () async {
      try {
        await auth.refresh(initialToken.refreshToken, "com.stablekernel.app2", "fuji");
        expect(true, false);
      } on AuthServerException {}
    });

    test("Cannot refresh token if client secret is missing", () async {
      try {
        await auth.refresh(initialToken.refreshToken, "com.stablekernel.app1", null);
        expect(true, false);
      } on AuthServerException {}
    });

    test("Cannot refresh token if client secret is incorrect", () async {
      try {
        await auth.refresh(initialToken.refreshToken, "com.stablekernel.app1", "nonsense");
        expect(true, false);
      } on AuthServerException {}
    });
  });


  group("Generating auth code", () {
    AuthServer auth;
    User createdUser;

    setUp(() async {
      auth = new AuthServer(storage);
      createdUser = (await createUsers(1)).first;
    });

    test("Can create an auth code that can be exchanged for a token", () async {
      var authCode = await auth.authenticateForCode(
          createdUser.username,  User.DefaultPassword, "com.stablekernel.redirect");

      expect(authCode.code.length, greaterThan(0));
      expect(authCode.issueDate.isBefore(new DateTime.now().toUtc()), true);
      expect(authCode.resourceOwnerIdentifier, createdUser.id);
      expect(authCode.clientID, "com.stablekernel.redirect");
      expect(authCode.expirationDate.isAfter(new DateTime.now().toUtc()), true);
      expect(authCode.tokenIdentifier, isNull);

      var redirectURI = (await auth.clientForID("com.stablekernel.redirect")).redirectURI;
      expect(authCode.redirectURI, redirectURI);

      var token = await auth.exchange(authCode.code, "com.stablekernel.redirect", "mckinley");
      expect(token.accessToken, isString);
      expect(token.clientID, "com.stablekernel.redirect");
      expect(token.refreshToken, isString);
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");
      expect(token.expirationDate.difference(new DateTime.now().toUtc()).inSeconds, greaterThan(3500));
      expect(token.issueDate.difference(new DateTime.now().toUtc()).inSeconds.abs(), lessThan(2));
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
        await auth.authenticateForCode(
            createdUser.username, User.DefaultPassword, "com.stablekernel.app1");
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
  });

  group("Exchanging auth code", () {
    AuthServer auth;
    User createdUser;
    AuthCode code;

    setUp(() async {
      auth = new AuthServer(storage);
      createdUser = (await createUsers(1)).first;
      code = await auth.authenticateForCode(
          createdUser.username, User.DefaultPassword, "com.stablekernel.redirect");;
    });

    test("Can create an auth code that can be exchanged for a token", () async {
      var token = await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.redirect");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.issueDate.isBefore(new DateTime.now().toUtc()), true);
      expect(token.expirationDate.isAfter(new DateTime.now().toUtc()), true);
      expect(token.type, "bearer");
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

    test("Expired code fails", () async {
      code = await auth.authenticateForCode(
          createdUser.username, User.DefaultPassword, "com.stablekernel.redirect", expirationInSeconds: 1);

      sleep(new Duration(seconds: 1));

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
      } on AuthServerException {}
    });

    test("Code that has been exchanged already fails, issued token is revoked", () async {
      justLogEverything();
      var issuedToken = await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
      } on AuthServerException {}

      // Can no longer use issued token
      try {
        await auth.verify(issuedToken.accessToken);
        expect(true, false);
      } on AuthServerException {}
    });

    test("Code that has been exchanged already fails, issued and refreshed token is revoked", () async {
      var issuedToken = await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");
      var refreshedToken = await auth.refresh(issuedToken.refreshToken, "com.stablekernel.redirect", "mckinley");

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
      } on AuthServerException {}

      // Can no longer use issued token
      try {
        await auth.verify(issuedToken.accessToken);
        expect(true, false);
      } on AuthServerException {}

      try {
        await auth.verify(refreshedToken.accessToken);
        expect(true, false);
      } on AuthServerException {}
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

    test("Different client ID than the one that generated code fials", () async {
      try {
        await auth.exchange(code.code, "com.stablekernel.redirect2", "gibraltar");

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

  group("Scoping use cases", () {


  });

  test("Clients have separate tokens", () async {
    var auth = new AuthServer(storage);

    var createdUser = (await createUsers(1)).first;

    var token = await auth.authenticate("bob+0@stablekernel.com",
        User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
    var p1 = await auth.verify(token.accessToken);
    expect(p1.clientID, "com.stablekernel.app1");
    expect(p1.resourceOwnerIdentifier, createdUser.id);

    var token2 = await auth.authenticate("bob+0@stablekernel.com",
        User.DefaultPassword, "com.stablekernel.app2", "fuji");
    var p2 = await auth.verify(token2.accessToken);
    expect(p2.clientID, "com.stablekernel.app2");
    expect(p2.resourceOwnerIdentifier, createdUser.id);

    p1 = await auth.verify(token.accessToken);
    expect(p1.clientID, "com.stablekernel.app1");
    expect(p1.resourceOwnerIdentifier, createdUser.id);
  });

  test("Ensure users aren't authenticated by other users", () async {
    var auth = new AuthServer(storage);
    var users = await createUsers(10);
    var t1 = await auth.authenticate("bob+0@stablekernel.com",
        User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");
    var t2 = await auth.authenticate("bob+4@stablekernel.com",
        User.DefaultPassword, "com.stablekernel.app1", "kilimanjaro");

    var permission = await auth.verify(t1.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.resourceOwnerIdentifier, users[0].id);

    permission = await auth.verify(t2.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.resourceOwnerIdentifier, users[4].id);
  });

  // Delete user wipes tokens?
}

class User extends ManagedObject<_User> implements _User, AuthenticatableManagedObject {
  static const String DefaultPassword = "foobaraxegrind!%12";

  @override
  dynamic get uniqueIdentifier => id;

  String get username => email;
  set username(String un) {
    email = un;
  }
}

class _User {
  @managedPrimaryKey
  int id;

  String hashedPassword;
  String salt;

  String email;
}

Future<List<User>> createUsers(int count) async {
  var list = <User>[];
  for (int i = 0; i < count; i++) {
    var salt = AuthUtility.generateRandomSalt();
    var u = new User()
      ..email = "bob+$i@stablekernel.com"
      ..salt = salt
      ..hashedPassword = AuthUtility.generatePasswordHash(User.DefaultPassword, salt);

    var q = new Query<User>()
      ..values = u;

    list.add(await q.insert());
  }
  return list;
}

justLogEverything() {
  hierarchicalLoggingEnabled = true;
  new Logger("")
    ..level = Level.ALL
    ..onRecord.listen((p) => print("${p} ${p.object} ${p.stackTrace}"));
}
