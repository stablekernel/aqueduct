import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../model_graph.dart';
import '../../helpers.dart';

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
    await ctx.persistentStore.close();
  });

  group("Assign non-join matchers to belongsToProperty", () {
    test("Can use whereRelatedByValue", () async {
      var q = new Query<ChildObject>()..where.parents = whereRelatedByValue(1);
      var results = await q.fetch();

      expect(results.length,
          rootObjects.firstWhere((r) => r.id == 1).children.length);
      for (var child in rootObjects.first.children) {
        var matching = results.firstWhere((c) => c.id == child.id);
        expect(child.value1, matching.value1);
        expect(child.value2, matching.value2);
        expect(child.parents.id, 1);
      }
    });

    test(
        "Can match on belongsTo relationship's primary key, does not cause join",
        () async {
      var q = new Query<ChildObject>()..where.parents.id = whereEqualTo(1);
      var results = await q.fetch();

      expect(results.length,
          rootObjects.firstWhere((r) => r.id == 1).children.length);
      for (var child in rootObjects.first.children) {
        var matching = results.firstWhere((c) => c.id == child.id);
        expect(child.value1, matching.value1);
        expect(child.value2, matching.value2);
        expect(child.parents.id, 1);
      }
    });

    test("Can use whereNull", () async {
      var q = new Query<ChildObject>()..where.parents = whereNull;
      var results = await q.fetch();

      var childNotChildren =
          rootObjects.expand((r) => [r.child]).where((c) => c != null).toList();

      expect(results.length, childNotChildren.length);
      childNotChildren.forEach((c) {
        expect(results.firstWhere((resultChild) => c.id == resultChild.id),
            isNotNull);
      });

      q = new Query<ChildObject>()..where.parent = whereNull;
      results = await q.fetch();

      var childrenNotChild =
          rootObjects.expand((r) => r.children ?? []).toList();

      expect(results.length, childrenNotChild.length);
      childrenNotChild.forEach((c) {
        expect(results.firstWhere((resultChild) => c.id == resultChild.id),
            isNotNull);
      });
    });

    test("Can use whereNotNull", () async {
      var q = new Query<ChildObject>()..where.parents = whereNull;
      var results = await q.fetch();

      var childNotChildren =
          rootObjects.expand((r) => [r.child]).where((c) => c != null).toList();

      expect(results.length, childNotChildren.length);
      childNotChildren.forEach((c) {
        expect(results.firstWhere((resultChild) => c.id == resultChild.id),
            isNotNull);
      });

      q = new Query<ChildObject>()..where.parent = whereNull;
      results = await q.fetch();
      var childrenNotChild =
          rootObjects.expand((r) => r.children ?? []).toList();

      expect(results.length, childrenNotChild.length);
      childrenNotChild.forEach((c) {
        expect(results.firstWhere((resultChild) => c.id == resultChild.id),
            isNotNull);
      });
    });
  });

  test("Multiple joins from same table", () async {
    var q = new Query<ChildObject>()
      ..sortBy((c) => c.id, QuerySortOrder.ascending)
      ..joinOn((c) => c.parent)
      ..joinOn((c) => c.parents);
    var results = await q.fetch();

    expect(
        results.map((c) => c.asMap()).toList(),
        equals([
          fullObjectMap(1, and: {"parents": null, "parent": fullObjectMap(1)}),
          fullObjectMap(2, and: {"parents": fullObjectMap(1), "parent": null}),
          fullObjectMap(3, and: {"parents": fullObjectMap(1), "parent": null}),
          fullObjectMap(4, and: {"parents": fullObjectMap(1), "parent": null}),
          fullObjectMap(5, and: {"parents": fullObjectMap(1), "parent": null}),
          fullObjectMap(6, and: {"parents": null, "parent": fullObjectMap(2)}),
          fullObjectMap(7, and: {"parents": fullObjectMap(2), "parent": null}),
          fullObjectMap(8, and: {"parents": null, "parent": fullObjectMap(3)}),
          fullObjectMap(9, and: {"parents": fullObjectMap(4), "parent": null})
        ]));
  });

  group("Join on parent of hasMany relationship", () {
    test("Standard join", () async {
      var q = new Query<ChildObject>()..joinOn((c) => c.parents);
      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(1, and: {
              "parents": null,
              "parent": {"id": 1}
            }),
            fullObjectMap(2,
                and: {"parents": fullObjectMap(1), "parent": null}),
            fullObjectMap(3,
                and: {"parents": fullObjectMap(1), "parent": null}),
            fullObjectMap(4,
                and: {"parents": fullObjectMap(1), "parent": null}),
            fullObjectMap(5,
                and: {"parents": fullObjectMap(1), "parent": null}),
            fullObjectMap(6, and: {
              "parents": null,
              "parent": {"id": 2}
            }),
            fullObjectMap(7,
                and: {"parents": fullObjectMap(2), "parent": null}),
            fullObjectMap(8, and: {
              "parents": null,
              "parent": {"id": 3}
            }),
            fullObjectMap(9, and: {"parents": fullObjectMap(4), "parent": null})
          ]));
    });

    test("Nested join", () async {
      var q = new Query<GrandChildObject>();
      q.joinOn((c) => c.parents)..joinOn((c) => c.parents);
      var results = await q.fetch();

      expect(
          results.map((g) => g.asMap()).toList(),
          equals([
            fullObjectMap(1, and: {
              "parents": null,
              "parent": {"id": 1}
            }),
            fullObjectMap(2, and: {
              "parent": null,
              "parents": fullObjectMap(1, and: {
                "parents": null,
                "parent": {"id": 1}
              })
            }),
            fullObjectMap(3, and: {
              "parent": null,
              "parents": fullObjectMap(1, and: {
                "parents": null,
                "parent": {"id": 1}
              })
            }),
            fullObjectMap(4, and: {
              "parents": null,
              "parent": {"id": 2}
            }),
            fullObjectMap(5, and: {
              "parent": null,
              "parents": fullObjectMap(2,
                  and: {"parents": fullObjectMap(1), "parent": null})
            }),
            fullObjectMap(6, and: {
              "parent": null,
              "parents": fullObjectMap(2,
                  and: {"parents": fullObjectMap(1), "parent": null})
            }),
            fullObjectMap(7, and: {
              "parents": null,
              "parent": {"id": 3}
            }),
            fullObjectMap(8, and: {
              "parent": null,
              "parents": fullObjectMap(4,
                  and: {"parents": fullObjectMap(1), "parent": null})
            }),
          ]));
    });

    test("Bidirectional join", () async {
      var q = new Query<ChildObject>()
        ..sortBy((c) => c.id, QuerySortOrder.ascending)
        ..joinMany((c) => c.grandChildren)
            .sortBy((g) => g.id, QuerySortOrder.descending)
        ..joinOn((c) => c.parents);

      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(1, and: {
              "parents": null,
              "parent": {"id": 1},
              "grandChildren": [
                fullObjectMap(3, and: {
                  "parents": {"id": 1},
                  "parent": null
                }),
                fullObjectMap(2, and: {
                  "parents": {"id": 1},
                  "parent": null
                }),
              ]
            }),
            fullObjectMap(2, and: {
              "parents": fullObjectMap(1),
              "parent": null,
              "grandChildren": [
                fullObjectMap(6, and: {
                  "parents": {"id": 2},
                  "parent": null
                }),
                fullObjectMap(5, and: {
                  "parents": {"id": 2},
                  "parent": null
                }),
              ]
            }),
            fullObjectMap(3, and: {
              "parents": fullObjectMap(1),
              "parent": null,
              "grandChildren": []
            }),
            fullObjectMap(4, and: {
              "parents": fullObjectMap(1),
              "parent": null,
              "grandChildren": [
                fullObjectMap(8, and: {
                  "parents": {"id": 4},
                  "parent": null
                }),
              ]
            }),
            fullObjectMap(5, and: {
              "parents": fullObjectMap(1),
              "parent": null,
              "grandChildren": []
            }),
            fullObjectMap(6, and: {
              "parents": null,
              "parent": {"id": 2},
              "grandChildren": []
            }),
            fullObjectMap(7, and: {
              "parents": fullObjectMap(2),
              "parent": null,
              "grandChildren": []
            }),
            fullObjectMap(8, and: {
              "parents": null,
              "parent": {"id": 3},
              "grandChildren": []
            }),
            fullObjectMap(9, and: {
              "parents": fullObjectMap(4),
              "parent": null,
              "grandChildren": []
            })
          ]));
    });
  });

  group("Join on parent of hasOne relationship", () {
    test("Standard join", () async {
      var q = new Query<ChildObject>()
        ..sortBy((c) => c.id, QuerySortOrder.ascending)
        ..joinOn((c) => c.parent);
      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(1,
                and: {"parents": null, "parent": fullObjectMap(1)}),
            fullObjectMap(2, and: {
              "parents": {"id": 1},
              "parent": null
            }),
            fullObjectMap(3, and: {
              "parents": {"id": 1},
              "parent": null
            }),
            fullObjectMap(4, and: {
              "parents": {"id": 1},
              "parent": null
            }),
            fullObjectMap(5, and: {
              "parents": {"id": 1},
              "parent": null
            }),
            fullObjectMap(6,
                and: {"parents": null, "parent": fullObjectMap(2)}),
            fullObjectMap(7, and: {
              "parents": {"id": 2},
              "parent": null
            }),
            fullObjectMap(8,
                and: {"parents": null, "parent": fullObjectMap(3)}),
            fullObjectMap(9, and: {
              "parents": {"id": 4},
              "parent": null
            })
          ]));
    });

    test("Nested join", () async {
      var q = new Query<GrandChildObject>()
        ..sortBy((g) => g.id, QuerySortOrder.ascending);

      q.joinOn((c) => c.parent)..joinOn((c) => c.parent);

      var results = await q.fetch();

      expect(
          results.map((g) => g.asMap()).toList(),
          equals([
            fullObjectMap(1, and: {
              "parents": null,
              "parent": fullObjectMap(1,
                  and: {"parents": null, "parent": fullObjectMap(1)})
            }),
            fullObjectMap(2, and: {
              "parent": null,
              "parents": {"id": 1}
            }),
            fullObjectMap(3, and: {
              "parent": null,
              "parents": {"id": 1}
            }),
            fullObjectMap(4, and: {
              "parents": null,
              "parent": fullObjectMap(2, and: {
                "parents": {"id": 1},
                "parent": null
              })
            }),
            fullObjectMap(5, and: {
              "parent": null,
              "parents": {"id": 2}
            }),
            fullObjectMap(6, and: {
              "parent": null,
              "parents": {"id": 2}
            }),
            fullObjectMap(7, and: {
              "parents": null,
              "parent": fullObjectMap(3, and: {
                "parents": {"id": 1},
                "parent": null
              })
            }),
            fullObjectMap(8, and: {
              "parent": null,
              "parents": {"id": 4}
            })
          ]));
    });
  });

  group("Implicit joins", () {
    test("Standard implicit join", () async {
      var q = new Query<ChildObject>()..where.parents.value1 = whereEqualTo(1);
      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(2, and: {
              "parent": null,
              "parents": {"id": 1}
            }),
            fullObjectMap(3, and: {
              "parent": null,
              "parents": {"id": 1}
            }),
            fullObjectMap(4, and: {
              "parent": null,
              "parents": {"id": 1}
            }),
            fullObjectMap(5, and: {
              "parent": null,
              "parents": {"id": 1}
            }),
          ]));
    });

    test("Nested implicit joins", () async {
      var q = new Query<GrandChildObject>()
        ..where.parents.parents.value1 = whereEqualTo(1)
        ..sortBy((g) => g.id, QuerySortOrder.ascending);

      var results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(5, and: {
              "parent": null,
              "parents": {"id": 2}
            }),
            fullObjectMap(6, and: {
              "parent": null,
              "parents": {"id": 2}
            }),
            fullObjectMap(8, and: {
              "parent": null,
              "parents": {"id": 4}
            }),
          ]));

      q = new Query<GrandChildObject>()
        ..where.parents.parents = whereRelatedByValue(1)
        ..sortBy((g) => g.id, QuerySortOrder.ascending);
      results = await q.fetch();

      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(5, and: {
              "parent": null,
              "parents": {"id": 2}
            }),
            fullObjectMap(6, and: {
              "parent": null,
              "parents": {"id": 2}
            }),
            fullObjectMap(8, and: {
              "parent": null,
              "parents": {"id": 4}
            }),
          ]));
    });

    test("Bidirectional implicit join", () async {
      var q = new Query<ChildObject>()
        ..where.parents.id = whereEqualTo(1)
        ..where.grandChild = whereNotNull;
      var results = await q.fetch();
      expect(
          results.map((c) => c.asMap()).toList(),
          equals([
            fullObjectMap(2, and: {
              "parent": null,
              "parents": {"id": 1}
            }),
            fullObjectMap(3, and: {
              "parent": null,
              "parents": {"id": 1}
            }),
          ]));
    });
  });
}
