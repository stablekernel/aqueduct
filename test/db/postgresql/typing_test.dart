import 'package:aqueduct/src/db/postgresql/postgresql_query.dart';
import 'package:aqueduct/src/db/postgresql/query_builder.dart';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ManagedContext context;
  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Values get typed when used in predicate", () async {
    context = await contextWithModels([TestModel]);

    final q = new Query<TestModel>()
      ..where.id = whereEqualTo(1)
      ..where.n = whereEqualTo("a")
      ..where.t = whereEqualTo(new DateTime.now())
      ..where.l = whereEqualTo(1)
      ..where.b = whereEqualTo(true)
      ..where.d = whereEqualTo(1.0);

    var mapper = (q as PostgresQuery).createFetchMapper();
    expect(mapper.finalizedPredicate.format, contains("id:int8"));
    expect(mapper.finalizedPredicate.format, contains("n:text"));
    expect(mapper.finalizedPredicate.format, contains("t:timestamp"));
    expect(mapper.finalizedPredicate.format, contains("l:int4"));
    expect(mapper.finalizedPredicate.format, contains("b:boolean"));
    expect(mapper.finalizedPredicate.format, contains("d:float8"));
  });

  test("Values get typed when used as insertion values", () async {
    context = await contextWithModels([TestModel]);

    final q = new Query<TestModel>()
      ..values.id = 1
      ..values.n = "a"
      ..values.t = new DateTime.now()
      ..values.l = 1
      ..values.b = true
      ..values.d = 1.0;

    var builder = new PostgresQueryBuilder(context.entityForType(TestModel),
        returningProperties: ["id"], values: q.values.backingMap);
    var insertString = builder.insertionValueString;
    expect(insertString, contains("id:int8"));
    expect(insertString, contains("n:text"));
    expect(insertString, contains("t:timestamp"));
    expect(insertString, contains("l:int4"));
    expect(insertString, contains("b:boolean"));
    expect(insertString, contains("d:float8"));
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {
}

class _TestModel {
  @primaryKey
  int id;

  String n;
  DateTime t;
  int l;
  bool b;
  double d;
}