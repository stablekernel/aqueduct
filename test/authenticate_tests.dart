import 'package:inquirer_pgsql/inquirer_pgsql.dart';
import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'dart:io';
import 'helpers.dart';

void main() {
  PostgresModelAdapter adapter;
  AuthDelegate<TestUser, Token> delegate;

  setUp(() async {
    adapter = new PostgresModelAdapter(null, () async {
      var uri = 'postgres://dart:dart@localhost:5432/dart_test';
      return await connect(uri);
    });
    adapter.loggingEnabled = true;
    delegate = new AuthDelegate<TestUser, Token>(adapter);
    await generateTemporarySchemaFromModels(adapter, [TestUser, Token]);
  });

  tearDown(() {
    adapter.close();
    adapter = null;
  });

  test("Generate and verify token", () async {
    var auth = new AuthenticationServer<TestUser, Token>([new Client("com.stablekernel.app1", "kilimanjaro")], delegate);
    TestUser createdUser = (await createUsers(adapter, 1)).first;

    var token = await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");

    expect(token.accessToken.length, greaterThan(0));
    expect(token.refreshToken.length, greaterThan(0));
    expect(token.type, "bearer");

    var permission = await auth.verify(token.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.resourceOwnerIdentifier, createdUser.id);

    try {
      permission = await auth.verify("foobar");
      fail("Shouldn't get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }
  });

  test("Bad client ID and secret fails", () async {
    var auth = new AuthenticationServer<TestUser, Token>([new Client("com.stablekernel.app1", "kilimanjaro")], delegate);
    await createUsers(adapter, 1);

    try {
      await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app20", "kilimanjaro");
      fail("Shouldn't get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }

    try {
      await auth.authenticate("bob0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "foobar");
      fail("Shouldn't get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }
  });

  test("Invalid username and password fails", () async {
    var auth = new AuthenticationServer<TestUser, Token>([new Client("com.stablekernel.app1", "kilimanjaro")], delegate);
    await createUsers(adapter, 1);

    try {
      await auth.authenticate("fred@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");
      fail("Shouldn't get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 400);
    }

    try {
      await auth.authenticate("bob+0@stablekernel.com", "foobar", "com.stablekernel.app1", "kilimanjaro");
      fail("Shouldn't get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }
  });

  test("Expiration date works correctly", () async {
    var auth = new AuthenticationServer<TestUser, Token>([new Client("com.stablekernel.app1", "kilimanjaro")], delegate);
    await createUsers(adapter, 1);
    var t = await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro", expirationInSeconds: 5);

    var p1 = await auth.verify(t.accessToken);
    expect(p1.resourceOwnerIdentifier, greaterThan(0));

    sleep(new Duration(seconds: 5));

    try {
      await auth.verify(t.accessToken);
      fail("Shouldn't get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }
  });

  test("Clients have separate tokens", () async {
    var auth = new AuthenticationServer<TestUser, Token>(
    [new Client("com.stablekernel.app1", "kilimanjaro"),
    new Client("com.stablekernel.app2", "fuji")], delegate);

    TestUser createdUser = (await createUsers(adapter, 1)).first;

    var token = await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");
    var p1 = await auth.verify(token.accessToken);
    expect(p1.clientID, "com.stablekernel.app1");
    expect(p1.resourceOwnerIdentifier, createdUser.id);

    var token2 = await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app2", "fuji");
    var p2 = await auth.verify(token2.accessToken);
    expect(p2.clientID, "com.stablekernel.app2");
    expect(p2.resourceOwnerIdentifier, createdUser.id);

    p1 = await auth.verify(token.accessToken);
    expect(p1.clientID, "com.stablekernel.app1");
    expect(p1.resourceOwnerIdentifier, createdUser.id);
  });

  test("Ensure users aren't authenticated by other users", () async {
    var auth = new AuthenticationServer<TestUser, Token>([new Client("com.stablekernel.app1", "kilimanjaro")], delegate);
    var users = await createUsers(adapter, 10);
    var t1 = await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");
    var t2 = await auth.authenticate("bob+4@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");

    var permission = await auth.verify(t1.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.resourceOwnerIdentifier, users[0].id);

    permission = await auth.verify(t2.accessToken);
    expect(permission.clientID, "com.stablekernel.app1");
    expect(permission.resourceOwnerIdentifier, users[4].id);
  });

  test("Refresh token works correctly", () async {
    var auth = new AuthenticationServer<TestUser, Token>([new Client("com.stablekernel.app1", "kilimanjaro")], delegate);
    TestUser user = (await createUsers(adapter, 1)).first;

    var t1 = await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");
    var t2 = await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro", expirationInSeconds: 5);

    var p1 = await auth.verify(t1.accessToken);
    expect(p1.resourceOwnerIdentifier, user.id);
    var p2 = await auth.verify(t2.accessToken);
    expect(p2.resourceOwnerIdentifier, user.id);

    sleep(new Duration(seconds: 5));

    try {
      await auth.verify(t2.accessToken);
      fail("Should not get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }

    var n1 = await auth.refresh(t1.refreshToken, "com.stablekernel.app1", "kilimanjaro");
    var n2 = await auth.refresh(t2.refreshToken, "com.stablekernel.app1", "kilimanjaro");
    expect(n1.accessToken != t1.accessToken, true);
    expect(n2.accessToken != t2.accessToken, true);

    p1 = await auth.verify(n1.accessToken);
    p2 = await auth.verify(n2.accessToken);
    expect(p1.resourceOwnerIdentifier, user.id);
    expect(p2.resourceOwnerIdentifier, user.id);

    try {
      await auth.verify(t1.accessToken);
      fail("Should not get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }

    try {
      await auth.verify(t2.accessToken);
      fail("Should not get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }

    sleep(new Duration(seconds: 5));

    p1 = await auth.verify(n1.accessToken);
    expect(p1.resourceOwnerIdentifier, user.id);
    try {
      await auth.verify(t2.accessToken);
      fail("Should not get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }
  });

  test("Refresh token doesn't work on wrong client id", () async {
    var auth = new AuthenticationServer<TestUser, Token>([new Client("com.stablekernel.app1", "kilimanjaro"),
    new Client("com.stablekernel.app2", "foobar")], delegate);
    await createUsers(adapter, 1);

    var t1 = await auth.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro");
    try {
      await auth.refresh(t1.refreshToken, "com.stablekernel.app2", "foobar");
      fail("Should not get here");
    } catch (e) {
      expect(e.suggestedHTTPStatusCode, 401);
    }
  });

  test("Tokens get pruned", () async {

  });
}