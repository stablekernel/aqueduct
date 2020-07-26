import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  final ctx = ManagedContext(
      ManagedDataModel([
        T,
        U,
        V,
        EnumObject,
        Constant,
        ConstantRef,
        FK,
        Parent,
        PresenceHas,
        PresenceBelongsTo,
        AbsenceBelongsTo,
        AbsenceHas,
        NonDefaultPK,
        MultiValidate
      ]),
      DefaultPersistentStore());

  tearDownAll(() async {
    await ctx.close();
  });

  group("Primary key defaults", () {
    test("@primaryKey defaults to using Validate.constant()", () async {
      final t = T()..id = 1;
      expect((await t.validate(forEvent: Validating.insert)).isValid, true);
      expect((await t.validate(forEvent: Validating.update)).isValid, false);
    });

    test(
        "A primary key that isn't @primaryKey does not have Validate.constant()",
        () async {
      final t = NonDefaultPK()..id = 1;
      expect((await t.validate(forEvent: Validating.insert)).isValid, true);
      expect((await t.validate(forEvent: Validating.update)).isValid, true);
    });
  });

  group("Foreign keys", () {
    test("Validator applies to foreign key value", () async {
      final fk = FK();
      fk.parent = Parent()..id = 1;
      expect((await fk.validate()).isValid, false);
      expect((await fk.validate()).errors.first, contains("FK.parent.id"));

      fk.parent.id = 2;
      expect((await fk.validate()).isValid, true);
    });

    test("If foreign key object is null, validator is not run", () async {
      final fk = FK();
      expect((await fk.validate()).isValid, true);
    });

    test(
        "If foreign key object doesn't contain primary key, validator is not run",
        () async {
      final fk = FK();
      fk.parent = Parent();
      expect((await fk.validate()).isValid, true);
    });

    test(
        "If primary key has a validator, it is not run when evaluated as a foreign key",
        () async {
      final fk = FK();
      fk.parent = Parent()..id = 10;
      expect((await fk.validate()).isValid, true);

      expect((await fk.parent.validate()).isValid, false);
      expect((await fk.parent.validate()).errors.first, contains("Parent.id"));
    });
  });

  group("Validate.matches", () {
    test("Valid regex reports match", () async {
      var t = T()
        ..regex = "OIASDJKASD"
        ..contain = "XcontainY";
      expect((await t.validate()).isValid, true);
    });

    test("Invalid regex reports failure", () async {
      var t = T()..regex = "OiASDJKASD";
      expect((await t.validate()).isValid, false);

      t = T()..contain = "abcde";
      expect((await t.validate()).isValid, false);
    });
  });

  group("Validate.compare", () {
    test("lessThan/int", () async {
      var t = T()..compareIntLessThan1 = 0;
      expect((await t.validate()).isValid, true);
      t.compareIntLessThan1 = 1;
      expect((await t.validate()).isValid, false);
      t.compareIntLessThan1 = 10;
      expect((await t.validate()).isValid, false);
    });

    test("lessThanEqual/string", () async {
      var t = T()..compareStringLessThanEqualToBar = "abc";
      expect((await t.validate()).isValid, true);
      t.compareStringLessThanEqualToBar = "bar";
      expect((await t.validate()).isValid, true);
      t.compareStringLessThanEqualToBar = "baz";
      expect((await t.validate()).isValid, false);
    });

    test("greaterThan/double", () async {
      var t = T()..compareDoubleGreaterThan1 = 2.0;
      expect((await t.validate()).isValid, true);
      t.compareDoubleGreaterThan1 = 1.0;
      expect((await t.validate()).isValid, false);
      t.compareDoubleGreaterThan1 = 0.0;
      expect((await t.validate()).isValid, false);
    });

    test("greaterThanEqual/date", () async {
      var t = T()..compareDateGreaterThanEqualTo1990 = DateTime(2000);
      expect((await t.validate()).isValid, true);
      t.compareDateGreaterThanEqualTo1990 = DateTime(1990);
      expect((await t.validate()).isValid, true);
      t.compareDateGreaterThanEqualTo1990 = DateTime(1980);
      expect((await t.validate()).isValid, false);
    });

    test("equal", () async {
      var t = T()..compareIntEqualTo5 = 5;
      expect((await t.validate()).isValid, true);
      t.compareIntEqualTo5 = 4;
      expect((await t.validate()).isValid, false);
    });

    test("Combine two yields and of both", () async {
      var t = T()..compareIntBetween6And10 = 6;
      expect((await t.validate()).isValid, true);
      t.compareIntBetween6And10 = 10;
      expect((await t.validate()).isValid, true);

      t.compareIntBetween6And10 = 11;
      expect((await t.validate()).isValid, false);
      t.compareIntBetween6And10 = 5;
      expect((await t.validate()).isValid, false);
    });
  });

  group("Validate.length", () {
    test("lessThan", () async {
      var t = T()..lengthLessThan5 = "abc";
      expect((await t.validate()).isValid, true);
      t.lengthLessThan5 = "abcde";
      expect((await t.validate()).isValid, false);
      t.lengthLessThan5 = "abcdefgh";
      expect((await t.validate()).isValid, false);
    });

    test("lessThanEqual", () async {
      var t = T()..lengthLessThanEqualTo5 = "abc";
      expect((await t.validate()).isValid, true);
      t.lengthLessThanEqualTo5 = "abcde";
      expect((await t.validate()).isValid, true);
      t.lengthLessThanEqualTo5 = "abcdefg";
      expect((await t.validate()).isValid, false);
    });

    test("greaterThan", () async {
      var t = T()..lengthGreaterThan5 = "abcdefghi";
      expect((await t.validate()).isValid, true);
      t.lengthGreaterThan5 = "abcde";
      expect((await t.validate()).isValid, false);
      t.lengthGreaterThan5 = "abc";
      expect((await t.validate()).isValid, false);
    });

    test("greaterThanEqual", () async {
      var t = T()..lengthGreaterThanEqualTo5 = "abcdefgh";
      expect((await t.validate()).isValid, true);
      t.lengthGreaterThanEqualTo5 = "abcde";
      expect((await t.validate()).isValid, true);
      t.lengthGreaterThanEqualTo5 = "abc";
      expect((await t.validate()).isValid, false);
    });

    test("equal", () async {
      var t = T()..lengthEqualTo2 = "ab";
      expect((await t.validate()).isValid, true);
      t.lengthEqualTo2 = "c";
      expect((await t.validate()).isValid, false);
    });

    test("Combine two yields and of both", () async {
      var t = T()..lengthBetween6And10 = "abcdef";
      expect((await t.validate()).isValid, true);
      t.lengthBetween6And10 = "abcdefghij";
      expect((await t.validate()).isValid, true);

      t.lengthBetween6And10 = "abcdefghijk";
      expect((await t.validate()).isValid, false);
      t.lengthBetween6And10 = "abcde";
      expect((await t.validate()).isValid, false);
    });
  });

  group("Validate.present", () {
    test("Ensures key exists", () async {
      var u = U();
      expect((await u.validate()).isValid, false);
      u.present = 1;
      expect((await u.validate()).isValid, true);
    });

    test("Does not care about null, as long as present", () async {
      var u = U()..present = null;
      expect((await u.validate()).isValid, true);
    });

    test("Relationship primary key must be present", () async {
      final o = PresenceBelongsTo();
      expect((await o.validate()).isValid, false);
      o.present = PresenceHas();
      expect((await o.validate()).isValid, false);
      o.present = PresenceHas()..id = 1;
      expect((await o.validate()).isValid, true);
    });

    test("Ensure foreign object key exists", () async {
      final fk = PresenceBelongsTo();
      expect((await fk.validate()).isValid, false);
    });

    test("If foreign key object is null, validator fails", () async {
      final fk = PresenceBelongsTo()..present = null;
      expect((await fk.validate()).isValid, false);
    });

    test("If foreign key object doesn't contain primary key, validator fails",
        () async {
      final fk = PresenceBelongsTo()..present = PresenceHas();
      expect((await fk.validate()).isValid, false);
      expect((await fk.validate()).errors.first,
          contains("PresenceBelongsTo.present.id"));
    });
  });

  group("Validate.absent", () {
    test("Ensures key is absent", () async {
      var u = U()..present = 1;
      expect((await u.validate()).isValid, true);
      u.absent = 1;
      expect((await u.validate()).isValid, false);
    });

    test("Does not treat null as absent", () async {
      var u = U()
        ..present = 1
        ..absent = null;
      expect((await u.validate()).isValid, false);
    });

    test("Relationship key must be absent", () async {
      final o = AbsenceBelongsTo();
      expect((await o.validate()).isValid, true);

      o.absent = AbsenceHas();
      expect((await o.validate()).isValid, false);
      expect((await o.validate()).errors.first,
          contains("AbsenceBelongsTo.absent.id"));

      o.absent = AbsenceHas()..id = 1;
      expect((await o.validate()).isValid, false);
      expect((await o.validate()).errors.first,
          contains("AbsenceBelongsTo.absent.id"));
    });
  });

  group("Validate.oneOf", () {
    test("Works with String", () async {
      var t = T()..oneOfAB = "A";
      expect((await t.validate()).isValid, true);
      t.oneOfAB = "C";
      expect((await t.validate()).isValid, false);
    });

    test("Works with int", () async {
      var t = T()..oneOf12 = 1;
      expect((await t.validate()).isValid, true);
      t.oneOf12 = 3;
      expect((await t.validate()).isValid, false);
    });

    test("Implicitly added to enum types", () async {
      var e = EnumObject()..backing.contents["enumValues"] = "foobar";
      expect((await e.validate()).isValid, false);
      e.enumValues = EnumValues.abcd;
      expect((await e.validate()).isValid, true);
    });
  });

  group("Validate.constant", () {
    test("Allows attributes during insert, not update", () async {
      var t = Constant()..constantString = "A";
      expect((await t.validate(forEvent: Validating.insert)).isValid, true);

      expect((await t.validate(forEvent: Validating.update)).isValid, false);
    });

    test("Allows relationships during insert, not update", () async {
      var t = Constant()
        ..constantRef = ConstantRef()
        ..id = 1;
      expect((await t.validate(forEvent: Validating.insert)).isValid, true);
      expect((await t.validate(forEvent: Validating.update)).isValid, false);
    });
  });

  group("Operation", () {
    test("Specify update only, only runs on update", () async {
      var t = T()..mustBeZeroOnUpdate = 10;
      expect((await ManagedValidator.run(t, event: Validating.insert)).isValid,
          true);

      t.mustBeZeroOnUpdate = 10;
      expect((await ManagedValidator.run(t, event: Validating.update)).isValid,
          false);

      t.mustBeZeroOnUpdate = 0;
      expect((await ManagedValidator.run(t, event: Validating.update)).isValid,
          true);
    });

    test("Specify insert only, only runs on insert", () async {
      var t = T()..mustBeZeroOnInsert = 10;
      expect((await ManagedValidator.run(t, event: Validating.update)).isValid,
          true);

      t.mustBeZeroOnInsert = 10;
      expect((await ManagedValidator.run(t, event: Validating.insert)).isValid,
          false);

      t.mustBeZeroOnInsert = 0;
      expect((await ManagedValidator.run(t, event: Validating.insert)).isValid,
          true);
    });

    test("More than one matcher", () async {
      var t = T()..mustBeBayOrBaz = "bay";
      expect((await t.validate()).isValid, true);
      t.mustBeBayOrBaz = "baz";
      expect((await t.validate()).isValid, true);
      t.mustBeBayOrBaz = "bar";
      expect((await t.validate()).isValid, false);
      t.mustBeBayOrBaz = "baa";
      expect((await t.validate()).isValid, false);
    });

    test("ManagedObject can provide add'l validations by overriding validate",
        () async {
      var v = V()..aOrbButReallyOnlyA = "a";
      expect((await v.validate()).isValid, true);
      v.aOrbButReallyOnlyA = "b";
      expect((await v.validate()).isValid, false);
    });
  });

  group("Custom validator verify", () {
    test("Custom validator correctly validates a value", () async {
      var t = T()..mustByXYZ = "XYZ";
      expect((await t.validate()).isValid, true);
      t.mustByXYZ = "not";
      expect((await t.validate()).isValid, false);
    });
  });

  test("Can combine both metadata and arguments to Column", () async {
    final x = MultiValidate()..canOnlyBe4 = 3;
    expect((await x.validate()).isValid, false);
    x.canOnlyBe4 = 5;
    expect((await x.validate()).isValid, false);
    x.canOnlyBe4 = 4;
    expect((await x.validate()).isValid, true);

    final allValidators = x.entity.attributes['canOnlyBe4'].validators;
    expect(allValidators.length, 4);
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

  @Validate.oneOf(["A", "B"])
  String oneOfAB;

  @Validate.oneOf([1, 2])
  int oneOf12;

  @Validate.compare(equalTo: 0, onInsert: true, onUpdate: false)
  int mustBeZeroOnInsert;

  @Validate.compare(equalTo: 0, onInsert: false, onUpdate: true)
  int mustBeZeroOnUpdate;

  @Validate.compare(greaterThan: "bar")
  @Validate.oneOf(["baa", "bar", "bay", "baz"])
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
  const CustomValidate({bool onUpdate = true, bool onInsert = true})
      : super(onUpdate: onUpdate, onInsert: onInsert);

  @override
  Future<void> validate(ValidationContext context, dynamic input) async {
    if (input != "XYZ") {
      context.addError("not XYZ");
    }
  }
}

class V extends ManagedObject<_V> implements _V {
  @override
  Future<ValidationContext> validate(
      {Validating forEvent = Validating.insert}) async {
    final context = await super.validate(forEvent: forEvent);

    if (aOrbButReallyOnlyA == "b") {
      context.addError("can't be b");
    }

    return context;
  }
}

class Constant extends ManagedObject<_Constant> implements _Constant {}

class _Constant {
  @primaryKey
  int id;

  @Validate.constant()
  String constantString;

  @Validate.constant()
  @Relate(#constant)
  ConstantRef constantRef;
}

class ConstantRef extends ManagedObject<_ConstantRef> implements _ConstantRef {}

class _ConstantRef {
  @primaryKey
  int id;

  Constant constant;
}

class _V {
  @primaryKey
  int id;

  @Validate.oneOf(["a", "b"])
  String aOrbButReallyOnlyA;
}

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}

class _EnumObject {
  @primaryKey
  int id;

  EnumValues enumValues;
}

enum EnumValues { abcd, efgh, other18 }

class FK extends ManagedObject<_FK> implements _FK {}

class _FK {
  @primaryKey
  int id;

  @Validate.compare(greaterThan: 1)
  @Relate(#fk)
  Parent parent;
}

class Parent extends ManagedObject<_Parent> implements _Parent {}

class _Parent {
  @Validate.compare(greaterThan: 100)
  @primaryKey
  int id;

  FK fk;
}

class PresenceHas extends ManagedObject<_PresenceHas> implements _PresenceHas {}

class _PresenceHas {
  @primaryKey
  int id;

  ManagedSet<PresenceBelongsTo> present;
}

class PresenceBelongsTo extends ManagedObject<_PresenceBelongsTo>
    implements _PresenceBelongsTo {}

class _PresenceBelongsTo {
  @primaryKey
  int id;

  @Validate.present(onInsert: true)
  @Relate(#present)
  PresenceHas present;
}

class AbsenceHas extends ManagedObject<_AbsenceHas> implements _AbsenceHas {}

class _AbsenceHas {
  @primaryKey
  int id;

  ManagedSet<AbsenceBelongsTo> absent;
}

class AbsenceBelongsTo extends ManagedObject<_AbsenceBelongsTo>
    implements _AbsenceBelongsTo {}

class _AbsenceBelongsTo {
  @primaryKey
  int id;

  @Validate.absent(onInsert: true)
  @Relate(#absent)
  AbsenceHas absent;
}

class NonDefaultPK extends ManagedObject<_NonDefaultPK>
    implements _NonDefaultPK {}

class _NonDefaultPK {
  @Column(
      primaryKey: true,
      databaseType: ManagedPropertyType.bigInteger,
      autoincrement: true)
  int id;

  String name;
}

class MultiValidate extends ManagedObject<_MultiValidate>
    implements _MultiValidate {}

const validateReference = Validate.compare(lessThan: 100);

class _MultiValidate {
  @primaryKey
  int id;

  @validateReference
  @Validate.compare(lessThan: 5)
  @Column(validators: [
    Validate.compare(greaterThan: 3),
    Validate.compare(equalTo: 4)
  ])
  int canOnlyBe4;
}
