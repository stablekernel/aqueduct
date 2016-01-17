import 'package:monadart/monadart.dart';
import 'package:test/test.dart';

main() {
  test("Multiple matchers", () {
    var matcher = new TestModelMatcher();
    matcher.id = 1;
    matcher.name = "Fred";
    var predicate = matcher.predicate;
    expect(predicate.format, "(id = @id_0) and (name = @name_1)");
    expect(predicate.parameters["id_0"], 1);
    expect(predicate.parameters["name_1"], "Fred");

    var now = new DateTime.now();
    matcher = new TestModelMatcher();
    matcher.id = 2;
    matcher.name = "Bob";
    matcher.dateCreatedAt = now;
    predicate = matcher.predicate;
    expect(predicate.format, "(id = @id_0) and (name = @name_1) and (dateCreatedAt = @dateCreatedAt_2)");
    expect(predicate.parameters["id_0"], 2);
    expect(predicate.parameters["name_1"], "Bob");
    expect(predicate.parameters["dateCreatedAt_2"], now);
  });

  test("Assignment matcher - core types", () {
    var matcher = new TestModelMatcher();
    matcher.id = 1;
    var predicate = matcher.predicate;
    expect(predicate.format, "id = @id_0");
    expect(predicate.parameters["id_0"], 1);

    matcher = new TestModelMatcher();
    matcher.name = "Fred";
    predicate = matcher.predicate;
    expect(predicate.format, "name = @name_0");
    expect(predicate.parameters["name_0"], "Fred");

    var now = new DateTime.now();
    matcher = new TestModelMatcher();
    matcher.dateCreatedAt = now;
    predicate = matcher.predicate;
    expect(predicate.format, "dateCreatedAt = @dateCreatedAt_0");
    expect(predicate.parameters["dateCreatedAt_0"], now);
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
  });

  test("Comparison matcher - core types", () {
    var matcher = new TestModelMatcher();
    matcher.id = whenGreaterThan(1);
    matcher.name = "Fred";
    var predicate = matcher.predicate;
    expect(predicate.format, "(id > @id_0) and (name = @name_1)");
    expect(predicate.parameters["id_0"], 1);
    expect(predicate.parameters["name_1"], "Fred");

    matcher = new TestModelMatcher();
    matcher.id = whenLessThan(1);
    predicate = matcher.predicate;
    expect(predicate.format, "id < @id_0");
    expect(predicate.parameters["id_0"], 1);

    matcher = new TestModelMatcher();
    matcher.id = whenNotEqual(1);
    predicate = matcher.predicate;
    expect(predicate.format, "id != @id_0");
    expect(predicate.parameters["id_0"], 1);

    matcher = new TestModelMatcher();
    matcher.id = whenLessThanEqualTo(1);
    predicate = matcher.predicate;
    expect(predicate.format, "id <= @id_0");
    expect(predicate.parameters["id_0"], 1);

    matcher = new TestModelMatcher();
    matcher.id = whenGreaterThanEqualTo(1);
    predicate = matcher.predicate;
    expect(predicate.format, "id >= @id_0");
    expect(predicate.parameters["id_0"], 1);
  });

  test("Range matcher - core types", () {
    var matcher = new TestModelMatcher();
    matcher.id = whenBetween(1, 2);
    var predicate = matcher.predicate;
    expect(predicate.format, "id between @id_lhs0 and @id_rhs0");
    expect(predicate.parameters["id_lhs0"], 1);
    expect(predicate.parameters["id_rhs0"], 2);

    matcher = new TestModelMatcher();
    matcher.id = whenOutsideOf(1, 2);
    predicate = matcher.predicate;
    expect(predicate.format, "id not between @id_lhs0 and @id_rhs0");
    expect(predicate.parameters["id_lhs0"], 1);
    expect(predicate.parameters["id_rhs0"], 2);

    matcher = new TestModelMatcher();
    matcher.id = whenOutsideOf(1, 2);
    matcher.name = "Bob";
    predicate = matcher.predicate;
    expect(predicate.format, "(id not between @id_lhs0 and @id_rhs0) and (name = @name_1)");
    expect(predicate.parameters["id_lhs0"], 1);
    expect(predicate.parameters["id_rhs0"], 2);
    expect(predicate.parameters["name_1"], "Bob");
  });

  test("Null matcher", () {
    var matcher = new TestModelMatcher();
    matcher.id = whenNull;
    var predicate = matcher.predicate;
    expect(predicate.format, "id isnull");

    matcher = new TestModelMatcher();
    matcher.id = whenNotNull;
    predicate = matcher.predicate;
    expect(predicate.format, "id notnull");

  });
}

@proxy @ModelBacking(TestModelBacking)
class TestModel extends Model implements TestModelBacking {

}

@proxy @ModelBacking(TestModelBacking)
class TestModelMatcher extends ModelMatcher implements TestModelBacking {

}

class TestModelBacking {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  DateTime dateCreatedAt;
}