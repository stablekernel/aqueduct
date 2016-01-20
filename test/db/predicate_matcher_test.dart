import 'package:monadart/monadart.dart';
import 'package:test/test.dart';
import 'dart:mirrors';

main() {

  test("Multiple matchers", () {
    var matcher = new TestModelMatcher();
    matcher.id = 1;
    matcher.name = "Fred";
    var predicate = matcher.predicate;

    expect(predicate.format, "(_TestModel.id = @id_0) and (_TestModel.name = @name_1)");
    expect(predicate.parameters["id_0"], 1);
    expect(predicate.parameters["name_1"], "Fred");

    var now = new DateTime.now();
    matcher = new TestModelMatcher();
    matcher.id = 2;
    matcher.name = "Bob";
    matcher.dateCreatedAt = now;
    predicate = matcher.predicate;
    expect(predicate.format, "(_TestModel.id = @id_0) and (_TestModel.name = @name_1) and (_TestModel.dateCreatedAt = @dateCreatedAt_2)");
    expect(predicate.parameters["id_0"], 2);
    expect(predicate.parameters["name_1"], "Bob");
    expect(predicate.parameters["dateCreatedAt_2"], now);
  });

  test("Assignment matcher - core types", () {
    var matcher = new TestModelMatcher();
    matcher.id = 1;
    var predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.id = @id_0");
    expect(predicate.parameters["id_0"], 1);

    matcher = new TestModelMatcher();
    matcher.name = "Fred";
    predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.name = @name_0");
    expect(predicate.parameters["name_0"], "Fred");

    var now = new DateTime.now();
    matcher = new TestModelMatcher();
    matcher.dateCreatedAt = now;
    predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.dateCreatedAt = @dateCreatedAt_0");
    expect(predicate.parameters["dateCreatedAt_0"], now);

    var defaultMatcher = new ModelMatcher<_TestModel>()
      ..["id"] = 1;
    predicate = defaultMatcher.predicate;
    expect(predicate.format, "_TestModel.id = @id_0");
    expect(predicate.parameters["id_0"], 1);
  });

  test("Assignment matcher must match type - core types", () {
    var matcher = new TestModelMatcher();
    try {
      matcher.id = "string";
      fail("This shouldn't work");
    } on PredicateMatcherException catch (e) {
      expect(e.message, startsWith("Type mismatch for property"));
    } catch (e) {
      expect(e, isNull);
    }

    try {
      matcher.name = 2;
      fail("This shouldn't work");
    } on PredicateMatcherException catch (e) {
      expect(e.message, startsWith("Type mismatch for property"));
    } catch (e) {
      expect(e, isNull);
    }
    try {
      matcher.dateCreatedAt = "foo";
      fail("This shouldn't work");
    } on PredicateMatcherException catch (e) {
      expect(e.message, startsWith("Type mismatch for property"));
    } catch (e) {
      expect(e, isNull);
    }

    try {
      var _ = new ModelMatcher<_TestModel>()
        ..["id"] = "foo";
    } on PredicateMatcherException catch (e) {
      expect(e.message, startsWith("Type mismatch for property"));
    } catch (e) {
      expect(e, isNull);
    }
  });

  test("Comparison matcher - core types", () {
    var matcher = new TestModelMatcher();
    matcher.id = whereGreaterThan(1);
    matcher.name = "Fred";
    var predicate = matcher.predicate;
    expect(predicate.format, "(_TestModel.id > @id_0) and (_TestModel.name = @name_1)");
    expect(predicate.parameters["id_0"], 1);
    expect(predicate.parameters["name_1"], "Fred");

    matcher = new TestModelMatcher();
    matcher.id = whereLessThan(1);
    predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.id < @id_0");
    expect(predicate.parameters["id_0"], 1);

    matcher = new TestModelMatcher();
    matcher.id = whereNotEqual(1);
    predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.id != @id_0");
    expect(predicate.parameters["id_0"], 1);

    matcher = new TestModelMatcher();
    matcher.id = whereLessThanEqualTo(1);
    predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.id <= @id_0");
    expect(predicate.parameters["id_0"], 1);

    matcher = new TestModelMatcher();
    matcher.id = whereGreaterThanEqualTo(1);
    predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.id >= @id_0");
    expect(predicate.parameters["id_0"], 1);
  });

  test("Range matcher - core types", () {
    var matcher = new TestModelMatcher();
    matcher.id = whereBetween(1, 2);
    var predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.id between @id_lhs0 and @id_rhs1");
    expect(predicate.parameters["id_lhs0"], 1);
    expect(predicate.parameters["id_rhs1"], 2);

    matcher = new TestModelMatcher();
    matcher.id = whereOutsideOf(1, 2);
    predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.id not between @id_lhs0 and @id_rhs1");
    expect(predicate.parameters["id_lhs0"], 1);
    expect(predicate.parameters["id_rhs1"], 2);

    matcher = new TestModelMatcher();
    matcher.id = whereOutsideOf(1, 2);
    matcher.name = "Bob";
    predicate = matcher.predicate;
    expect(predicate.format, "(_TestModel.id not between @id_lhs0 and @id_rhs1) and (_TestModel.name = @name_2)");
    expect(predicate.parameters["id_lhs0"], 1);
    expect(predicate.parameters["id_rhs1"], 2);
    expect(predicate.parameters["name_2"], "Bob");
  });

  test("Null matcher", () {
    var matcher = new TestModelMatcher();
    matcher.id = whereNull;
    var predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.id isnull");

    matcher = new TestModelMatcher();
    matcher.id = whereNotNull;
    predicate = matcher.predicate;
    expect(predicate.format, "_TestModel.id notnull");
  });

  test("String matcher", () {

  });

  test("belongsTo relationship matcher", () {
    var toManyMatcher = new ModelMatcher<_TestModelBelongToMany>()
      ..["modelToMany"] = whereRelatedByValue(1);
    var predicate = toManyMatcher.predicate;

    expect(predicate.format, "_TestModelBelongToMany.modelToMany_id = @modelToMany_id_0");
    expect(predicate.parameters, {"modelToMany_id_0" : 1});

    toManyMatcher = new TestModelBelongToManyMatcher()
      ..modelToMany = whereRelatedByValue(1);
    predicate = toManyMatcher.predicate;

    expect(predicate.format, "_TestModelBelongToMany.modelToMany_id = @modelToMany_id_0");
    expect(predicate.parameters, {"modelToMany_id_0" : 1});

  });

  test("One-level join", () {
    var m = new TestModelMatcher()
        ..id = 1
        ..toMany = whereAnyMatch;
    expect(m.predicate.format, "_TestModel.id = @id_0");
    expect(m.predicate.parameters["id_0"], 1);

    //var subMatchers =

  });

  test("One-level join with predicate", () {
    var m = new TestModelMatcher()
      ..id = whereLessThan(3)
      ..name = "Fred"
      ..toMany = whereMatching(new TestModelBelongToManyMatcher()
        ..id = whereLessThan(1));

    expect(m.predicate.format, "(_TestModel.id < @id_0) and (_TestModel.name = @name_1) and (_TestModelBelongToMany.id < @id_2)");
    expect(m.predicate.parameters["id_0"], 3);
    expect(m.predicate.parameters["name_1"], "Fred");
    expect(m.predicate.parameters["id_2"], 1);

    m = new ModelMatcher<_TestModel>()
      ..["id"] = whereLessThan(3)
      ..["toMany"] = whereMatching(new ModelMatcher<_TestModelBelongToMany>()
        ..["id"] = whereLessThan(1));

    expect(m.predicate.format, "(_TestModel.id < @id_0) and (_TestModelBelongToMany.id < @id_1)");
    expect(m.predicate.parameters["id_0"], 3);
    expect(m.predicate.parameters["id_1"], 1);

  });
}

@proxy
class TestModel extends Model<_TestModel> implements _TestModel {}

@proxy
class TestModelMatcher extends ModelMatcher<_TestModel> implements _TestModel {}

class _TestModel {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  DateTime dateCreatedAt;

  @RelationshipAttribute.hasMany("modelToMany")
  List<TestModelBelongToMany> toMany;

  @RelationshipAttribute.hasOne("modelToOne")
  TestModelBelongToOne toOne;
}

@proxy
class TestModelBelongToOne extends Model<_TestModelBelongToOne> implements _TestModelBelongToOne {
}

@proxy
class TestModelBelongToOneMatcher extends ModelMatcher<_TestModelBelongToOne> implements _TestModelBelongToOne {
}

class _TestModelBelongToOne {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  @RelationshipAttribute.belongsTo("toOne")
  TestModel modelToOne;
}

@proxy
class TestModelBelongToMany extends Model<_TestModelBelongToMany> implements _TestModel {
}

@proxy
class TestModelBelongToManyMatcher extends ModelMatcher<_TestModelBelongToMany> implements _TestModelBelongToMany {
}

class _TestModelBelongToMany {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  @RelationshipAttribute.belongsTo("toMany")
  TestModel modelToMany;
}