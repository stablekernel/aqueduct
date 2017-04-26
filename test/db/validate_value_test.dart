import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  var dataModel = new ManagedDataModel([T]);
  ManagedContext.defaultContext = new ManagedContext(dataModel, null);

  group("Validate.matches", () {
    test("Valid regex reports match", () {
      var t = new T()
        ..regex = "OIASDJKASD"
        ..contain = "XcontainY";
      expect(Validate.run(t), true);
    });

    test("Invalid regex reports failure", () {
      var t = new T()..regex = "OiASDJKASD";
      expect(Validate.run(t), false);

      t = new T()..contain = "abcde";
      expect(Validate.run(t), false);
    });
  });

  group("Validate.compare", () {
    test("Can compare int", () {

    });

    test("Can compare datetime", () {

    });

    test("Can compare double", () {

    });

    test("Can compare string", () {

    });

    test("Can compare double", () {

    });

    test("lessThan", () {

    });

    test("lessThanEqual", () {

    });

    test("greaterThan", () {

    });

    test("greaterThanEqual", () {

    });

    test("equal", () {

    });

    test("Combine two yields and of both", () {

    });
  });

  group("Validate.length", () {
    test("lessThan", () {

    });

    test("lessThanEqual", () {

    });

    test("greaterThan", () {

    });

    test("greaterThanEqual", () {

    });

    test("equal", () {

    });

    test("Combine two yields and of both", () {

    });
  });

  group("Validate.present", () {
    test("Ensures key exists", () {

    });

    test("Does not care about null, as long as present", () {

    });
  });

  group("Validate.absent", () {
    test("Ensures key is absent", () {

    });

    test("Does not treat null as abset", () {

    });
  });

  group("Validate.oneOf", () {
    test("Works with String", () {

    });

    test("Works with int", () {

    });

    test("Reports failure if out of set", () {

    });
  });

  group("Operation", () {
    test("Default runs on both update and create", () {

    });

    test("Specify update only, only runs on update", () {

    });

    test("Specify insert only, only runs on insert", () {

    });

    test("More than one matcher, both succeed", () {

    });

    test("More than one matcher, one or the other fails, reports error", () {

    });

    test("More than one matcher, both fail, reports both errors", () {

    });
  });

  group("Data model compilation failures", () {
    test("Non-string Validate.matches", () {

    });

    test("Non-string Validate.length", () {

    });

    test("Cannot add validate to transient", () {

    });

    test("Cannot add validate to ManagedObject", () {

    });

    test("Cannot add validate to ManagedSet", () {

    });
  });

  group("Custom validator verify", () {
    test("Custom validator correctly validates a value", () {

    });
  });
}

class T extends ManagedObject<_T> implements _T {}
class _T {
  @managedPrimaryKey
  int id;

  @Validate.matches(r"^[A-Z]+$")
  String regex;

  @Validate.matches("contain")
  String contain;

  @Validate.compare(lessThan: 1)
  int compareIntLessThan1;

  @Validate.compare(greaterThan: 1)
  double compareDoubleGreaterThan1;

  @Validate.compare(lessThanEqualTo: "bar")
  String compareStringLessThanEqualToBar;

  @Validate.compare(greaterThanEqualTo: "1990-01-01T00:45:11Z")
  DateTime compareDateGreaterThanEqualTo1990;

  @Validate.compare(equalTo: 5)
  int compareIntEqualTo5;

  @Validate.compare(lessThan: 11, greaterThan: 5)
  int compareIntBetween6And10;

  @Validate.length(lessThan: 5)
  String lengthLessThan5;

  @Validate.length(lessThanEqualTo: 5)
  String lengthLessThanEqualTo5;

  @Validate.length(greaterThan: 5)
  String lengthGreaterThan5;

  @Validate.length(greaterThanEqualTo: 5)
  String lengthGreaterThanEqualTo5;

  @Validate.length(equalTo: 2)
  String lengthEqualTo2;

  @Validate.oneOf(const ["a", "b"])
  String oneOfAB;

  @Validate.oneOf(const [1, 2]);
  int oneOf12;
}

class U extends ManagedObject<_U> implements _U {}
class _U {
  @managedPrimaryKey
  int id;

  @Validate
}