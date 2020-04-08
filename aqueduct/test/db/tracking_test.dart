import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  ManagedContext context;
  setUp(() async {
    context = await contextWithModels([Parent, Child, Grandchild]);
  });

  tearDown(() async {
    await context?.close();
    context = null;
  });

  group("Attribute identification", () {
    test("Identify top-level", () {
      expect(
          context
              .entityForType(Parent)
              .identifyAttribute((Parent x) => x.field)
              .name,
          "field");
    });

    test("Cannot select relationship", () {
      try {
        context.entityForType(Child).identifyAttribute((Child p) => p.parent);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("cannot be selected"));
      }
    });

    test("Cannot nest attribute selection", () {
      try {
        context
            .entityForType(Child)
            .identifyAttribute((Child p) => p.parent.field);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Cannot use relationships"));
      }
    });

    test("cannot select multiple attributes", () {
      try {
        context.entityForType(Child).identifyAttribute((Child p) {
          // ignore: unnecessary_statements
          p.document;
          return p.field;
        });
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(
            e.toString(),
            contains(
                "Cannot access more than one property for this operation"));
      }
    });

    test("Can select document directly", () {
      expect(
          context
              .entityForType(Parent)
              .identifyAttribute((Parent x) => x.document)
              .name,
          "document");
    });

    test("Cannot select sub-document", () {
      try {
        context
            .entityForType(Child)
            .identifyAttribute((Child p) => p.document["foo"]);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(),
            contains("Cannot access subdocuments for this operation"));
      }
    });
  });

  group("Relationship identification", () {
    test("Identify top-level relationship", () {
      expect(
          context
              .entityForType(Parent)
              .identifyRelationship((Parent x) => x.children)
              .name,
          "children");
    });

    test("Identify top-level relationship to-one", () {
      expect(
          context
              .entityForType(Child)
              .identifyRelationship((Child x) => x.parent)
              .name,
          "parent");
    });

    test("Cannot select attribute", () {
      try {
        context
            .entityForType(Parent)
            .identifyRelationship((Parent p) => p.document);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Invalid property selection"));
      }
    });

    test("Cannot nest attribute selection", () {
      try {
        context
            .entityForType(Grandchild)
            .identifyRelationship((Grandchild p) => p.parent.parent);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Cannot identify a nested relationship"));
      }
    });

    test("cannot select multiple attributes", () {
      try {
        context.entityForType(Child).identifyRelationship((Child p) {
          // ignore: unnecessary_statements
          p.parent;
          return p.grandchild;
        });
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(
            e.toString(),
            contains(
                "Cannot access more than one property for this operation"));
      }
    });
  });

  group("KeyPath identification", () {
    test("Identify multiple properties", () {
      final props = context
          .entityForType(Parent)
          .identifyProperties((Parent x) => [x.document, x.field, x.children]);
      expect(props.length, 3);
      expect(props.any((k) => k.path.first.name == "document"), true);
      expect(props.any((k) => k.path.first.name == "field"), true);
      expect(props.any((k) => k.path.first.name == "children"), true);
    });

    test("Identify top-level property with subdoc", () {
      final props = context
          .entityForType(Parent)
          .identifyProperties((Parent x) => [x.document["k"]]);
      expect(props.length, 1);
      expect(props.first.path.length, 1);
      expect(props.first.path.first.name, "document");
      expect(props.first.dynamicElements, ["k"]);
    });

    test("Identify top-level property with subdoc", () {
      final props = context
          .entityForType(Parent)
          .identifyProperties((Parent x) => [x.document["k"][1]]);
      expect(props.length, 1);
      expect(props.first.path.length, 1);
      expect(props.first.path.first.name, "document");
      expect(props.first.dynamicElements, ["k", 1]);
    });

    test("Subdoc + normal property", () {
      final props = context
          .entityForType(Parent)
          .identifyProperties((Parent x) => [x.document["k"][1], x.field]);
      expect(props.length, 2);

      expect(props.first.path.length, 1);
      expect(props.first.path.first.name, "document");
      expect(props.first.dynamicElements, ["k", 1]);

      expect(props.last.path.length, 1);
      expect(props.last.path.first.name, "field");
      expect(props.last.dynamicElements, isNull);
    });

    test("Can select nested properties", () {
      final props = context
          .entityForType(Child)
          .identifyProperties((Child x) => [x.parent.field]);
      expect(props.length, 1);
      expect(props.first.path.length, 2);
      expect(props.first.path.first.name, "parent");
      expect(props.first.path.first.entity.tableName, "_Child");
      expect(props.first.path.last.name, "field");
      expect(props.first.path.last.entity.tableName, "_Parent");
    });
  });
}

class Parent extends ManagedObject<_Parent> implements _Parent {}

class _Parent {
  @primaryKey
  int id;

  String field;

  Document document;

  ManagedSet<Child> children;
}

class Child extends ManagedObject<_Child> implements _Child {}

class _Child {
  @primaryKey
  int id;

  String field;

  Document document;

  @Relate(Symbol('children'))
  Parent parent;

  Grandchild grandchild;
}

class Grandchild extends ManagedObject<_Grandchild> implements _Grandchild {}

class _Grandchild {
  @primaryKey
  int id;

  String field;

  Document document;

  @Relate(Symbol('grandchild'))
  Child parent;
}
