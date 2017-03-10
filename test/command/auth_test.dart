import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/executable.dart';
import 'package:aqueduct/managed_auth.dart';

void main() {
  var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
  var schema = new Schema.fromDataModel(dataModel);
  PersistentStore store;

  setUp(() async {
    store = new PostgreSQLPersistentStore.fromConnectionInfo(
        "dart", "dart", "localhost", 5432, "dart_test");

    for (var t in schema.dependencyOrderedTables) {
      var tableCommands = store.createTable(t);
      for (var c in tableCommands) {
        await store.execute(c);
      }
    }

    ManagedContext.defaultContext = new ManagedContext(dataModel, store);
  });

  tearDown(() async {
    for (var t in schema.dependencyOrderedTables.reversed) {
      var tableCommands = store.deleteTable(t);
      for (var c in tableCommands) {
        await store.execute(c);
      }
    }
  });

  group("Success cases", () {
    test("Can create public client", () async {
      await runWith(["add-client", "--id", "a.b.c"]);

      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, isNull);
      expect(results.first.hashedSecret, isNull);
      expect(results.first.salt, isNull);
      expect(results.first.redirectURI, isNull);
    });

    test("Can create confidential client", () async {
      await runWith(["add-client", "--id", "a.b.c", "--secret", "abc"]);

      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, isNull);
      expect(results.first.redirectURI, isNull);

      var salt = results.first.salt;
      var secret = results.first.hashedSecret;
      expect(AuthUtility.generatePasswordHash("abc", salt), secret);
    });

    test("Can create confidential client with redirect uri", () async {
      await runWith(["add-client", "--id", "a.b.c", "--secret", "abc", "--redirect-uri", "http://foobar.com"]);

      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, isNull);
      expect(results.first.redirectURI, "http://foobar.com");

      var salt = results.first.salt;
      var secret = results.first.hashedSecret;
      expect(AuthUtility.generatePasswordHash("abc", salt), secret);
    });

    test("Can create client with scope", () async {
      await runWith(["add-client", "--id", "a.b.c", "--allowed-scopes", "xyz"]);

      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, "xyz");
      expect(results.first.redirectURI, isNull);
      expect(results.first.hashedSecret, isNull);
      expect(results.first.salt, isNull);
    });

    test("Can create client with multiple scopes", () async {
      await runWith(["add-client", "--allowed-scopes", "xyz.f abc def", "--id", "a.b.c"]);

      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, "xyz.f abc def");
      expect(results.first.redirectURI, isNull);
      expect(results.first.hashedSecret, isNull);
      expect(results.first.salt, isNull);
    });

    test("Scope gets collapsed", () async {
      await runWith(["add-client", "--allowed-scopes", "xyz:a xyz xyz:a.f xyz.f", "--id", "a.b.c"]);

      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, "xyz");
      expect(results.first.redirectURI, isNull);
      expect(results.first.hashedSecret, isNull);
      expect(results.first.salt, isNull);
    });

    test("Can set scope on client", () async {
      await runWith(["add-client", "--id", "a.b.c"]);
      await runWith(["set-scope", "--id", "a.b.c", "--scopes", "abc efg"]);
      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, "abc efg");
      expect(results.first.redirectURI, isNull);
      expect(results.first.hashedSecret, isNull);
      expect(results.first.salt, isNull);
    });
  });

  group("Failure cases", () {
    test("Without id fails", () async {
      await runWith(["add-client", "--secret", "abcdef"]);
      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 0);
    });

    test("Create public client with redirect uri fails", () async {
      await runWith(["add-client", "--id", "foobar", "--redirect-uri", "http://xyz.com"]);
      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 0);
    });

    test("Malformed scope fails", () async {
      await runWith(["add-client", "--id", "foobar", "--allowed-scopes", "x\"x"]);
      var q = new Query<ManagedClient>();
      var results = await q.fetch();
      expect(results.length, 0);
    });

    test("Update scope of invalid client id fails", () async {
      var result = await runWith(["set-scope", "--id", "a.b.c", "--scopes", "abc efg"]);
      expect(result != 0, true);
    });
  });
}

Future<int> runWith(List<String> args) {
  var allArgs = ["auth"];
  allArgs.addAll(args);
  allArgs.addAll(["--connect", "postgres://dart:dart@localhost:5432/dart_test"]);

  var cmd = new Runner();
  var results = cmd.options.parse(allArgs);

  return cmd.process(results);
}