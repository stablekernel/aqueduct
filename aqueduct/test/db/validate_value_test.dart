import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

import '../helpers.dart';

void main() {
  final ctx = new ManagedContext(new ManagedDataModel([T, U, V, EnumObject]), new DefaultPersistentStore());

  tearDownAll(() async {
    await ctx.close();
  });

  group("Validate.matches", () {
    test("Valid regex reports match", () {
      var t = new T()
        ..regex = "OIASDJKASD"
        ..contain = "XcontainY";
      expect(t.validate().isValid, true);
    });

    test("Invalid regex reports failure", () {
      var t = new T()..regex = "OiASDJKASD";
      expect(t.validate().isValid, false);

      t = new T()..contain = "abcde";
      expect(t.validate().isValid, false);
    });
  });

  group("Validate.compare", () {
    test("lessThan/int", () {
      var t = new T()..compareIntLessThan1 = 0;
      expect(t.validate().isValid, true);
      t.compareIntLessThan1 = 1;
      expect(t.validate().isValid, false);
      t.compareIntLessThan1 = 10;
      expect(t.validate().isValid, false);
    });

    test("lessThanEqual/string", () {
      var t = new T()..compareStringLessThanEqualToBar = "abc";
      expect(t.validate().isValid, true);
      t.compareStringLessThanEqualToBar = "bar";
      expect(t.validate().isValid, true);
      t.compareStringLessThanEqualToBar = "baz";
      expect(t.validate().isValid, false);
    });

    test("greaterThan/double", () {
      var t = new T()..compareDoubleGreaterThan1 = 2.0;
      expect(t.validate().isValid, true);
      t.compareDoubleGreaterThan1 = 1.0;
      expect(t.validate().isValid, false);
      t.compareDoubleGreaterThan1 = 0.0;
      expect(t.validate().isValid, false);
    });

    test("greaterThanEqual/date", () {
      var t = new T()..compareDateGreaterThanEqualTo1990 = new DateTime(2000);
      expect(t.validate().isValid, true);
      t.compareDateGreaterThanEqualTo1990 = new DateTime(1990);
      expect(t.validate().isValid, true);
      t.compareDateGreaterThanEqualTo1990 = new DateTime(1980);
      expect(t.validate().isValid, false);
    });

    test("equal", () {
      var t = new T()..compareIntEqualTo5 = 5;
      expect(t.validate().isValid, true);
      t.compareIntEqualTo5 = 4;
      expect(t.validate().isValid, false);
    });

    test("Combine two yields and of both", () {
      var t = new T()..compareIntBetween6And10 = 6;
      expect(t.validate().isValid, true);
      t.compareIntBetween6And10 = 10;
      expect(t.validate().isValid, true);

      t.compareIntBetween6And10 = 11;
      expect(t.validate().isValid, false);
      t.compareIntBetween6And10 = 5;
      expect(t.validate().isValid, false);
    });
  });

  group("Validate.length", () {
    test("lessThan", () {
      var t = new T()..lengthLessThan5 = "abc";
      expect(t.validate().isValid, true);
      t.lengthLessThan5 = "abcde";
      expect(t.validate().isValid, false);
      t.lengthLessThan5 = "abcdefgh";
      expect(t.validate().isValid, false);
    });

    test("lessThanEqual", () {
      var t = new T()..lengthLessThanEqualTo5 = "abc";
      expect(t.validate().isValid, true);
      t.lengthLessThanEqualTo5 = "abcde";
      expect(t.validate().isValid, true);
      t.lengthLessThanEqualTo5 = "abcdefg";
      expect(t.validate().isValid, false);
    });

    test("greaterThan", () {
      var t = new T()..lengthGreaterThan5 = "abcdefghi";
      expect(t.validate().isValid, true);
      t.lengthGreaterThan5 = "abcde";
      expect(t.validate().isValid, false);
      t.lengthGreaterThan5 = "abc";
      expect(t.validate().isValid, false);
    });

    test("greaterThanEqual", () {
      var t = new T()..lengthGreaterThanEqualTo5 = "abcdefgh";
      expect(t.validate().isValid, true);
      t.lengthGreaterThanEqualTo5 = "abcde";
      expect(t.validate().isValid, true);
      t.lengthGreaterThanEqualTo5 = "abc";
      expect(t.validate().isValid, false);
    });

    test("equal", () {
      var t = new T()..lengthEqualTo2 = "ab";
      expect(t.validate().isValid, true);
      t.lengthEqualTo2 = "c";
      expect(t.validate().isValid, false);
    });

    test("Combine two yields and of both", () {
      var t = new T()..lengthBetween6And10 = "abcdef";
      expect(t.validate().isValid, true);
      t.lengthBetween6And10 = "abcdefghij";
      expect(t.validate().isValid, true);

      t.lengthBetween6And10 = "abcdefghijk";
      expect(t.validate().isValid, false);
      t.lengthBetween6And10 = "abcde";
      expect(t.validate().isValid, false);
    });
  });

  group("Validate.present", () {
    test("Ensures key exists", () {
      var u = new U();
      expect(u.validate().isValid, false);
      u.present = 1;
      expect(u.validate().isValid, true);
    });

    test("Does not care about null, as long as present", () {
      var u = new U()..present = null;
      expect(u.validate().isValid, true);
    });
  });

  group("Validate.absent", () {
    test("Ensures key is absent", () {
      var u = new U()..present = 1;
      expect(u.validate().isValid, true);
      u.absent = 1;
      expect(u.validate().isValid, false);
    });

    test("Does not treat null as absent", () {
      var u = new U()
        ..present = 1
        ..absent = null;
      expect(u.validate().isValid, false);
    });
  });

  group("Validate.oneOf", () {
    test("Works with String", () {
      var t = new T()..oneOfAB = "A";
      expect(t.validate().isValid, true);
      t.oneOfAB = "C";
      expect(t.validate().isValid, false);
    });

    test("Works with int", () {
      var t = new T()..oneOf12 = 1;
      expect(t.validate().isValid, true);
      t.oneOf12 = 3;
      expect(t.validate().isValid, false);
    });

    test("Implicitly added to enum types", () {
      var e = new EnumObject()..backing.contents["enumValues"] = "foobar";
      expect(e.validate().isValid, false);
      e.enumValues = EnumValues.abcd;
      expect(e.validate().isValid, true);
    });
  });

  group("Operation", () {
    test("Specify update only, only runs on update", () {
      var t = new T()..mustBeZeroOnUpdate = 10;
      expect(ManagedValidator.run(t, event: Validating.insert).isValid, true);

      t.mustBeZeroOnUpdate = 10;
      expect(ManagedValidator.run(t, event: Validating.update).isValid, false);

      t.mustBeZeroOnUpdate = 0;
      expect(ManagedValidator.run(t, event: Validating.update).isValid, true);
    });

    test("Specify insert only, only runs on insert", () {
      var t = new T()..mustBeZeroOnInsert = 10;
      expect(ManagedValidator.run(t, event: Validating.update).isValid, true);

      t.mustBeZeroOnInsert = 10;
      expect(ManagedValidator.run(t, event: Validating.insert).isValid, false);

      t.mustBeZeroOnInsert = 0;
      expect(ManagedValidator.run(t, event: Validating.insert).isValid, true);
    });

    test("More than one matcher", () {
      var t = new T()..mustBeBayOrBaz = "bay";
      expect(t.validate().isValid, true);
      t.mustBeBayOrBaz = "baz";
      expect(t.validate().isValid, true);
      t.mustBeBayOrBaz = "bar";
      expect(t.validate().isValid, false);
      t.mustBeBayOrBaz = "baa";
      expect(t.validate().isValid, false);
    });

    test("ManagedObject can provide add'l validations by overriding validate", () async {
      var v = new V()..aOrbButReallyOnlyA = "a";
      expect(v.validate().isValid, true);
      v.aOrbButReallyOnlyA = "b";
      expect(v.validate().isValid, false);
    });
  });

  group("Custom validator verify", () {
    test("Custom validator correctly validates a value", () {
      var t = new T()..mustByXYZ = "XYZ";
      expect(t.validate().isValid, true);
      t.mustByXYZ = "not";
      expect(t.validate().isValid, false);
    });
  });

  group("Data model compilation failures", () {
    test("DateTime fails to parse", () {
      try {
        new ManagedDataModel([FailingDateTime]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.toString(), contains("19x34"));
        expect(e.toString(), contains("cannot be parsed as DateTime"));
        expect(e.toString(), contains("'d'"));
        expect(e.toString(), contains("_FDT"));
      }
    });

    test("Non-string Validate.matches", () {
      try {
        new ManagedDataModel([FailingRegex]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.toString(), contains("must be String"));
        expect(e.toString(), contains("'d'"));
        expect(e.toString(), contains("_FRX"));
      }
    });

    test("Non-string Validate.length", () {
      try {
        new ManagedDataModel([FailingLength]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.toString(), contains("must annotate 'String'"));
        expect(e.toString(), contains("'d'"));
        expect(e.toString(), contains("_FLEN"));
      }
    });

    test("Unsupported type, date, for oneOf", () {
      try {
        new ManagedDataModel([UnsupportedDateOneOf]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.toString(), contains("has invalid validator for property"));
        expect(e.toString(), contains("Validate.oneOf value must be a List, where each element matches the type of the decorated attribute"));
        expect(e.toString(), contains("compareDateOneOf20162017"));
      }
    });

    test("Unsupported type, double, for oneOf", () {
      try {
        new ManagedDataModel([UnsupportedDoubleOneOf]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.toString(), contains("has invalid validator for property"));
        expect(e.toString(), contains("Validate.oneOf value must be a List, where each element matches the type of the decorated attribute"));
        expect(e.toString(), contains("someFloatingNumber"));
      }
    });

    test("Non-matching type for oneOf", () {
      try {
        new ManagedDataModel([FailingOneOf]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.toString(), contains("Validate.oneOf value must be a List, where each element matches the type of the decorated attribute"));
        expect(e.toString(), contains("'d'"));
        expect(e.toString(), contains("_FOO"));
      }
    });

    test("Empty oneOf", () {
      try {
        new ManagedDataModel([FailingEmptyOneOf]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.toString(), contains("must have at least one element"));
        expect(e.toString(), contains("'d'"));
        expect(e.toString(), contains("_FEO"));
      }
    });

    test("Heterogenous oneOf", () {
      try {
        new ManagedDataModel([FailingHeterogenous]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.toString(), contains("Validate.oneOf value must be a List, where each element matches the type of the decorated attribute"));
        expect(e.toString(), contains("'d'"));
        expect(e.toString(), contains("_FH"));
      }
    });
  });
}

class T extends ManagedObject<_T> implements _T {}
class _T {
  @primaryKey
  int id;

  @Validate.matches(r"^[A-Z]+$")
  String regex;

  @Validate.matches("contain")
  String contain;

  @Validate.compare(lessThan: 1)
  int compareIntLessThan1;

  @Validate.compare(greaterThan: 1.0)
  double compareDoubleGreaterThan1;

  @Validate.compare(lessThanEqualTo: "bar")
  String compareStringLessThanEqualToBar;

  @Validate.compare(greaterThanEqualTo: "1990-01-01T00:00:00Z")
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

  @Validate.length(lessThan: 11, greaterThan: 5)
  String lengthBetween6And10;

  @Validate.oneOf(const ["A", "B"])
  String oneOfAB;

  @Validate.oneOf(const [1, 2])
  int oneOf12;

  @Validate.compare(equalTo: 0, onInsert: true, onUpdate: false)
  int mustBeZeroOnInsert;

  @Validate.compare(equalTo: 0, onInsert: false, onUpdate: true)
  int mustBeZeroOnUpdate;

  @Validate.compare(greaterThan: "bar")
  @Validate.oneOf(const ["baa", "bar", "bay", "baz"])
  String mustBeBayOrBaz;

  @CustomValidate()
  String mustByXYZ;
}

class U extends ManagedObject<_U> implements _U {}
class _U {
  @primaryKey
  int id;

  @Validate.present()
  int present;

  @Validate.absent()
  int absent;
}

class CustomValidate extends Validate {
  const CustomValidate({bool onUpdate: true, bool onInsert: true})
    : super(onUpdate: onUpdate, onInsert: onInsert);

  @override
  void validate(ValidationContext context, dynamic input) {
    if (input != "XYZ") {
      context.addError("not XYZ");
    }
  }
}

class FailingDateTime extends ManagedObject<_FDT> {}
class _FDT {
  @primaryKey
  int id;

  @Validate.compare(greaterThanEqualTo: "19x34")
  DateTime d;
}

class FailingRegex extends ManagedObject<_FRX> {}
class _FRX {
  @primaryKey
  int id;

  @Validate.matches("xyz")
  int d;
}

class FailingLength extends ManagedObject<_FLEN> {}
class _FLEN {
  @primaryKey
  int id;

  @Validate.length(equalTo: 6)
  int d;
}

class FailingEmptyOneOf extends ManagedObject<_FEO> {}
class _FEO {
  @primaryKey
  int id;

  @Validate.oneOf(const [])
  int d;
}

class FailingOneOf extends ManagedObject<_FOO> {}
class _FOO {
  @primaryKey
  int id;

  @Validate.oneOf(const ["x", "y"])
  int d;
}

class UnsupportedDateOneOf extends ManagedObject<_UDAOO> {}
class _UDAOO {
  @primaryKey
  int id;

  @Validate.oneOf(const ["2016-01-01T00:00:00", "2017-01-01T00:00:00"])
  DateTime compareDateOneOf20162017;
}

class UnsupportedDoubleOneOf extends ManagedObject<_UDOOO> {}
class _UDOOO {
  @primaryKey
  int id;

  @Validate.oneOf(const ["3.14159265359", "2.71828"])
  double someFloatingNumber;
}

class FailingHeterogenous extends ManagedObject<_FH> {}
class _FH {
  @primaryKey
  int id;

  @Validate.oneOf(const ["x", 1])
  int d;
}

class FailingTransient extends ManagedObject<_FT> {
  @Validate.compare(greaterThanEqualTo: 1)
  int d;
}
class _FT {
  @primaryKey
  int id;
}

class V extends ManagedObject<_V> implements _V {
  @override
  ValidationContext validate({Validating forEvent: Validating.insert}) {
    final context = super.validate(forEvent: forEvent);

    if (aOrbButReallyOnlyA == "b") {
      context.addError("can't be b");
    }

    return context;
  }
}

class _V {
  @primaryKey
  int id;

  @Validate.oneOf(const ["a", "b"])
  String aOrbButReallyOnlyA;
}


class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}
class _EnumObject {
  @primaryKey
  int id;

  EnumValues enumValues;
}

enum EnumValues {
  abcd, efgh, other18
}