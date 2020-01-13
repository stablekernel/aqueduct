import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  group("Offset/limit", () {
    ManagedContext context;

    setUpAll(() async {
      context = await contextWithModels([PageableTestModel]);
      for (int i = 0; i < 10; i++) {
        var p = PageableTestModel()..value = "$i";
        await (Query<PageableTestModel>(context)..values = p).insert();
      }
    });

    tearDownAll(() async {
      await context?.close();
      context = null;
    });

    test("Fetch limit and offset specify a particular row", () async {
      var q = Query<PageableTestModel>(context)
        ..fetchLimit = 1
        ..offset = 2;

      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.value, "2");
    });

    test("Offset out of bounds returns no results", () async {
      var q = Query<PageableTestModel>(context)
        ..fetchLimit = 1
        ..offset = 10;

      var results = await q.fetch();
      expect(results.length, 0);
    });

    test("Offset respects ordering specified by sort descriptors", () async {
      var q = Query<PageableTestModel>(context)
        ..fetchLimit = 2
        ..offset = 2
        ..sortBy((p) => p.id, QuerySortOrder.descending);

      var results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.value, "7");
      expect(results[1].value, "6");
    });
  });

  group("Paging", () {
    ManagedContext context;

    var check = (List checkIDs, List<PageableTestModel> values) {
      expect(checkIDs.length, values.length);
      var ids = values.map((v) => v.id).toList();
      for (int i = 0; i < ids.length; i++) {
        expect(ids[i], checkIDs[i]);
      }
    };

    setUpAll(() async {
      context = await contextWithModels([PageableTestModel]);
      for (int i = 0; i < 10; i++) {
        var p = PageableTestModel()..value = "$i";
        await (Query<PageableTestModel>(context)..values = p).insert();
      }
    });

    tearDownAll(() async {
      await context?.close();
      context = null;
    });

    /*
      Tests will ensure the following scenarios:

     |1 2 3 4 5 6 7 8 9 0|
     ---------------------
    x|- - - - >          |
     |x - - - - >        |
    x|- - - - - - - - - -|>
     |          x - - - >|
     |          x - - - -|>
     |                  x|>
     |                   |x>
 nil |- - - - - - - - - -|>
 nil |- - - - >          |
   <x|                   |
    <|x                  |
    <|- - - x            |
     |< - - - x          |
    <|- - - - - - - - - -|x
     |        < - - - - x|
     |          < - - - -|x
    <|- - - - - - - - - -| nil
     |          < - - - -| nil
     ---------------------
     */

    test("Ascending from known data set edge, limited to inside data set",
        () async {
      // select * from t where id > 0 order by id asc limit 5;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.ascending, boundingValue: 0)
        ..fetchLimit = 5;
      var res = await req.fetch();
      check([1, 2, 3, 4, 5], res);
    });

    test("Ascending from first element, limited to inside data set", () async {
      // select * from t where id > 1 order by id asc limit 5;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.ascending, boundingValue: 1)
        ..fetchLimit = 5;
      var res = await req.fetch();
      check([2, 3, 4, 5, 6], res);
    });

    test("Ascending from first element, extended past data set", () async {
      // select * from t where id > 0 order by id asc limit 15;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.ascending, boundingValue: 0)
        ..fetchLimit = 15;
      var res = await req.fetch();
      check([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], res);
    });

    test("Ascending from inside data set to known edge", () async {
      // select * from t where id > 6 order by id asc limit 4;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.ascending, boundingValue: 6)
        ..fetchLimit = 4;
      var res = await req.fetch();
      check([7, 8, 9, 10], res);
    });

    test("Ascending from inside data set to past edge", () async {
      // select * from t where id > 6 order by id asc limit 5
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.ascending, boundingValue: 6)
        ..fetchLimit = 5;
      var res = await req.fetch();
      check([7, 8, 9, 10], res);
    });

    test("Ascending from edge of data set into outside data set", () async {
      // select * from t where id > 10 order by id asc limit 5
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.ascending, boundingValue: 10)
        ..fetchLimit = 5;
      var res = await req.fetch();
      expect(res.length, 0);
    });

    test("Ascending from outside the data set and onward", () async {
      // select * from t where id > 11 order by id asc limit 10
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.ascending, boundingValue: 11)
        ..fetchLimit = 10;
      var res = await req.fetch();
      expect(res.length, 0);
    });

    test("Ascending from null to all the way outside the data set", () async {
      // select * from t order by id asc limit 15
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.ascending)
        ..fetchLimit = 15;
      var res = await req.fetch();
      check([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], res);
    });

    test("Ascending from null to halfway into the data set", () async {
      // select * from t order by id asc limit 5;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.ascending)
        ..fetchLimit = 5;
      var res = await req.fetch();
      check([1, 2, 3, 4, 5], res);
    });

    test("Descending from beginning of data set to before data set", () async {
      // select * from t where id < 0 order by id desc limit 10
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.descending, boundingValue: 0)
        ..fetchLimit = 10;
      var res = await req.fetch();
      expect(res.length, 0);
    });

    test("Descending from first element in data set to before data set",
        () async {
      // select * from t where id < 1 order by id desc limit 10;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.descending, boundingValue: 1)
        ..fetchLimit = 10;
      var res = await req.fetch();
      expect(res.length, 0);
    });

    test("Descending from middle of data set to before data set", () async {
      // select * from t where id < 4 order by id desc limit 10;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.descending, boundingValue: 4)
        ..fetchLimit = 10;
      var res = await req.fetch();
      check([3, 2, 1], res);
    });

    test("Descending from middle of data set to edge of data set", () async {
      // select * from t where id < 5 order by id desc limit 4;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.descending, boundingValue: 5)
        ..fetchLimit = 4;
      var res = await req.fetch();
      check([4, 3, 2, 1], res);
    });

    test(
        "Descending from outside end of data set to beginning edge of data set",
        () async {
      // select * from t where id < 11 order by id desc limit 10;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.descending, boundingValue: 11)
        ..fetchLimit = 10;
      var res = await req.fetch();
      check([10, 9, 8, 7, 6, 5, 4, 3, 2, 1], res);
    });

    test("Descending from last element in data set to middle of data set",
        () async {
      // select * from t where id < 10 order by id desc limit 5;
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.descending, boundingValue: 10)
        ..fetchLimit = 5;
      var res = await req.fetch();
      check([9, 8, 7, 6, 5], res);
    });

    test("Descending from outside end of data set to middle of data set",
        () async {
      // select * from t where id < 11 order by id desc limit 5
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.descending, boundingValue: 11)
        ..fetchLimit = 5;
      var res = await req.fetch();
      check([10, 9, 8, 7, 6], res);
    });

    test("Descending from null to beginning of data set", () async {
      // select * from t order by id desc limit 10
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.descending)
        ..fetchLimit = 10;
      var res = await req.fetch();
      check([10, 9, 8, 7, 6, 5, 4, 3, 2, 1], res);
    });

    test("Descending from null to middle of data set", () async {
      // select * from t order by id desc limit 5
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.id, QuerySortOrder.descending)
        ..fetchLimit = 5;
      var res = await req.fetch();
      check([10, 9, 8, 7, 6], res);
    });
  });

  group("Failure cases", () {
    ManagedContext context;
    var check = (List checkIDs, List<PageableTestModel> values) {
      expect(checkIDs.length, values.length);
      var ids = values.map((v) => v.id).toList();
      for (int i = 0; i < ids.length; i++) {
        expect(ids[i], checkIDs[i]);
      }
    };

    setUpAll(() async {
      context =
          await contextWithModels([PageableTestModel, HasMany, BelongsTo]);
      for (int i = 0; i < 10; i++) {
        var p = PageableTestModel()..value = "$i";
        await (Query<PageableTestModel>(context)..values = p).insert();
      }
    });

    tearDownAll(() async {
      await context?.close();
      context = null;
    });

    test("Incorrect type for boundingValue", () async {
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.value, QuerySortOrder.ascending, boundingValue: 0);

      try {
        var _ = await req.fetch();
        expect(true, false);
      } on StateError catch (e) {
        expect(e.toString(),
            contains("Bounding value for column 'value' has invalid type"));
      }
    });

    test("Page property doesn't exist throws error", () async {
      try {
        var _ = Query<PageableTestModel>(context)
          ..pageBy((p) => p["foobar"], QuerySortOrder.ascending,
              boundingValue: "0");

        expect(true, false);
      } on ArgumentError catch (e) {
        expect(
            e.toString(),
            contains(
                "Property 'foobar' does not exist on 'PageableTestModel'"));
      }
    });

    test("Query when not fetching paging property still succeeds", () async {
      var req = Query<PageableTestModel>(context)
        ..pageBy((p) => p.value, QuerySortOrder.ascending, boundingValue: "0")
        ..returningProperties((p) => [p.id])
        ..fetchLimit = 5;
      var res = await req.fetch();
      check([2, 3, 4, 5, 6], res);
    });

    test("Page by relationship fails", () async {
      try {
        Query<HasMany>(context)
            .pageBy((p) => p.objects, QuerySortOrder.ascending);
        expect(true, false);
      } on ArgumentError catch (e) {
        expect(e.toString(),
            contains("Property 'objects' on 'HasMany' is a relationship"));
      }
    });
  });
}

class PageableTestModel extends ManagedObject<_PageableTestModel>
    implements _PageableTestModel {}

class _PageableTestModel {
  @primaryKey
  int id;

  String value;
}

class HasMany extends ManagedObject<_HasMany> implements _HasMany {}

class _HasMany {
  @primaryKey
  int id;

  ManagedSet<BelongsTo> objects;
}

class BelongsTo extends ManagedObject<_BelongsTo> implements _BelongsTo {}

class _BelongsTo {
  @primaryKey
  int id;

  @Relate(Symbol('objects'))
  HasMany hasMany;
}
