import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/context_helpers.dart';

void main() {
  ManagedContext ctx;
  setUpAll(() async {
    ctx = await contextWithModels([Root, Child, Constructor]);
  });
  tearDownAll(() async {
    await ctx.close();
  });

  test(
      "If context does not contain data model with query type, throw exception",
      () {
    try {
      Query<Missing>(ctx);
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Invalid context"));
    }
  });

  test(
      "Can immediately access primary key of belongs-to relationship when building Query.values",
      () {
    final q = Query<Child>(ctx);
    q.values.parent.id = 1;
    expect(q.values.parent.id, 1);
  });

  test("Values set in constructor are replicated in Query.values", () {
    final q = Query<Constructor>(ctx);
    expect(q.values.name, "Bob");
  });

  test("Cannot join on same property twice", () {
    try {
      Query<Root>(ctx)
        ..join(object: (r) => r.child)
        ..join(object: (r) => r.child);
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), contains("Invalid query"));
    }
  });

//todo: Deferring these until later
//  test("Can immediately access document property when building Query.values", () {
//    final q = new Query<Root>();
//    q.values.document["id"] = 1;
//    expect(q.values.document["id"], 1);
//  });
//
//  test("Can immediately access nested document property when building Query.values", () {
//    final q = new Query<Root>();
//    q.values.document["object"]["key"] = 1;
//    expect(q.values.document["object"]["key"], 1);
//  });
//
//  test("Can immediately access nested document list property when building Query.values", () {
//    final q1 = new Query<Root>();
//    q1.values.document["object"][2] = 1;
//    expect(q1.values.document["object"][2], 1);
//
//    final q2 = new Query<Root>();
//    q2.values.document[2]["object"] = 1;
//    expect(q2.values.document[2]["object"], 1);
//  });

  test("Access ManagedSet property of Query.values throws error", () {
    final q = Query<Root>(ctx);
    try {
      q.values.children = ManagedSet<Child>();
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Invalid property access"));
    }
  });

  test(
      "Accessing non-primary key of ManagedObject property in Query.values throws error",
      () {
    final q = Query<Child>(ctx);
    try {
      q.values.parent.name = "ok";
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Invalid property access"));
    }
  });

  test("Accessing primary key of has-one property in Query.values throws error",
      () {
    final q = Query<Root>(ctx);
    try {
      q.values.child.id = 1;
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Invalid property access"));
    }
  });

  test(
      "Can set belongs-to relationship with default constructed object if it is empty",
      () {
    final q = Query<Child>(ctx);
    q.values.parent = Root();
    q.values.parent.id = 1;
    expect(q.values.parent.id, 1);
  });

  test(
      "Can set belongs-to relationship with default constructed object if it only contains primary key",
      () {
    final q = Query<Child>(ctx);
    q.values.parent = Root()..id = 1;
    expect(q.values.parent.id, 1);
  });

  test(
      "Setting belongs-to relationship with default constructed object removes non-primary key values",
      () {
    final q = Query<Child>(ctx);
    q.values.parent = Root()
      ..id = 1
      ..name = "bob";

    expect(q.values.backing.contents.keys, ["parent"]);
    expect(q.values.backing.contents["parent"].backing.contents, {"id": 1});

    try {
      q.values.parent.name = "bob";
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Invalid property access"));
    }
  });

  group("Query.values assigned to instance created by default constroct", () {
    test("Can still create subobjects", () {
      final q = Query<Child>(ctx);
      q.values = Child();
      q.values.parent.id = 1;
      expect(q.values.parent.id, 1);
    });

    test("Replaced object retains all property values", () {
      final q = Query<Child>(ctx);
      final r = Child()..name = "bob";

      q.values = r;
      q.values.parent.id = 1;
      expect(q.values.parent.id, 1);
      expect(q.values.name, "bob");
    });

    test("If default instance holds ManagedSet, remove it", () {
      final q = Query<Root>(ctx);
      q.values = Root()..children = ManagedSet();

      expect(q.values.backing.contents, {});
    });

    test("If default instance holds has-one ManagedObject, remove it", () {
      final q = Query<Root>(ctx);
      q.values = Root()..child = Child();
      expect(q.values.backing.contents, {});
    });

    test(
        "If default instance holds belongs-to ManagedObject with more than primary key, remove inner key",
        () {
      final q = Query<Child>(ctx);
      q.values = Child()..parent = (Root()..name = "fred");
      expect(q.values.backing.contents.keys, ["parent"]);
      expect(q.values.backing.contents["parent"].backing.contents, {});
    });

    test(
        "If default instance holds belongs-to ManagedObject with only primary key, retain value",
        () {
      final q = Query<Child>(ctx);
      final r = Child()..parent = (Root()..id = 1);

      q.values = r;

      expect(q.values.parent.id, 1);
    });

    test(
        "If multiple values are set on assigned object, only remove those that need to be removed",
        () {
      final q = Query<Child>(ctx);
      q.values = Child()
        ..parent = (Root()
          ..id = 1
          ..name = "fred")
        ..name = "fred";

      expect(q.values.backing.contents.keys, ["parent", "name"]);
      expect(q.values.backing.contents["parent"].backing.contents, {"id": 1});
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

  @Relate(Symbol('children'))
  Root parent;

  @Relate(Symbol('child'))
  Root parentHasOne;
}

class Child extends ManagedObject<_Child> implements _Child {}

class _Constructor {
  @primaryKey
  int id;

  String name;
}

class Constructor extends ManagedObject<_Constructor> implements _Constructor {
  Constructor() {
    name = "Bob";
  }
}

class Missing extends ManagedObject<_Missing> {}

class _Missing {
  @primaryKey
  int id;
}
