import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  group("Multiple contexts, same data model", () {
    final dm = ManagedDataModel([T, U]);

    ManagedContext ctx1;
    ManagedContext ctx2;

    setUp(() async {
      ctx1 = await contextWithDataModel(dm);
      ctx2 = await contextWithDataModel(dm);
    });

    tearDown(() async {
      await ctx1?.close();
      await ctx2?.close();
    });

    test("Queries are sent to the correct database", () async {
      var q = Query<T>(ctx1)..values.name = "bob";
      await q.insert();

      final t1 = await Query<T>(ctx1).fetch();
      final t2 = await Query<T>(ctx2).fetch();

      expect(t1.length, 1);
      expect(t1.first.name, "bob");
      expect(t2.length, 0);
    });

    test("If one context is released, other context's is OK", () async {
      var q = Query<T>(ctx1)..values.name = "bob";
      await q.insert();

      await ctx1.close();
      ctx1 = null;

      q = Query<T>(ctx2)..values.name = "fred";
      await q.insert();

      final t2 = await Query<T>(ctx2).fetch();

      expect(t2.length, 1);
      expect(t2.first.name, "fred");
    });
  });

  group("Multiple contexts, different data model", () {
    ManagedContext ctx1;
    ManagedContext ctx2;

    setUp(() async {
      ctx1 = await contextWithDataModel(ManagedDataModel([T]));
      ctx2 = await contextWithDataModel(ManagedDataModel([U]));
    });

    tearDown(() async {
      await ctx1?.close();
      await ctx2?.close();
    });

    test("Queries are sent to the appropriate database", () async {
      final t1 = await Query<T>(ctx1).fetch();
      final t2 = await Query<U>(ctx2).fetch();

      expect(t1.length, 0);
      expect(t2.length, 0);
    });

    test(
        "Cannot create query on context whose data model doesn't contain query type",
        () async {
      try {
        Query<T>(ctx2);
        fail('unreachable');
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Invalid context"));
      }

      try {
        Query<U>(ctx1);
        fail('unreachable');
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Invalid context"));
      }
    });
  });
}

class _T {
  @primaryKey
  int id;

  String name;
}

class T extends ManagedObject<_T> implements _T {}

class _U {
  @primaryKey
  int id;
  String name;
}

class U extends ManagedObject<_U> implements _U {}

Future<ManagedContext> contextWithDataModel(ManagedDataModel dataModel) async {
  var persistentStore =
      PostgreSQLPersistentStore("dart", "dart", "localhost", 5432, "dart_test");

  var commands = commandsFromDataModel(dataModel, temporary: true);
  var context = ManagedContext(dataModel, persistentStore);

  for (var cmd in commands) {
    await persistentStore.execute(cmd);
  }

  return context;
}
