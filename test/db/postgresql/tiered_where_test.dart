import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import '../model_graph.dart';
import '../../helpers.dart';

void main() {
  justLogEverything();

  List<RootObject> rootObjects;
  ManagedContext ctx;
  setUpAll(() async {
    ctx = await contextWithModels([RootObject, RootJoinObject, OtherRootObject, ChildObject, GrandChildObject]);
    rootObjects = await populateModelGraph(ctx);
  });

  tearDownAll(() async {
    await ctx.persistentStore.close();
  });

  group("Returned values", () {
    // This group ensures that the right fields are returned and turned into objects,
    // not whether or not the right objects are returned.
    test("Objects have default values when implicitly joined, implicitly joined tables not returned", () async {
      var q = new Query<RootObject>()
          ..where.child.id = whereGreaterThan(1);
      var results = await q.fetch();

      for(var r in results) {
        expect(r.backingMap.containsKey("child"), false);
        expect(r.backingMap.length, r.entity.defaultProperties.length);
        for (var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }
      }
    });

    test("Objects have default values when explicitly joined", () async {
      var q = new Query<RootObject>()
        ..joinOn((r) => r.child);
      var results = await q.fetch();

      for(var r in results) {
        expect(r.backingMap.length, r.entity.defaultProperties.length + 1); // +1 is for key containing 'child'
        for (var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }

        // Child may be null, but even if it is the key must be in the map
        expect(r.backingMap.containsKey("child"), true);
        if (r.child != null) {
          expect(r.child.backingMap.length, r.child.entity.defaultProperties.length);
          for(var property in r.child.entity.defaultProperties) {
            expect(r.child.backingMap.containsKey(property), true);
          }
        }
      }
    });

    test("Joined objects have default values when they themselves are implicitly joined", () async {
      var q = new Query<RootObject>();

      q.joinOn((r) => r.child)
        ..where.grandChild.id = whereGreaterThan(1);
      var results = await q.fetch();

      for(var r in results) {
        expect(r.backingMap.length, r.entity.defaultProperties.length + 1); // +1 is for key containing 'child'
        for (var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }

        // Child may be null, but even if it is the key must be in the map
        expect(r.backingMap.containsKey("child"), true);
        if (r.child != null) {
          expect(r.child.backingMap.length, r.child.entity.defaultProperties.length);
          for(var property in r.child.entity.defaultProperties) {
            expect(r.child.backingMap.containsKey(property), true);
          }
          expect(r.child.backingMap.containsKey("grandChild"), false);
        }
      }
    });

    test("Deeply nested objects have default values when explicitly joined", () async {
      var q = new Query<RootObject>();

      q.joinOn((r) => r.child)
        ..joinOn((c) => c.grandChild);

      var results = await q.fetch();
      for(var r in results) {
        expect(r.backingMap.length, r.entity.defaultProperties.length + 1); // +1 is for key containing 'child'
        for (var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }

        expect(r.backingMap.containsKey("child"), true);
        if (r.child != null) {
          expect(r.child.backingMap.length, r.child.entity.defaultProperties.length + 1); // +1 is for key containing 'grandchild
          for(var property in r.child.entity.defaultProperties) {
            expect(r.child.backingMap.containsKey(property), true);
          }

          expect(r.child.backingMap.containsKey("grandChild"), true);
          if(r.child.grandChild != null) {
            expect(r.child.grandChild.backingMap.length, r.child.grandChild.entity.defaultProperties.length);
            for(var property in r.child.grandChild.entity.defaultProperties) {
              expect(r.child.backingMap.containsKey(property), true);
            }
          }
        }
      }

      expect(results.any((r) => r.child?.grandChild != null), true);
    });

    test("Objects have specified resultProperties values when explicitly joined", () async {
      var q = new Query<RootObject>()
        ..propertiesToFetch = ["id"];

      q.joinOn((r) => r.child)
        ..propertiesToFetch = ["id"];

      var results = await q.fetch();
      for(var r in results) {
        expect(r.backingMap.length, 2 /* id + child */);
        expect(r.backingMap.containsKey("id"), true);
        expect(r.backingMap.containsKey("child"), true);

        if (r.child != null) {
          expect(r.child.backingMap.length, 1);
          expect(r.child.backingMap.containsKey("id"), true);
        }
      }
    });

    test("Deeply nested objects have specified resultProperties values when explicitly joined", () async {
      var q = new Query<RootObject>()
        ..propertiesToFetch = ["id"];

      var cq = q.joinOn((r) => r.child)
        ..propertiesToFetch = ["id"];

      cq.joinOn((c) => c.grandChild)
        ..propertiesToFetch = ["id"];

      var results = await q.fetch();
      for(var r in results) {
        expect(r.backingMap.length, 2 /* id + child */);
        expect(r.backingMap.containsKey("id"), true);
        expect(r.backingMap.containsKey("child"), true);

        if (r.child != null) {
          expect(r.child.backingMap.length, 2 /* id + grandchild */);
          expect(r.child.backingMap.containsKey("id"), true);
          expect(r.child.backingMap.containsKey("grandChild"), true);

          if (r.child?.grandChild != null) {
            expect(r.child.grandChild.backingMap.length, 1);
            expect(r.child.grandChild.backingMap.containsKey("id"), true);
          }
        }
      }
      expect(results.any((r) => r.child?.grandChild != null), true);
    });

    // Check with child as explicit, grandchild as implicit is selected
    test("Explicit join with nested implicit join only returns root and explicit objects", () async {
      var q = new Query<RootObject>();

      q.joinOn((r) => r.child)
        ..where.grandChild.id = whereGreaterThan(0);

      var results = await q.fetch();
      for(var r in results) {
        expect(r.backingMap.length, r.entity.defaultProperties.length + 1);
        for(var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }
        expect(r.backingMap.containsKey("child"), true);

        if (r.child != null) {
          expect(r.child.backingMap.length, r.child.entity.defaultProperties.length);
          for(var property in r.child.entity.defaultProperties) {
            expect(r.child.backingMap.containsKey(property), true);
          }
        }
      }
    });
  });

  group("Filtering root objects by values in its related objects", () {
    test("Implicit join on child filters root objects not matching condition", () async {
      var q = new Query<RootObject>()
          ..where.child.id = whereEqualTo(1);
      var results = await q.fetch();

      var inMemoryMatch = rootObjects.firstWhere((r) => r.child?.id == 1);
      expect(results.length, 1);
      expect(results.first.id, inMemoryMatch.id);
    });

    test("Explicit join on child maintains root objects, even when child is null", () async {
      var q = new Query<RootObject>();
      q.joinOn((r) => r.child)
        ..where.id = whereEqualTo(1);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.child?.id == 1).child, isNotNull);
      expect(results
          .where((r) => r.id != 1)
          .every((r) => r.backingMap.containsKey("child") && r.child == null),
          true);
    });

    test("Explicit join on child, implicit join on grandchild values, retains all root objects but reduces child objects", () async {
      var q = new Query<RootObject>();
      q.joinMany((r) => r.children)
        ..where.grandChild.id = whereEqualTo(4);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.id == 1).children.length, 1);
      expect(results.firstWhere((r) => r.id == 1).children.first.id, 4);
      expect(results
          .where((r) => r.id != 1)
          .every((r) => r.children.isEmpty),
          true);
    });

    test("Explicit join on child and grandchild, retains all root objects and child objects", () async {
      var q = new Query<RootObject>();
      var cq = q.joinMany((r) => r.children);
      cq.joinMany((c) => c.grandChildren)
        ..where.id = whereEqualTo(4);

      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      for (var r in rootObjects) {
        var matching = results.firstWhere((result) => r.id == result.id);

        expect(matching.children.length, r.children?.length ?? 0);
        for(var child in matching.children) {
          var matchingChild = matching.children
              .firstWhere((c) => c.id == child.id);
          expect(matchingChild.grandChildren.length, child.grandChildren.length);
        }
      }
    });

    test("Explicit join on child, where clause on root object and child object can filter both root and child objects", () async {
      var q = new Query<RootObject>()
          ..where.id = whereGreaterThan(1);

      q.joinMany((r) => r.children)
        ..where.id = whereGreaterThan(5);

      var results = await q.fetch();
      expect(results.length, rootObjects.length - 1);
      expect(results.any((r) => r.id == 1), false);

      for(var r in results) {
        expect(r.children, isNotNull);
        expect(r.children.any((c) => c.id <= 5), false);
      }

      expect(results.firstWhere((r) => r.id == 2).children.length, 1);
      expect(results.firstWhere((r) => r.id == 4).children.length, 1);
    });

    test("Explicit join on child, implicit join on grandchild and where clause in root object can filter all of the returned object graph", () async {
      var q = new Query<RootObject>()
          ..where.id = whereEqualTo(1);
      q.joinMany((r) => r.children)
        ..where.grandChildren.matchOn.id = whereEqualTo(5);

      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);
      expect(results.first.children.length, 1);
      expect(results.first.children.first.grandChildren.length, 1);
    });
  });

  group("Filtering child objects by values in its related objects", () {
    // Filter child by values in child
    test("Explicit join on child with where clause maintains root objects, even when child is null", () async {

    });

    // Filter child by values in grandchild
    test("Explicit join on child with implicit join on grandchild, returns all root objects, but filters child/grandchild objects", () async {

    });

    // Filter child by values in both child and grandchild
    test("Explicit join on child with implicit join on grandchild both with where clause, returns all root objects, but filters child/grandchild objects", () async {

    });

    test("Explicit join on child and grandchild both with where clause, returns all root objects and child objects aren't filtered by not having grandchild", () async {

    });
  });

  group("Implicit and explicit same table", () {
    test("An explicit and implicit join on the same table return the keys of the explicit join", () async {
      var q = new Query<RootObject>()
        ..where.child.value1 = whereGreaterThan(0);

      q.joinOn((r) => r.child)
        ..propertiesToFetch = ["id"]
        ..where.value1 = whereGreaterThan(0);

      var results = await q.fetch();
      for(var r in results) {
        expect(r.backingMap.length, r.entity.defaultProperties.length + 1); // +1 is for child
        for(var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }
        expect(r.child.backingMap.length, 1);
        expect(r.child.backingMap.containsKey("id"), true);
      }
    });

    test("An explicit and implicit join on same table combine predicates", () async {

    });

    test("An explicit and implicit join with where clauses on same table have appropriate impact on parent objects", () async {
        // Those excluded by the explicit join don't impact parents, those excluded by the implicit join on the root object
        // do
    });

  });

  group("Filtering by existence", () {
    // where.child = whereNotNull
    // where.child = whereNull
    // where.child.grandchild = whereNull
    // where.child.grandchild = whereNotNull
  });
}