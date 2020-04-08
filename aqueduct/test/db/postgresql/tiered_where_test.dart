import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';
import 'package:aqueduct/src/dev/model_graph.dart';

/*
  If you're going to look at these tests, you'll have to draw out the model graph defined in model_graph.dart
  to make sense of it. The size of it makes it difficult to draw in ASCII.

  Explicit join = Using joinOn/joinMany to create a new sub-Query
  Implicit join = Using the property of a related object in the 'where' of a Query
 */

void main() {
  List<RootObject> rootObjects;
  ManagedContext ctx;
  setUpAll(() async {
    ctx = await contextWithModels([
      RootObject,
      RootJoinObject,
      OtherRootObject,
      ChildObject,
      GrandChildObject
    ]);
    rootObjects = await populateModelGraph(ctx);
  });

  tearDownAll(() async {
    await ctx.close();
  });

  group("Joins return appropriate properties", () {
    // This group ensures that the right fields are returned and turned into objects,
    // not whether or not the right objects are returned.
    test("Values are not returned from implicitly joined tables", () async {
      var q = Query<RootObject>(ctx)..where((o) => o.child.cid).greaterThan(1);
      var results = await q.fetch();

      for (var r in results) {
        expect(r.backing.contents.containsKey("child"), false);
        expect(r.backing.contents.length, r.entity.defaultProperties.length);
        for (var property in r.entity.defaultProperties) {
          expect(r.backing.contents.containsKey(property), true);
        }
      }
    });

    test("Objects have default values when explicitly joined", () async {
      var q = Query<RootObject>(ctx)..join(object: (r) => r.child);
      var results = await q.fetch();

      for (var r in results) {
        expect(
            r.backing.contents.length,
            r.entity.defaultProperties.length +
                1); // +1 is for key containing 'child'
        for (var property in r.entity.defaultProperties) {
          expect(r.backing.contents.containsKey(property), true);
        }

        // Child may be null, but even if it is the key must be in the map
        expect(r.backing.contents.containsKey("child"), true);
        if (r.child != null) {
          expect(r.child.backing.contents.length,
              r.child.entity.defaultProperties.length);
          for (var property in r.child.entity.defaultProperties) {
            expect(r.child.backing.contents.containsKey(property), true);
          }
        }
      }
    });

    test(
        "Query with both explicit and implicit join only returns values for explicit join",
        () async {
      var q = Query<RootObject>(ctx);

      // if i have a join condition that uses a property of a has-many or has-one relationship,
      // it creates another join. but that joined table's columns are not usable in
      //the join condition, so we must do an inner select that does the join and move
      // the additional expression to the where clause

      q
          .join(object: (r) => r.child)
          .where((o) => o.grandChild.gid)
          .greaterThan(1);
      var results = await q.fetch();

      for (var r in results) {
        expect(
            r.backing.contents.length,
            r.entity.defaultProperties.length +
                1); // +1 is for key containing 'child'
        for (var property in r.entity.defaultProperties) {
          expect(r.backing.contents.containsKey(property), true);
        }

        // Child may be null, but even if it is the key must be in the map
        expect(r.backing.contents.containsKey("child"), true);
        if (r.child != null) {
          expect(r.child.backing.contents.length,
              r.child.entity.defaultProperties.length);
          for (var property in r.child.entity.defaultProperties) {
            expect(r.child.backing.contents.containsKey(property), true);
          }
          expect(r.child.backing.contents.containsKey("grandChild"), false);
        }
      }
    });

    test("Nested explicit joins return values for all tables", () async {
      var q = Query<RootObject>(ctx);

      q.join(object: (r) => r.child).join(object: (c) => c.grandChild);

      var results = await q.fetch();
      for (var r in results) {
        expect(
            r.backing.contents.length,
            r.entity.defaultProperties.length +
                1); // +1 is for key containing 'child'
        for (var property in r.entity.defaultProperties) {
          expect(r.backing.contents.containsKey(property), true);
        }

        expect(r.backing.contents.containsKey("child"), true);
        if (r.child != null) {
          expect(
              r.child.backing.contents.length,
              r.child.entity.defaultProperties.length +
                  1); // +1 is for key containing 'grandchild
          for (var property in r.child.entity.defaultProperties) {
            expect(r.child.backing.contents.containsKey(property), true);
          }

          expect(r.child.backing.contents.containsKey("grandChild"), true);
          if (r.child.grandChild != null) {
            expect(r.child.grandChild.backing.contents.length,
                r.child.grandChild.entity.defaultProperties.length);
            for (var property in r.child.grandChild.entity.defaultProperties) {
              expect(r.child.grandChild.backing.contents.containsKey(property),
                  true);
            }
          }
        }
      }

      expect(results.any((r) => r.child?.grandChild != null), true);
    });

    test("Query can specify resultProperties values when explicitly joined",
        () async {
      var q = Query<RootObject>(ctx)..returningProperties((r) => [r.rid]);

      q.join(object: (r) => r.child).returningProperties((c) => [c.cid]);

      var results = await q.fetch();
      for (var r in results) {
        expect(r.backing.contents.length, 2 /* id + child */);
        expect(r.backing.contents.containsKey("rid"), true);
        expect(r.backing.contents.containsKey("child"), true);

        if (r.child != null) {
          expect(r.child.backing.contents.length, 1);
          expect(r.child.backing.contents.containsKey("cid"), true);
        }
      }
    });

    test(
        "Query with nested explicit joins can specify resultProperties for all objects",
        () async {
      var q = Query<RootObject>(ctx)..returningProperties((r) => [r.rid]);

      var cq = q.join(object: (r) => r.child)
        ..returningProperties((c) => [c.cid]);

      cq.join(object: (c) => c.grandChild).returningProperties((g) => [g.gid]);

      var results = await q.fetch();
      for (var r in results) {
        expect(r.backing.contents.length, 2 /* id + child */);
        expect(r.backing.contents.containsKey("rid"), true);
        expect(r.backing.contents.containsKey("child"), true);

        if (r.child != null) {
          expect(r.child.backing.contents.length, 2 /* id + grandchild */);
          expect(r.child.backing.contents.containsKey("cid"), true);
          expect(r.child.backing.contents.containsKey("grandChild"), true);

          if (r.child?.grandChild != null) {
            expect(r.child.grandChild.backing.contents.length, 1);
            expect(
                r.child.grandChild.backing.contents.containsKey("gid"), true);
          }
        }
      }
      expect(results.any((r) => r.child?.grandChild != null), true);
    });
  });

  group("With where clauses on root object", () {
    test("Implicity joining related object", () async {
      var q = Query<RootObject>(ctx)..where((o) => o.child.cid).equalTo(1);
      var results = await q.fetch();

      var inMemoryMatch = rootObjects.firstWhere((r) => r.child?.cid == 1);
      expect(results.length, 1);
      expect(results.first.rid, inMemoryMatch.rid);
    });

    test("Explicitly joining related object", () async {
      var q = Query<RootObject>(ctx)..where((o) => o.rid).greaterThan(1);

      q.join(set: (r) => r.children).where((o) => o.cid).greaterThan(5);

      var results = await q.fetch();
      expect(results.length, rootObjects.length - 1);
      expect(results.any((r) => r.rid == 1), false);

      for (var r in results) {
        expect(r.children, isNotNull);
        expect(r.children.any((c) => c.cid <= 5), false);
      }

      expect(results.firstWhere((r) => r.rid == 2).children.length, 1);
      expect(results.firstWhere((r) => r.rid == 4).children.length, 1);
    });

    test("Explicitly joining related objects, nested implicit join", () async {
      var q = Query<RootObject>(ctx)..where((o) => o.rid).equalTo(1);
      q.join(set: (r) => r.children);
//        .where((o) => o.grandChildren.haveAtLeastOneWhere.gid).equalTo(5);

      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.rid, 1);
      expect(results.first.children.length, 1);
      expect(results.first.children.first.grandChildren, isNull);
    }, skip: "#481");

    test("Explicitly joining related objects and nested related objects",
        () async {
      var q = Query<RootObject>(ctx)..where((o) => o.rid).equalTo(1);

      var cq = q.join(set: (r) => r.children);

      cq.join(set: (c) => c.grandChildren).where((o) => o.gid).lessThan(6);

      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.rid, 1);
      expect(results.first.children.length,
          rootObjects.firstWhere((r) => r.rid == 1).children.length);
      expect(
          results.first.children
              .firstWhere((c) => c.cid == 2)
              .grandChildren
              .length,
          1);
      expect(
          results.first.children
              .where((c) => c.cid != 2)
              .every((c) => c.grandChildren.isEmpty),
          true);
    });

    test("Nested implicit joins are combined", () async {
      var q = Query<RootObject>(ctx);
//        ..where((o) => o.children.haveAtLeastOneWhere.cid).equalTo(2)
//        ..where((o) => o.children.haveAtLeastOneWhere.grandChildren
//            .haveAtLeastOneWhere.gid).lessThan(8);
      var results = await q.fetch();

      expect(results.length, 1);
      expect(results.first.rid, 1);
      expect(results.first.backing.contents.containsKey("children"), false);

      q = Query<RootObject>(ctx);
//        ..where((o) => o.children.haveAtLeastOneWhere.cid).equalTo(2)
//        ..where((o) => o.children.haveAtLeastOneWhere.grandChildren
//            .haveAtLeastOneWhere.gid).greaterThan(8);
      results = await q.fetch();
      expect(results.length, 0);
    }, skip: "#481");

    test("Where clause on foreign key property of joined table", () async {
      var q = Query<RootObject>(ctx);
//        ..where((o) => o.child.grandChildren.haveAtLeastOneWhere.gid)
//            .equalTo(2);
      var res = await q.fetch();
      expect(res.length, 1);
      expect(res.first.rid, 1);

      q = Query<RootObject>(ctx);
//        ..where((o) => o.children.haveAtLeastOneWhere.grandChild)
//            .identifiedBy(4);
      res = await q.fetch();
      expect(res.length, 1);
      expect(res.first.rid, 1);

      q = Query<RootObject>(ctx);
//        ..where((o) => o.child.grandChildren.haveAtLeastOneWhere.gid)
//            .equalTo(4);
      res = await q.fetch();
      expect(res.length, 0);

      q = Query<RootObject>(ctx);
//        ..where((o) => o.children.haveAtLeastOneWhere.grandChild)
//            .identifiedBy(8);
      res = await q.fetch();
      expect(res.length, 0);
    }, skip: "#481");
  });

  group("With where clauses on child object", () {
    test("Explicit joins do not impact returned root objects", () async {
      var q = Query<RootObject>(ctx);
      q.join(object: (r) => r.child).where((o) => o.cid).equalTo(1);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.child?.cid == 1).child, isNotNull);
      expect(
          results.where((r) => r.rid != 1).every((r) =>
              r.backing.contents.containsKey("child") && r.child == null),
          true);
    });

    test(
        "Implicit join on child affects child object returned, but not root objects",
        () async {
      var q = Query<RootObject>(ctx);
      q.join(set: (r) => r.children).where((o) => o.grandChild.gid).equalTo(4);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.rid == 1).children.length, 1);
      expect(results.firstWhere((r) => r.rid == 1).children.first.cid, 2);
      expect(results.where((r) => r.rid != 1).every((r) => r.children.isEmpty),
          true);
    });

    // Filter child by values in both child and grandchild
    test(
        "Where clause on child + implicit join to granchild can find overly identified object",
        () async {
      var q = Query<RootObject>(ctx);
      q.join(set: (r) => r.children);
//        ..where((o) => o.cid).equalTo(2)
//        ..where((o) => o.grandChildren.haveAtLeastOneWhere.gid).equalTo(6);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.rid == 1).children.length, 1);
      expect(results.firstWhere((r) => r.rid == 1).children.first.cid, 2);
      expect(results.firstWhere((r) => r.rid == 1).children.first.grandChildren,
          isNull);
      expect(results.where((r) => r.rid != 1).every((r) => r.children.isEmpty),
          true);
    }, skip: "#481");

    test(
        "Where clause on child + implicit join to grandchild returns empty if conditions conflict",
        () async {
      var q = Query<RootObject>(ctx);
      q.join(set: (r) => r.children);
//        ..where((o) => o.cid).equalTo(4)
//        ..where((o) => o.grandChildren.haveAtLeastOneWhere.gid).equalTo(6);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.every((r) => r.children.isEmpty), true);
    }, skip: "#481");

    test(
        "Where clause on child + implicit join to grandchild returns appropriate matches",
        () async {
      var q = Query<RootObject>(ctx);
//      q.join(set: (r) => r.children)
//        ..where((o) => o.cid).lessThanEqualTo(5)
//        ..where((o) => o.grandChildren.haveAtLeastOneWhere.gid).greaterThan(5);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.rid == 1).children.length, 2);
      expect(
          results.firstWhere((r) => r.rid == 1).children.any((c) => c.cid == 2),
          true);
      expect(
          results.firstWhere((r) => r.rid == 1).children.any((c) => c.cid == 4),
          true);
      expect(results.where((r) => r.rid != 1).every((r) => r.children.isEmpty),
          true);
    }, skip: "#481");
  });

  group("With where clauses on grandchild object", () {
    test(
        "Explicit join on child and grandchild, retains all root objects and child objects",
        () async {
      var q = Query<RootObject>(ctx);
      var cq = q.join(set: (r) => r.children);
      cq.join(set: (c) => c.grandChildren).where((o) => o.gid).equalTo(5);

      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(
          results
              .firstWhere((r) => r.rid == 1)
              .children
              .firstWhere((c) => c.cid == 2)
              .grandChildren
              .length,
          1);
      expect(
          results
              .firstWhere((r) => r.rid == 1)
              .children
              .firstWhere((c) => c.cid == 2)
              .grandChildren
              .first
              .gid,
          5);
      expect(
          results
              .firstWhere((r) => r.rid == 1)
              .children
              .where((c) => c.cid != 2)
              .every((c) => c.grandChildren.isEmpty),
          true);

      expect(
          results
              .where((r) => r.rid != 1)
              .every((r) => r.children.every((c) => c.grandChildren.isEmpty)),
          true);
    });
  });

  group("Implicit and explicit same table", () {
    test(
        "An explicit and implicit join on the same table return the keys of the explicit join",
        () async {
      var q = Query<RootObject>(ctx)
        ..where((o) => o.child.value1).greaterThan(0);

      q.join(object: (r) => r.child).returningProperties((c) => [c.cid]);

      var results = await q.fetch();
      for (var r in results) {
        expect(r.backing.contents.length,
            r.entity.defaultProperties.length + 1); // +1 is for child
        for (var property in r.entity.defaultProperties) {
          expect(r.backing.contents.containsKey(property), true);
        }
        expect(r.child.backing.contents.length, 1);
        expect(r.child.backing.contents.containsKey("cid"), true);
      }
    });

    test(
        "An explicit and implicit join on same table combine predicates and have appropriate impact on root objects",
        () async {
      var q = Query<RootObject>(ctx);
//        ..where((o) => o.children.haveAtLeastOneWhere.cid).greaterThan(5);

      q.join(set: (r) => r.children).where((o) => o.cid).lessThan(10);

      var results = await q.fetch();

      expect(results.length, 2);
      expect(results.firstWhere((r) => r.rid == 2).children.length, 1);
      expect(
          results.firstWhere((r) => r.rid == 2).children.any((c) => c.cid == 7),
          true);
      expect(results.firstWhere((r) => r.rid == 4).children.length, 1);
      expect(
          results.firstWhere((r) => r.rid == 4).children.any((c) => c.cid == 9),
          true);
    }, skip: "#481");
  });

  group("Filtering by existence", () {
    test("WhereNotNull on hasMany", () async {
      var q = Query<RootObject>(ctx)..where((o) => o.children).isNotNull();
      var results = await q.fetch();

      expect(results.length, 3);
      expect(results.any((r) => r.rid == 1), true);
      expect(results.any((r) => r.rid == 2), true);
      expect(results.any((r) => r.rid == 4), true);
      expect(
          results.every((r) => r.backing.contents["children"] == null), true);
    });

    test("WhereNull on hasMany", () async {
      var q = Query<RootObject>(ctx)..where((o) => o.children).isNull();
      var results = await q.fetch();

      expect(results.length, 2);
      expect(results.any((r) => r.rid == 3), true);
      expect(results.any((r) => r.rid == 5), true);
      expect(
          results.every((r) => r.backing.contents["children"] == null), true);
    });

    test("WhereNotNull on hasOne", () async {
      var q = Query<RootObject>(ctx)..where((o) => o.child).isNotNull();
      var results = await q.fetch();

      expect(results.length, 3);
      expect(results.any((r) => r.rid == 1), true);
      expect(results.any((r) => r.rid == 2), true);
      expect(results.any((r) => r.rid == 3), true);
      expect(results.every((r) => r.backing.contents["child"] == null), true);
    });

    test("WhereNull on hasOne", () async {
      var q = Query<RootObject>(ctx)..where((o) => o.child).isNull();
      var results = await q.fetch();

      expect(results.length, 2);
      expect(results.any((r) => r.rid == 4), true);
      expect(results.any((r) => r.rid == 5), true);
      expect(results.every((r) => r.backing.contents["child"] == null), true);
    });
  });

  group("Same entity, different relationship property", () {
    test("Where clause on root object for two properties with same entity type",
        () async {
      var q = Query<RootObject>(ctx)
//        ..where((o) => o.children.haveAtLeastOneWhere.cid).greaterThan(3)
        ..where((o) => o.child.cid).equalTo(1);
      var results = await q.fetch();

      expect(results.length, 1);
      expect(results.first.rid, 1);
      expect(results.first.child, isNull);
      expect(results.first.children, isNull);

      q = Query<RootObject>(ctx)
//        ..where((o) => o.children.haveAtLeastOneWhere.cid).greaterThan(10)
        ..where((o) => o.child.cid).equalTo(1);
      results = await q.fetch();

      expect(results.length, 0);
    }, skip: "#481");

    test("Join on on two properties with same entity type", () async {
      var q = Query<RootObject>(ctx);

      q.join(set: (r) => r.children).where((o) => o.cid).greaterThan(3);

      q.join(object: (r) => r.child).where((o) => o.cid).equalTo(1);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.rid == 1).child.cid, 1);
      expect(results.firstWhere((r) => r.rid == 1).children.length, 2);
      expect(results.firstWhere((r) => r.rid == 2).children.length, 1);
      expect(results.firstWhere((r) => r.rid == 4).children.length, 1);

      expect(
          results.where((r) => r.rid != 1).every((r) => r.child == null), true);
    });
  });

  group("Can use deeply nested property when building where", () {
    test("From has-one", () async {
      var q = Query<RootObject>(ctx)
        ..where((o) => o.child.grandChild.gid).equalTo(1);
      final result = await q.fetch();
      expect(result.length, 1);
      expect(result.first.rid, 1);
      expect(result.first.backing.contents.containsKey("child"), false);
    });

    test("From belongs-to-one", () async {
      var q = Query<GrandChildObject>(ctx)
        ..where((o) => o.parent.parent.rid).equalTo(1);
      final result = await q.fetch();
      expect(result.length, 1);
      expect(result.first.gid, 1);
      expect(
          result.first.backing.contents["parent"].backing.contents.keys.length,
          1);
    });

    test("From belongs-to-many", () async {
      var q = Query<GrandChildObject>(ctx)
        ..sortBy((o) => o.gid, QuerySortOrder.ascending)
        ..where((o) => o.parents.parents.rid).equalTo(1);
      final result = await q.fetch();
      expect(result.length, 3);
      expect(result.map((g) => g.gid).toList(), [5, 6, 8]);
      expect(
          result.any((g) =>
              g.backing.contents["parents"].backing.contents.keys.length != 1),
          false);
    });
  });
}
