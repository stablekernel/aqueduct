import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';
import 'package:aqueduct/src/dev/model_graph.dart';

/*
  The more rigid tests on joining are covered by tiered_where, has_many and has_one tests.
  These just check to ensure that belongsTo joins are going to net out the same.
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

  group("Assign non-join matchers to belongsToProperty", () {
    test("Can use identifiedBy", () async {
      var q = Query<ChildObject>(ctx)..where((o) => o.parents).identifiedBy(1);
      var results = await q.fetch();

      expect(results.length,
          rootObjects.firstWhere((r) => r.rid == 1).children.length);
      for (var child in rootObjects.first.children) {
        var matching = results.firstWhere((c) => c.cid == child.cid);
        expect(child.value1, matching.value1);
        expect(child.value2, matching.value2);
        expect(child.parents.rid, 1);
      }
    });

    test(
        "Can match on belongsTo relationship's primary key, does not cause join",
        () async {
      var q = Query<ChildObject>(ctx)..where((o) => o.parents.rid).equalTo(1);
      var results = await q.fetch();

      expect(results.length,
          rootObjects.firstWhere((r) => r.rid == 1).children.length);
      for (var child in rootObjects.first.children) {
        var matching = results.firstWhere((c) => c.cid == child.cid);
        expect(child.value1, matching.value1);
        expect(child.value2, matching.value2);
        expect(child.parents.rid, 1);
      }
    });

    test("Can use whereNull", () async {
      var q = Query<ChildObject>(ctx)..where((o) => o.parents).isNull();
      var results = await q.fetch();

      var childNotChildren =
          rootObjects.expand((r) => [r.child]).where((c) => c != null).toList();

      expect(results.length, childNotChildren.length);
      childNotChildren.forEach((c) {
        expect(results.firstWhere((resultChild) => c.cid == resultChild.cid),
            isNotNull);
      });

      q = Query<ChildObject>(ctx)..where((o) => o.parent).isNull();
      results = await q.fetch();

      var childrenNotChild =
          rootObjects.expand((r) => r.children ?? []).toList();

      expect(results.length, childrenNotChild.length);
      childrenNotChild.forEach((c) {
        expect(results.firstWhere((resultChild) => c.cid == resultChild.cid),
            isNotNull);
      });
    });

    test("Can use whereNotNull", () async {
      var q = Query<ChildObject>(ctx)..where((o) => o.parents).isNotNull();
      var results = await q.fetch();

      var childrenNotChild = rootObjects
          .expand((r) => r.children ?? [])
          .where((c) => c != null)
          .toList();

      expect(results.length, childrenNotChild.length);
      childrenNotChild.forEach((c) {
        expect(results.firstWhere((resultChild) => c.cid == resultChild.cid),
            isNotNull);
      });

      q = Query<ChildObject>(ctx)..where((o) => o.parent).isNotNull();
      results = await q.fetch();
      var childNotChildren =
          rootObjects.expand((r) => [r.child]).where((c) => c != null).toList();

      expect(results.length, childNotChildren.length);
      childNotChildren.forEach((c) {
        expect(results.firstWhere((resultChild) => c.cid == resultChild.cid),
            isNotNull);
      });
    });
  });

  test("Multiple joins from same table", () async {
    var q = Query<ChildObject>(ctx)
      ..sortBy((c) => c.cid, QuerySortOrder.ascending)
      ..join(object: (c) => c.parent)
      ..join(object: (c) => c.parents);
    var results = await q.fetch();

    expect(
        results.map((c) => c.asMap()).toList(),
        equals([
          fullObjectMap(ChildObject, 1,
              and: {"parents": null, "parent": fullObjectMap(RootObject, 1)}),
          fullObjectMap(ChildObject, 2,
              and: {"parents": fullObjectMap(RootObject, 1), "parent": null}),
          fullObjectMap(ChildObject, 3,
              and: {"parents": fullObjectMap(RootObject, 1), "parent": null}),
          fullObjectMap(ChildObject, 4,
              and: {"parents": fullObjectMap(RootObject, 1), "parent": null}),
          fullObjectMap(ChildObject, 5,
              and: {"parents": fullObjectMap(RootObject, 1), "parent": null}),
          fullObjectMap(ChildObject, 6,
              and: {"parents": null, "parent": fullObjectMap(RootObject, 2)}),
          fullObjectMap(ChildObject, 7,
              and: {"parents": fullObjectMap(RootObject, 2), "parent": null}),
          fullObjectMap(ChildObject, 8,
              and: {"parents": null, "parent": fullObjectMap(RootObject, 3)}),
          fullObjectMap(ChildObject, 9,
              and: {"parents": fullObjectMap(RootObject, 4), "parent": null})
        ]));
  });

  group("Join on parent of hasMany relationship", () {
    test("Standard join", () async {
      var q = Query<ChildObject>(ctx)..join(object: (c) => c.parents);
      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(ChildObject, 1, and: {
              "parents": null,
              "parent": {"rid": 1}
            }),
            fullObjectMap(ChildObject, 2,
                and: {"parents": fullObjectMap(RootObject, 1), "parent": null}),
            fullObjectMap(ChildObject, 3,
                and: {"parents": fullObjectMap(RootObject, 1), "parent": null}),
            fullObjectMap(ChildObject, 4,
                and: {"parents": fullObjectMap(RootObject, 1), "parent": null}),
            fullObjectMap(ChildObject, 5,
                and: {"parents": fullObjectMap(RootObject, 1), "parent": null}),
            fullObjectMap(ChildObject, 6, and: {
              "parents": null,
              "parent": {"rid": 2}
            }),
            fullObjectMap(ChildObject, 7,
                and: {"parents": fullObjectMap(RootObject, 2), "parent": null}),
            fullObjectMap(ChildObject, 8, and: {
              "parents": null,
              "parent": {"rid": 3}
            }),
            fullObjectMap(ChildObject, 9,
                and: {"parents": fullObjectMap(RootObject, 4), "parent": null})
          ]));
    });

    test("Nested join", () async {
      var q = Query<GrandChildObject>(ctx);
      q.join(object: (c) => c.parents).join(object: (c) => c.parents);
      var results = await q.fetch();

      expect(
          results.map((g) => g.asMap()).toList(),
          equals([
            fullObjectMap(GrandChildObject, 1, and: {
              "parents": null,
              "parent": {"cid": 1}
            }),
            fullObjectMap(GrandChildObject, 2, and: {
              "parent": null,
              "parents": fullObjectMap(ChildObject, 1, and: {
                "parents": null,
                "parent": {"rid": 1}
              })
            }),
            fullObjectMap(GrandChildObject, 3, and: {
              "parent": null,
              "parents": fullObjectMap(ChildObject, 1, and: {
                "parents": null,
                "parent": {"rid": 1}
              })
            }),
            fullObjectMap(GrandChildObject, 4, and: {
              "parents": null,
              "parent": {"cid": 2}
            }),
            fullObjectMap(GrandChildObject, 5, and: {
              "parent": null,
              "parents": fullObjectMap(ChildObject, 2, and: {
                "parents": fullObjectMap(RootObject, 1),
                "parent": null
              })
            }),
            fullObjectMap(GrandChildObject, 6, and: {
              "parent": null,
              "parents": fullObjectMap(ChildObject, 2, and: {
                "parents": fullObjectMap(RootObject, 1),
                "parent": null
              })
            }),
            fullObjectMap(GrandChildObject, 7, and: {
              "parents": null,
              "parent": {"cid": 3}
            }),
            fullObjectMap(GrandChildObject, 8, and: {
              "parent": null,
              "parents": fullObjectMap(ChildObject, 4, and: {
                "parents": fullObjectMap(RootObject, 1),
                "parent": null
              })
            }),
          ]));
    });

    test("Bidirectional join", () async {
      var q = Query<ChildObject>(ctx)
        ..sortBy((c) => c.cid, QuerySortOrder.ascending)
        ..join(set: (c) => c.grandChildren)
            .sortBy((g) => g.gid, QuerySortOrder.descending)
        ..join(object: (c) => c.parents);

      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(ChildObject, 1, and: {
              "parents": null,
              "parent": {"rid": 1},
              "grandChildren": [
                fullObjectMap(GrandChildObject, 3, and: {
                  "parents": {"cid": 1},
                  "parent": null
                }),
                fullObjectMap(GrandChildObject, 2, and: {
                  "parents": {"cid": 1},
                  "parent": null
                }),
              ]
            }),
            fullObjectMap(ChildObject, 2, and: {
              "parents": fullObjectMap(RootObject, 1),
              "parent": null,
              "grandChildren": [
                fullObjectMap(GrandChildObject, 6, and: {
                  "parents": {"cid": 2},
                  "parent": null
                }),
                fullObjectMap(GrandChildObject, 5, and: {
                  "parents": {"cid": 2},
                  "parent": null
                }),
              ]
            }),
            fullObjectMap(ChildObject, 3, and: {
              "parents": fullObjectMap(RootObject, 1),
              "parent": null,
              "grandChildren": []
            }),
            fullObjectMap(ChildObject, 4, and: {
              "parents": fullObjectMap(RootObject, 1),
              "parent": null,
              "grandChildren": [
                fullObjectMap(GrandChildObject, 8, and: {
                  "parents": {"cid": 4},
                  "parent": null
                }),
              ]
            }),
            fullObjectMap(ChildObject, 5, and: {
              "parents": fullObjectMap(RootObject, 1),
              "parent": null,
              "grandChildren": []
            }),
            fullObjectMap(ChildObject, 6, and: {
              "parents": null,
              "parent": {"rid": 2},
              "grandChildren": []
            }),
            fullObjectMap(ChildObject, 7, and: {
              "parents": fullObjectMap(RootObject, 2),
              "parent": null,
              "grandChildren": []
            }),
            fullObjectMap(ChildObject, 8, and: {
              "parents": null,
              "parent": {"rid": 3},
              "grandChildren": []
            }),
            fullObjectMap(ChildObject, 9, and: {
              "parents": fullObjectMap(RootObject, 4),
              "parent": null,
              "grandChildren": []
            })
          ]));
    });

    test(
        "Can use two 'where' criteria on parent object when not joining parent object explicitly",
        () async {
      var q = Query<ChildObject>(ctx)
        ..where((o) => o.parent.value1).equalTo(1)
        ..where((o) => o.parent.value2).equalTo(1);
      final res1 = await q.fetchOne();
      expect(res1.cid, 1);

      var q2 = Query<ChildObject>(ctx)
        ..where((o) => o.parent.value1).equalTo(1)
        ..where((o) => o.parent.value2).equalTo(2);
      final res2 = await q2.fetch();
      expect(res2.length, 0);
    });
  });

  group("Join on parent of hasOne relationship", () {
    test("Standard join", () async {
      var q = Query<ChildObject>(ctx)
        ..sortBy((c) => c.cid, QuerySortOrder.ascending)
        ..join(object: (c) => c.parent);
      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(ChildObject, 1,
                and: {"parents": null, "parent": fullObjectMap(RootObject, 1)}),
            fullObjectMap(ChildObject, 2, and: {
              "parents": {"rid": 1},
              "parent": null
            }),
            fullObjectMap(ChildObject, 3, and: {
              "parents": {"rid": 1},
              "parent": null
            }),
            fullObjectMap(ChildObject, 4, and: {
              "parents": {"rid": 1},
              "parent": null
            }),
            fullObjectMap(ChildObject, 5, and: {
              "parents": {"rid": 1},
              "parent": null
            }),
            fullObjectMap(ChildObject, 6,
                and: {"parents": null, "parent": fullObjectMap(RootObject, 2)}),
            fullObjectMap(ChildObject, 7, and: {
              "parents": {"rid": 2},
              "parent": null
            }),
            fullObjectMap(ChildObject, 8,
                and: {"parents": null, "parent": fullObjectMap(RootObject, 3)}),
            fullObjectMap(ChildObject, 9, and: {
              "parents": {"rid": 4},
              "parent": null
            })
          ]));
    });

    test("Nested join", () async {
      var q = Query<GrandChildObject>(ctx)
        ..sortBy((g) => g.gid, QuerySortOrder.ascending);

      q.join(object: (c) => c.parent).join(object: (c) => c.parent);

      var results = await q.fetch();

      expect(
          results.map((g) => g.asMap()).toList(),
          equals([
            fullObjectMap(GrandChildObject, 1, and: {
              "parents": null,
              "parent": fullObjectMap(ChildObject, 1, and: {
                "parents": null,
                "parent": fullObjectMap(RootObject, 1)
              })
            }),
            fullObjectMap(GrandChildObject, 2, and: {
              "parent": null,
              "parents": {"cid": 1}
            }),
            fullObjectMap(GrandChildObject, 3, and: {
              "parent": null,
              "parents": {"cid": 1}
            }),
            fullObjectMap(GrandChildObject, 4, and: {
              "parents": null,
              "parent": fullObjectMap(ChildObject, 2, and: {
                "parents": {"rid": 1},
                "parent": null
              })
            }),
            fullObjectMap(GrandChildObject, 5, and: {
              "parent": null,
              "parents": {"cid": 2}
            }),
            fullObjectMap(GrandChildObject, 6, and: {
              "parent": null,
              "parents": {"cid": 2}
            }),
            fullObjectMap(GrandChildObject, 7, and: {
              "parents": null,
              "parent": fullObjectMap(ChildObject, 3, and: {
                "parents": {"rid": 1},
                "parent": null
              })
            }),
            fullObjectMap(GrandChildObject, 8, and: {
              "parent": null,
              "parents": {"cid": 4}
            })
          ]));
    });
  });

  group("Implicit joins", () {
    test("Standard implicit join", () async {
      var q = Query<ChildObject>(ctx)
        ..where((c) => c.parents.value1).equalTo(1);
      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(ChildObject, 2, and: {
              "parent": null,
              "parents": {"rid": 1}
            }),
            fullObjectMap(ChildObject, 3, and: {
              "parent": null,
              "parents": {"rid": 1}
            }),
            fullObjectMap(ChildObject, 4, and: {
              "parent": null,
              "parents": {"rid": 1}
            }),
            fullObjectMap(ChildObject, 5, and: {
              "parent": null,
              "parents": {"rid": 1}
            }),
          ]));
    });

    test("Nested implicit joins", () async {
      var q = Query<GrandChildObject>(ctx)
        ..where((g) => g.parents.parents.value1).equalTo(1)
        ..sortBy((g) => g.gid, QuerySortOrder.ascending);

      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(GrandChildObject, 5, and: {
              "parent": null,
              "parents": {"cid": 2}
            }),
            fullObjectMap(GrandChildObject, 6, and: {
              "parent": null,
              "parents": {"cid": 2}
            }),
            fullObjectMap(GrandChildObject, 8, and: {
              "parent": null,
              "parents": {"cid": 4}
            }),
          ]));

      q = Query<GrandChildObject>(ctx)
        ..where((o) => o.parents.parents).identifiedBy(1)
        ..sortBy((g) => g.gid, QuerySortOrder.ascending);
      results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(GrandChildObject, 5, and: {
              "parent": null,
              "parents": {"cid": 2}
            }),
            fullObjectMap(GrandChildObject, 6, and: {
              "parent": null,
              "parents": {"cid": 2}
            }),
            fullObjectMap(GrandChildObject, 8, and: {
              "parent": null,
              "parents": {"cid": 4}
            }),
          ]));
    });

    test("Bidirectional implicit join", () async {
      var q = Query<ChildObject>(ctx)
        ..where((o) => o.parents.rid).equalTo(1)
        ..where((o) => o.grandChild).isNotNull();
      var results = await q.fetch();
      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(ChildObject, 2, and: {
              "parent": null,
              "parents": {"rid": 1}
            }),
            fullObjectMap(ChildObject, 3, and: {
              "parent": null,
              "parents": {"rid": 1}
            }),
          ]));
    });
  });
}
