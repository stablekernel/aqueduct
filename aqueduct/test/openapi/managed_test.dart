import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/utilities/documented_element.dart';
import 'package:aqueduct/src/utilities/documented_element_analyzer_bridge.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  DocumentedElement.provider = AnalyzerDocumentedElementProvider();

  APIDocument doc;
  ManagedDataModel dataModel;

  setUpAll(() async {
    dataModel = ManagedDataModel([Model1, Model2, Model3]);
    final dbCtx = ManagedContext(dataModel, DefaultPersistentStore());
    doc = APIDocument()
      ..info = APIInfo("x", "1.0.0")
      ..paths = {}
      ..components = APIComponents();
    final ctx = APIDocumentContext(doc);
    dbCtx.documentComponents(ctx);
    await ctx.finalize();
  });

  group("Entity descriptions", () {
    test("Contains all entities in data model", () {
      expect(doc.components.schemas.length, 3);
    });

    test("Schema object contains all persistent attributes with correct types",
        () {
      final entity = doc.components.schemas["Model1"];
      expect(entity.properties["string"].type, APIType.string);
      expect(entity.properties["dateTime"].type, APIType.string);
      expect(entity.properties["dateTime"].format, "date-time");
      expect(entity.properties["id"].type, APIType.integer);
      expect(entity.properties["boolean"].type, APIType.boolean);
    });

    test("Schema object contains all transient attributes", () {
      final entity = doc.components.schemas["Model1"];
      expect(entity.properties["getter"].type, APIType.string);
      expect(entity.properties["getter"].isWriteOnly, false);
      expect(entity.properties["getter"].isReadOnly, true);

      expect(entity.properties["setter"].type, APIType.integer);
      expect(entity.properties["setter"].isWriteOnly, true);
      expect(entity.properties["setter"].isReadOnly, false);

      expect(entity.properties["field"].type, APIType.string);
      expect(entity.properties["field"].format, "date-time");
      expect(entity.properties["field"].isWriteOnly, false);
      expect(entity.properties["field"].isReadOnly, false);
    });

    test("Schema contains to-many relationships", () {
      final entity = doc.components.schemas["Model1"];
      expect(entity.properties["model2s"].type, APIType.array);
      expect(entity.properties["model2s"].items.referenceURI.path,
          "/components/schemas/Model2");
    });

    test("Schema contains to-one relationships", () {
      final entity = doc.components.schemas["Model1"];
      expect(entity.properties["model3"].referenceURI.path,
          "/components/schemas/Model3");
    });

    test("Schema contains belongs-to relationships", () {
      final model2 = doc.components.schemas["Model2"];
      expect(model2.properties["model1"].referenceURI.path,
          "/components/schemas/Model1");

      final model3 = doc.components.schemas["Model3"];
      expect(model3.properties["model1"].referenceURI.path,
          "/components/schemas/Model1");
    });

    test(
        "If property is not in default set, it should not be included in schema",
        () {
      const model = Model3;
      const propName = "notIncluded";

      // just make sure we're right that Model3.notIncluded is actually a property...
      expect(dataModel.entityForType(model).attributes[propName], isNotNull);

      final model3 = doc.components
          .schemas[MirrorSystem.getName(reflectType(model).simpleName)];
      // ... since we're checking that it doesn't exist in the spec
      expect(model3.properties[propName], isNull);
    });

    test("Entity default value is available in schema", () {
      final schema = doc.components.schemas["Model1"];
      expect(schema.properties["boolean"].defaultValue, "true");
    });
  });

  group("Validation additions", () {
    APISchemaObject schema;

    setUpAll(() {
      schema = doc.components.schemas["Model3"];
    });

    test("Custom validator documents schema object", () {
      expect(schema.properties["customValidate"].maxProperties, 2);
    });

    test("Regex validator contains pattern in schema object", () {
      expect(schema.properties["matches"].pattern, "xb");
    });

    test("Schema object contains maximum if min value in validator", () {
      expect(schema.properties["lessThan"].maximum, 1);
      expect(schema.properties["lessThan"].exclusiveMaximum, true);
      expect(schema.properties["lessThan"].minimum, isNull);
      expect(schema.properties["lessThan"].exclusiveMinimum, isNull);
    });

    test(
        "Schema object contains maximumExclusive if min exclusive value in validator",
        () {
      expect(schema.properties["lessThanEqualTo"].maximum, 1);
      expect(schema.properties["lessThanEqualTo"].exclusiveMaximum, false);
      expect(schema.properties["lessThanEqualTo"].minimum, isNull);
      expect(schema.properties["lessThanEqualTo"].exclusiveMinimum, isNull);
    });

    test("Schema object contains minimum if max value in validator", () {
      expect(schema.properties["greaterThan"].maximum, isNull);
      expect(schema.properties["greaterThan"].exclusiveMaximum, isNull);
      expect(schema.properties["greaterThan"].minimum, 1);
      expect(schema.properties["greaterThan"].exclusiveMinimum, true);
    });

    test(
        "Schema object contains minimumExclusive if max exclusive value in validator",
        () {
      expect(schema.properties["greaterThanEqualTo"].maximum, isNull);
      expect(schema.properties["greaterThanEqualTo"].exclusiveMaximum, isNull);
      expect(schema.properties["greaterThanEqualTo"].minimum, 1);
      expect(schema.properties["greaterThanEqualTo"].exclusiveMinimum, false);
    });

    test("Schema object contains range if range validator", () {
      expect(schema.properties["range"].maximum, 5);
      expect(schema.properties["range"].exclusiveMaximum, true);
      expect(schema.properties["range"].minimum, 1);
      expect(schema.properties["range"].exclusiveMinimum, false);
    });

    test("Schema object has equal max/min length if equals length validator",
        () {
      expect(schema.properties["lengthEqualTo"].maxLength, 20);
      expect(schema.properties["lengthEqualTo"].minLength, 20);
    });

    test("Schema object has diff max/min length if range length validator", () {
      expect(schema.properties["lengthRange"].maxLength, 19);
      expect(schema.properties["lengthRange"].minLength, 10);
    });

    test("Schema object has enum if Validate.oneOf", () {
      expect(schema.properties["oneOf"].enumerated, ["1", "2"]);
    });

    test("Compare matcher on non-num type isn't emitted", () {
      expect(schema.properties["nonNumCompare"].exclusiveMinimum, isNull);
      expect(schema.properties["nonNumCompare"].minimum, isNull);
      expect(schema.properties["nonNumCompare"].exclusiveMaximum, isNull);
      expect(schema.properties["nonNumCompare"].maximum, isNull);
    });
  });

  group("Comment Documentation", () {
    APISchemaObject schema;

    setUpAll(() {
      schema = doc.components.schemas["Model1"];
    });

    test("Entity itself has docs pre-prended with comments", () {
      expect(schema.title, "title");
      expect(schema.description, contains("description"));
      expect(schema.description,
          contains("No two objects may have the same value for all of"));
    });

    test("Entity has notes even if it doesn't have comments", () {
      expect(doc.components.schemas["Model3"].title, "Model3");
      expect(doc.components.schemas["Model3"].description,
          "\nNo two objects may have the same value for all of: 'matches', 'lessThan'.");
    });

    test(
        "Title and description contain docs, even if no docs added by auto-generated docs",
        () {
      expect(schema.properties["getter"].title, "title");
      expect(schema.properties["getter"].description, "description");
    });

    test(
        "Title and description are pre-pended to docs auto-generate for property",
        () {
      expect(schema.properties["string"].title, "title");
      expect(schema.properties["string"].description, contains("description"));
      expect(schema.properties["string"].description,
          contains("No two objects may have the same value for this field."));
    });

    test("Description contains 'unique identifier' for primary key", () {
      expect(schema.properties["id"].description,
          contains("This is the primary identifier for this object."));
    });

    test("Description contains note if has unique constraint", () {
      expect(schema.properties["string"].description,
          contains("No two objects may have the same value for this field."));
    });

    test("No autogenerated doc comments yields null for property description",
        () {
      expect(schema.properties["dateTime"].title, "");
      expect(schema.properties["dateTime"].description, "");
    });

    test("Relationship can have doc comments", () {
      expect(schema.properties["model2s"].title, "title");
      expect(schema.properties["model2s"].description, contains("description"));
    });
  });
}

/// title
///
/// description
class Model1 extends ManagedObject<_Model1> implements _Model1 {
  /// title
  ///
  /// description
  @Serialize()
  String get getter => null;

  @Serialize()
  set setter(int s) {}

  @Serialize()
  DateTime field;
}

@Table(uniquePropertySet: [Symbol('string'), Symbol('dateTime')])
class _Model1 {
  @primaryKey
  int id;

  /// title
  ///
  /// description
  @Column(unique: true)
  String string;

  DateTime dateTime;

  @Column(defaultValue: 'true')
  bool boolean;

  /// title
  ///
  /// description
  ManagedSet<Model2> model2s;
  Model3 model3;
}

class Model2 extends ManagedObject<_Model2> implements _Model2 {}

class _Model2 {
  @primaryKey
  int id;

  @Relate(Symbol('model2s'))
  Model1 model1;
}

class Model3 extends ManagedObject<_Model3> implements _Model3 {}

@Table(uniquePropertySet: [Symbol('matches'), Symbol('lessThan')])
class _Model3 {
  @primaryKey
  int id;

  @Column(omitByDefault: true)
  String notIncluded;

  @CustomValidate()
  String customValidate;

  @Validate.matches("xb")
  String matches;

  @Validate.compare(lessThan: 1)
  int lessThan;

  @Validate.compare(lessThanEqualTo: 1)
  int lessThanEqualTo;

  @Validate.compare(greaterThan: 1)
  int greaterThan;

  @Validate.compare(greaterThanEqualTo: 1)
  int greaterThanEqualTo;

  @Validate.compare(greaterThanEqualTo: 1, lessThan: 5)
  int range;

  @Validate.length(equalTo: 20)
  String lengthEqualTo;

  @Validate.length(lessThan: 20, greaterThanEqualTo: 10)
  String lengthRange;

  @Validate.oneOf(["1", "2"])
  String oneOf;

  @Validate.compare(greaterThan: "hello")
  String nonNumCompare;

  @Relate(Symbol('model3'))
  Model1 model1;
}

class CustomValidate extends Validate {
  const CustomValidate();

  @override
  void validate(ValidationContext context, dynamic input) {
    context.addError("any");
  }

  @override
  void constrainSchemaObject(
      APIDocumentContext context, APISchemaObject object) {
    object.maxProperties = 2;
  }
}
