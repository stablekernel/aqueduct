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

  group("Query.values assigned to default instance", () {
    test("Can still create subobjects", () {
      final q = new Query<Child>();
      q.values = new Child();
      q.values.parent.id = 1;
      expect(q.values.parent.id, 1);
    });

    test("Replaced object retains all property values", () {
      final q = new Query<Child>();
      final r = new Child()
        ..name = "bob";

      q.values = r;
      q.values.parent.id = 1;
      expect(q.values.parent.id, 1);
      expect(q.values.name, "bob");
    });

    test("If default instance holds ManagedSet, throw exception", () {
      final q = new Query<Root>();
      final r = new Root()
        ..children = new ManagedSet();

      try {
        q.values = r;
        fail('unreachable');
      } on StateError catch (e) {
        expect(e.toString(), "???");
      }
    });

    test("If default instance holds has-one ManagedObject, throw exception", () {
      final q = new Query<Root>();
      final r = new Root()
        ..child = new Child();

      try {
        q.values = r;
        fail('unreachable');
      } on StateError catch (e) {
        expect(e.toString(), "???");
      }
    });

    test("If default instance holds belongs-to ManagedObject with more than primary key, throw exception", () {
      final q = new Query<Child>();
      final r = new Child()
        ..parent = (new Root()..name = "fred");

      try {
        q.values = r;
        fail('unreachable');
      } on StateError catch (e) {
        expect(e.toString(), "???");
      }
    });

    test("If default instance holds belongs-to ManagedObject with only primary key, retain value", () {
      final q = new Query<Child>();
      final r = new Child()
        ..parent = (new Root()..id = 1);

      q.values = r;

      expect(q.values.parent.id, 1);
    });
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
