import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:io';
import '../helpers.dart';

void main() {
  ManagedContext context = null;
  AuthDelegate delegate;

  setUp(() async {
    context = await contextWithModels([TestUser, Token, AuthCode]);
    delegate = new AuthDelegate(context);
  });

  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Generate and verify a auth code", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    TestUser createdUser = (await createUsers(1)).first;

    var authCode = await auth.createAuthCode(
        "bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.redirect");

    expect(authCode.code.length, greaterThan(0));

    var permission = await auth.verifyCode(authCode.code);
    expect(permission.clientID, "com.stablekernel.redirect");
    expect(permission.resourceOwnerIdentifier, createdUser.id);
  });

  test("Generate auth code with bad user data fails", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    await createUsers(1);

    var successful = false;
    try {
      // Bad username
      await auth.createAuthCode(
          "bob+0@stable", "foobaraxegrind21%", "com.stablekernel.redirect");
      successful = true;
    } catch (e) {
      expect(e.statusCode, HttpStatus.BAD_REQUEST);
    }
    expect(successful, false);

    try {
      // Bad password
      await auth.createAuthCode(
          "bob+0@stablekernel.com", "foobaraxegri%", "com.stablekernel.redirect");
      successful = true;
    } catch (e) {
      expect(e.statusCode, HttpStatus.UNAUTHORIZED);
    }
    expect(successful, false);

    try {
      // Bad client id
      await auth.createAuthCode(
          "bob+0@stablekernel.com", "foobaraxegrind21%", "com.stabl");
      successful = true;
    } catch (e) {
      expect(e.statusCode, HttpStatus.UNAUTHORIZED);
    }
    expect(successful, false);
  });

  test("Exchange auth code for token", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    TestUser createdUser = (await createUsers(1)).first;

    var authCode = await auth.createAuthCode(
        "bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.redirect");
    var token =
        await auth.exchange(authCode.code, "com.stablekernel.redirect", "mckinley");

    expect(token.accessToken.length, greaterThan(0));
    expect(token.refreshToken.length, greaterThan(0));
    expect(token.type, "bearer");

    var permission = await auth.verify(token.accessToken);
    expect(permission.clientID, "com.stablekernel.redirect");
    expect(permission.resourceOwnerIdentifier, createdUser.id);

    var successful = false;
    try {
      permission = await auth.verify("foobar");
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);
  });

  test("Auth code only usable once", () async {
    await createUsers(1);
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);

    var authCode = await auth.createAuthCode(
        "bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.redirect");
    var token1 =
        await auth.exchange(authCode.code, "com.stablekernel.redirect", "mckinley");

    expect(token1, isNotNull);
    var token2 = null;
    try {
      token2 = await auth.exchange(
          authCode.code, "com.stablekernel.redirect", "mckinley");
    } catch (e) {
      expect(e.statusCode, HttpStatus.UNAUTHORIZED);
    }

    expect(token2, isNull);

    // Original token should now also be invalid
    try {
      var permission = await auth.verify(token1.accessToken);
      expect(permission, isNotNull);
    } catch (e) {
      expect(e.statusCode, HttpStatus.UNAUTHORIZED);
    }
  });

  test("Auth code unusable after expiration", () async {
    await createUsers(1);
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);

    var authCode = await auth.createAuthCode(
        "bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.redirect",
        expirationInSeconds: 1);
    sleep(new Duration(seconds: 2));

    var token = null;
    try {
      await auth.exchange(authCode.code, "com.stablekernel.redirect", "mckinley");
    } catch (e) {
      expect(e.statusCode, HttpStatus.UNAUTHORIZED);
    }
    expect(token, isNull);
  });

  test("Auth code unusable by other client", () async {
    await createUsers(1);
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);

    var authCode = await auth.createAuthCode(
        "bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.redirect");

    var token = null;
    try {
      token = await auth.exchange(
          authCode.code, "com.stablekernel.app1", "kilimanjaro");
    } catch (e) {
      expect(e.statusCode, HttpStatus.UNAUTHORIZED);
    }
    expect(token, isNull);
  });

  test("Auth code generation fails when client has no redirect URI", () async {
    await createUsers(1);
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);

    var authCode = null;
    try {
      authCode = await auth.createAuthCode("bob+0@stablekernel.com",
          "foobaraxegrind21%", "com.stablekernel.app1");
    } catch (e) {
      expect(e.statusCode, HttpStatus.INTERNAL_SERVER_ERROR);
    }
    expect(authCode, isNull);
  });

  test("Generate and verify token", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    TestUser createdUser = (await createUsers(1)).first;

    var token = await auth.authenticate("bob+0@stablekernel.com",
        "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");

    expect(token.accessToken.length, greaterThan(0));
    expect(token.refreshToken.length, greaterThan(0));
    expect(token.type, "bearer");

    var permission = await auth.verify(token.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.resourceOwnerIdentifier, createdUser.id);

    var successful = false;
    try {
      permission = await auth.verify("foobar");
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);
  });

  test("Bad client ID and secret fails", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    await createUsers(1);

    var successful = false;
    try {
      await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%",
          "com.stablekernel.app20", "kilimanjaro");
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);

    try {
      await auth.authenticate("bob0@stablekernel.com", "foobaraxegrind21%",
          "com.stablekernel.app1", "foobar");
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);
  });

  test("Invalid username and password fails", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    await createUsers(1);

    var successful = false;
    try {
      await auth.authenticate("fred@stablekernel.com", "foobaraxegrind21%",
          "com.stablekernel.app1", "kilimanjaro");
      successful = true;
    } catch (e) {
      expect(e.statusCode, 400);
    }
    expect(successful, false);

    try {
      await auth.authenticate("bob+0@stablekernel.com", "foobar",
          "com.stablekernel.app1", "kilimanjaro");
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    successful = false;
  });

  test("Expiration date works correctly", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    await createUsers(1);
    var t = await auth.authenticate("bob+0@stablekernel.com",
        "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro",
        expirationInSeconds: 5);

    var p1 = await auth.verify(t.accessToken);
    expect(p1.resourceOwnerIdentifier, greaterThan(0));

    sleep(new Duration(seconds: 5));

    var successful = false;
    try {
      await auth.verify(t.accessToken);
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);
  });

  test("Clients have separate tokens", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);

    TestUser createdUser = (await createUsers(1)).first;

    var token = await auth.authenticate("bob+0@stablekernel.com",
        "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");
    var p1 = await auth.verify(token.accessToken);
    expect(p1.clientID, "com.stablekernel.app1");
    expect(p1.resourceOwnerIdentifier, createdUser.id);

    var token2 = await auth.authenticate("bob+0@stablekernel.com",
        "foobaraxegrind21%", "com.stablekernel.app2", "fuji");
    var p2 = await auth.verify(token2.accessToken);
    expect(p2.clientID, "com.stablekernel.app2");
    expect(p2.resourceOwnerIdentifier, createdUser.id);

    p1 = await auth.verify(token.accessToken);
    expect(p1.clientID, "com.stablekernel.app1");
    expect(p1.resourceOwnerIdentifier, createdUser.id);
  });

  test("Ensure users aren't authenticated by other users", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    var users = await createUsers(10);
    var t1 = await auth.authenticate("bob+0@stablekernel.com",
        "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");
    var t2 = await auth.authenticate("bob+4@stablekernel.com",
        "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");

    var permission = await auth.verify(t1.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.resourceOwnerIdentifier, users[0].id);

    permission = await auth.verify(t2.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.resourceOwnerIdentifier, users[4].id);
  });

  test("Refresh token works correctly", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    TestUser user = (await createUsers(1)).first;

    var t1 = await auth.authenticate("bob+0@stablekernel.com",
        "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");
    var t2 = await auth.authenticate("bob+0@stablekernel.com",
        "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro",
        expirationInSeconds: 5);

    var p1 = await auth.verify(t1.accessToken);
    expect(p1.resourceOwnerIdentifier, user.id);
    var p2 = await auth.verify(t2.accessToken);
    expect(p2.resourceOwnerIdentifier, user.id);

    sleep(new Duration(seconds: 5));

    var successful = false;
    try {
      await auth.verify(t2.accessToken);
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);

    var n1 = await auth.refresh(
        t1.refreshToken, "com.stablekernel.app1", "kilimanjaro");
    var n2 = await auth.refresh(
        t2.refreshToken, "com.stablekernel.app1", "kilimanjaro");
    expect(n1.accessToken != t1.accessToken, true);
    expect(n2.accessToken != t2.accessToken, true);

    p1 = await auth.verify(n1.accessToken);
    p2 = await auth.verify(n2.accessToken);
    expect(p1.resourceOwnerIdentifier, user.id);
    expect(p2.resourceOwnerIdentifier, user.id);

    try {
      await auth.verify(t1.accessToken);
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);

    try {
      await auth.verify(t2.accessToken);
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);

    sleep(new Duration(seconds: 5));

    p1 = await auth.verify(n1.accessToken);
    expect(p1.resourceOwnerIdentifier, user.id);
    try {
      await auth.verify(t2.accessToken);
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);
  });

  test("Refresh token doesn't work on wrong client id", () async {
    var auth = new AuthServer<TestUser, Token, AuthCode>(delegate);
    await createUsers(1);

    var t1 = await auth.authenticate("bob+0@stablekernel.com",
        "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");
    var successful = false;
    try {
      await auth.refresh(t1.refreshToken, "com.stablekernel.app2", "fuji");
      successful = true;
    } catch (e) {
      expect(e.statusCode, 401);
    }
    expect(successful, false);
  });

  test("Tokens get pruned", () async {fail("NYI");});

  test(
      "Multiple clients can authenticate with same resource owner at same time",
          () async {});

}
