// ignore: unnecessary_const
@Tags(const ["cli"])
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';
import '../context_helpers.dart';
import 'cli_helpers.dart';

void main() {
  final dataModel = ManagedDataModel.fromCurrentMirrorSystem();
  final schema = Schema.fromDataModel(dataModel);
  ManagedContext context;
  PersistentStore store;
  Terminal terminal;

  setUp(() async {
    store = PostgreSQLPersistentStore(
        "dart", "dart", "localhost", 5432, "dart_test");

    final builder = SchemaBuilder.toSchema(store, schema);
    for (var command in builder.commands) {
      await store.execute(command);
    }

    context = ManagedContext(dataModel, store);

    terminal = Terminal.current()
      ..defaultAqueductArgs = [
        "--connect",
        "postgres://dart:dart@localhost:5432/dart_test"
      ];
  });

  tearDown(() async {
    await dropSchemaTables(schema, store);
    await context.close();
  });

  tearDownAll(() async {
    Terminal.deleteTemporaryDirectory();
  });

  group("Success cases", () {
    test("Can create public client", () async {
      await terminal
          .runAqueductCommand("auth", ["add-client", "--id", "a.b.c"]);

      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, isNull);
      expect(results.first.hashedSecret, isNull);
      expect(results.first.salt, isNull);
      expect(results.first.redirectURI, isNull);
    });

    test("Can create confidential client", () async {
      await terminal.runAqueductCommand(
          "auth", ["add-client", "--id", "a.b.c", "--secret", "abc"]);

      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, isNull);
      expect(results.first.redirectURI, isNull);

      final salt = results.first.salt;
      final secret = results.first.hashedSecret;
      expect(AuthUtility.generatePasswordHash("abc", salt), secret);
    });

    test("Can create confidential client with redirect uri", () async {
      await terminal.runAqueductCommand("auth", [
        "add-client",
        "--id",
        "a.b.c",
        "--secret",
        "abc",
        "--redirect-uri",
        "http://foobar.com"
      ]);

      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, isNull);
      expect(results.first.redirectURI, "http://foobar.com");

      final salt = results.first.salt;
      final secret = results.first.hashedSecret;
      expect(AuthUtility.generatePasswordHash("abc", salt), secret);
    });

    test("Can create public client with redirect uri", () async {
      await terminal.runAqueductCommand("auth",
          ["add-client", "--id", "foobar", "--redirect-uri", "http://xyz.com"]);
      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();

      expect(results.length, 1);
      expect(results.first.id, "foobar");
      expect(results.first.allowedScope, isNull);
      expect(results.first.redirectURI, "http://xyz.com");
      expect(results.first.hashedSecret, isNull);
    });

    test("Can create client with scope", () async {
      await terminal.runAqueductCommand(
          "auth", ["add-client", "--id", "a.b.c", "--allowed-scopes", "xyz"]);

      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, "xyz");
      expect(results.first.redirectURI, isNull);
      expect(results.first.hashedSecret, isNull);
      expect(results.first.salt, isNull);
    });

    test("Can create client with multiple scopes", () async {
      await terminal.runAqueductCommand("auth",
          ["add-client", "--allowed-scopes", "xyz.f abc def", "--id", "a.b.c"]);

      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, "xyz.f abc def");
      expect(results.first.redirectURI, isNull);
      expect(results.first.hashedSecret, isNull);
      expect(results.first.salt, isNull);
    });

    test("Scope gets collapsed", () async {
      await terminal.runAqueductCommand("auth", [
        "add-client",
        "--allowed-scopes",
        "xyz:a xyz xyz:a.f xyz.f",
        "--id",
        "a.b.c"
      ]);

      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, "a.b.c");
      expect(results.first.allowedScope, "xyz");
      expect(results.first.redirectURI, isNull);
      expect(results.first.hashedSecret, isNull);
      expect(results.first.salt, isNull);
    });

    test("Can set scope on client", () async {
      await terminal
          .runAqueductCommand("auth", ["add-client", "--id", "a.b.c"]);
      await terminal.runAqueductCommand(
          "auth", ["set-scope", "--id", "a.b.c", "--scopes", "abc efg"]);

      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();
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
      final processResult = await terminal
          .runAqueductCommand("auth", ["add-client", "--secret", "abcdef"]);
      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();
      expect(results.length, 0);

      expect(processResult, isNot(0));
      expect(terminal.output, contains("id required"));
    });

    test("Malformed scope fails", () async {
      final processResult = await terminal.runAqueductCommand(
          "auth", ["add-client", "--id", "foobar", "--allowed-scopes", "x\"x"]);
      final q = Query<ManagedAuthClient>(context);
      final results = await q.fetch();
      expect(results.length, 0);

      expect(processResult, isNot(0));
      expect(terminal.output, contains("Invalid authorization scope"));
    });

    test("Update scope of invalid client id fails", () async {
      final result = await terminal.runAqueductCommand(
          "auth", ["set-scope", "--id", "a.b.c", "--scopes", "abc efg"]);
      expect(result, isNot(0));
      expect(terminal.output, contains("does not exist"));
    });
  });
}
