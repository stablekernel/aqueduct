import 'dart:async';
import 'dart:isolate';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

import '../context_helpers.dart';

void main() {
  ManagedContext ctx;
  setUpAll(() async {
    ctx = await contextWithModels([Root, Child]);
  });
  
  test("Can immediately access primary key of belongs-to relationship when building Query.values", () {
    final q = new Query<Child>();
    q.values.parent.id = 1;
    expect(q.values.parent.id, 1);
  });

  test("Can immediately access document property when building Query.values", () {
    final q = new Query<Root>();
    q.values.document["id"] = 1;
    expect(q.values.document["id"], 1);
  });

  test("Can immediately access nested document property when building Query.values", () {
    final q = new Query<Root>();
    q.values.document["object"]["key"] = 1;
    expect(q.values.document["object"]["key"], 1);
  });

  test("Can immediately access nested document list property when building Query.values", () {
    final q1 = new Query<Root>();
    q1.values.document["object"][2] = 1;
    expect(q1.values.document["object"][2], 1);

    final q2 = new Query<Root>();
    q2.values.document[2]["object"] = 1;
    expect(q2.values.document[2]["object"], 1);
  });

  test("Access ManagedSet property of Query.values throws error", () {
    final q = new Query<Root>();
    try {
      q.values.children = new ManagedSet<Child>();
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), "?>>?");
    }
  });

  test("Accessing non-primary key of ManagedObject property in Query.values throws error", () {
    final q = new Query<Child>();
    try {
      q.values.parent.name = "ok";
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), "?>>?");
    }
  });

  test("Accessing primary key of has-one property in Query.values throws error", () {
    final q = new Query<Child>();
    try {
      q.values.parentHasOne.id = 1;
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), "?>>?");
    }
  });
}

class _Root {
  @primaryKey
  int id;

  String name;

  ManagedSet<Child> children;
  Document document;
  Child child;
}
class Root extends ManagedObject<_Root> implements _Root {}

class _Child {
  @primaryKey
  int id;

  String name;

  @Relate(#children)
  Root parent;

  @Relate(#child)
  Root parentHasOne;

}
class Child extends ManagedObject<_Child> implements _Child {}
