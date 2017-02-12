import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../model_graph.dart';
import '../../helpers.dart';

/*
  many to many should just be an extension of tests in belongs_to_fetch, tiered_where, has_many and has_one tests
  so primary goal of these tests is to test edge cases specific to many to many fetching
 */

void main() {
  justLogEverything();
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

  group("Standard joins", () {
    test("Can join across many to many relationship, from one side", () async {
      var q = new Query<RootObject>()
        ..sortDescriptors = [new QuerySortDescriptor("id", QuerySortOrder.ascending)];

      q.joinMany((r) => r.join)..joinOn((r) => r.other);
      var results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            fullObjectMap(1, and: {
              "join": [
                {
                  "id": 1,
                  "root": {"id": 1},
                  "other": fullObjectMap(1)
                },
                {
                  "id": 2,
                  "root": {"id": 1},
                  "other": fullObjectMap(2)
                },
              ]
            }),
            fullObjectMap(2, and: {
              "join": [
                {
                  "id": 3,
                  "root": {"id": 2},
                  "other": fullObjectMap(3)
                },
              ]
            }),
            fullObjectMap(3, and: {"join": []}),
            fullObjectMap(4, and: {"join": []}),
            fullObjectMap(5, and: {"join": []}),
          ]));
    });

    test("Can join across many to many relationship, from other side", () async {
      var q = new Query<OtherRootObject>()
        ..sortDescriptors = [new QuerySortDescriptor("id", QuerySortOrder.ascending)];

      q.joinMany((r) => r.join)..joinOn((r) => r.root);
      var results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            fullObjectMap(1, and: {
              "join": [
                {
                  "id": 1,
                  "root": fullObjectMap(1),
                  "other": {"id": 1},
                }
              ]
            }),
            fullObjectMap(2, and: {
              "join": [
                {
                  "id": 2,
                  "root": fullObjectMap(1),
                  "other": {"id": 2},
                },
              ]
            }),
            fullObjectMap(3, and: {"join": [{
              "id": 3,
              "root": fullObjectMap(2),
              "other": {"id": 3},
            }]}),
          ]));
    });
  });
}
