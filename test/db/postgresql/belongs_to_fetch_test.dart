import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../model_graph.dart';
import '../../helpers.dart';

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

  // Matching on a belongsTo property for a foreign key doesn't need join, but anything else does

  group("Assign non-join matchers to belongsToProperty", () {
    test("Can use whereRelatedByValue", () async {
      var q = new Query<ChildObject>()
          ..where.parents = whereRelatedByValue(1);
      var results = await q.fetch();

      expect(results.length, rootObjects.firstWhere((r) => r.id == 1).children.length);
      for (var child in rootObjects.first.children) {
        var matching = results.firstWhere((c) => c.id == child.id);
        expect(child.value1, matching.value1);
        expect(child.value2, matching.value2);
        expect(child.parents.id, 1);
      }
    });

    test("Can match on foreign key, does not cause join", () async {
      var q = new Query<ChildObject>()
        ..where.parents.id = whereEqualTo(1);
      var results = await q.fetch();

      expect(results.length, rootObjects.firstWhere((r) => r.id == 1).children.length);
      for (var child in rootObjects.first.children) {
        var matching = results.firstWhere((c) => c.id == child.id);
        expect(child.value1, matching.value1);
        expect(child.value2, matching.value2);
        expect(child.parents.id, 1);
      }
    });

    test("Can use whereNull", () async {
      var q = new Query<ChildObject>()
        ..where.parents = whereNull;
      var results = await q.fetch();

      expect(results.length, 0);
    });

    test("Can use whereNotNull", () async {
      var q = new Query<ChildObject>()
        ..where.parents = whereNull;
      var results = await q.fetch();

      expect(results.length, rootObjects.firstWhere((r) => r.id == 1).children.length);
      for (var child in rootObjects.first.children) {
        var matching = results.firstWhere((c) => c.id == child.id);
        expect(child.value1, matching.value1);
        expect(child.value2, matching.value2);
        expect(child.parents.id, 1);
      }
    });
  });

  group("Join on parent of hasMany relationship", () {
    test("Standard join", () async {
      var q = new Query<ChildObject>()
          ..joinOn((c) => c.parents);
      var results = await q.fetch();

      for (var root in rootObjects) {
        for (var child in root.children) {
          var matchingChild = results.firstWhere((c) => c.id == child.id);
          expect(matchingChild.value1, child.value1);
          expect(matchingChild.value2, child.value2);

          expect(matchingChild.parents.id, child.parents.id);
          expect(matchingChild.parents.value1, child.parents.value1);
          expect(matchingChild.parents.value2, child.parents.value2);
          expect(matchingChild.parents.backingMap["children"], isNull);
          expect(matchingChild.parents.backingMap["child"], isNull);
        }
      }
    });

    // nested, double nested

  });

  group("Join on parent of hasOne relationship", () {
    // nested, double nested
  });

  group("Implicit joins", () {

  });
}
