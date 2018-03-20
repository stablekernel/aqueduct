import 'dart:async';

import 'package:aqueduct/src/db/query/mixin.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../helpers.dart';

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
      final q = new BaseQuery<Parent>(context.entityForType(Parent));
      expect(q.identifyAttribute((x) => x.field).name, "field");
    });

    test("Cannot select relationship", () {
      try {
        new BaseQuery<Child>(context.entityForType(Child))
          ..identifyAttribute((p) => p.parent);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("cannot be selected"));
      }
    });

    test("Cannot nest attribute selection", () {
      try {
        new BaseQuery<Child>(context.entityForType(Child))
            ..identifyAttribute((p) => p.parent.field);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Cannot use relationships"));
      }
    });

    test("cannot select multiple attributes", () {
      try {
        new BaseQuery<Child>(context.entityForType(Child))
          ..identifyAttribute((p) {
            p.document;
            return p.field;
          });
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Cannot access more than one property for this operation"));
      }
    });

    test("Can select document directly", () {
      final q = new BaseQuery<Parent>(context.entityForType(Parent));
      expect(q.identifyAttribute((x) => x.document).name, "document");
    });

    test("Cannot select sub-document", () {
      try {
        new BaseQuery<Child>(context.entityForType(Child))
          ..identifyAttribute((p) => p.document["foo"]);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Cannot access subdocuments for this operation"));
      }
    });
  });

  group("Relationship identification", () {
    test("Identify top-level relationship", () {
      final q = new BaseQuery<Parent>(context.entityForType(Parent));
      expect(q.identifyRelationship((x) => x.children).name, "children");
    });

    test("Identify top-level relationship to-one", () {
      final q = new BaseQuery<Child>(context.entityForType(Child));
      expect(q.identifyRelationship((x) => x.parent).name, "parent");
    });

    test("Cannot select attribute", () {
      final q = new BaseQuery<Parent>(context.entityForType(Parent));
      try {
        q.identifyRelationship((p) => p.document);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Invalid property selection"));
      }
    });

    test("Cannot nest attribute selection", () {
      try {
        new BaseQuery<Grandchild>(context.entityForType(Grandchild))
          ..identifyRelationship((p) => p.parent.parent);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Cannot identify a nested relationship"));
      }
    });

    test("cannot select multiple attributes", () {
      try {
        new BaseQuery<Child>(context.entityForType(Child))
          ..identifyRelationship((p) {
            p.parent;
            return p.grandchild;
          });
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Cannot access more than one property for this operation"));
      }
    });
  });

  group("KeyPath identification", () {
    test("Identify multiple properties", () {
      final q = new BaseQuery<Parent>(context.entityForType(Parent));
      final props = q.identifyProperties((x) => [x.document, x.field, x.children]);
      expect(props.length, 3);
      expect(props.any((k) => k.path.first.name == "document"), true);
      expect(props.any((k) => k.path.first.name == "field"), true);
      expect(props.any((k) => k.path.first.name == "children"), true);
    });

    test("Identify top-level property with subdoc", () {
      final q = new BaseQuery<Parent>(context.entityForType(Parent));
      final props = q.identifyProperties((x) => [x.document["k"]]);
      expect(props.length, 1);
      expect(props.first.path.length, 1);
      expect(props.first.path.first.name, "document");
      expect(props.first.dynamicElements, ["k"]);
    });

    test("Identify top-level property with subdoc", () {
      final q = new BaseQuery<Parent>(context.entityForType(Parent));
      final props = q.identifyProperties((x) => [x.document["k"][1]]);
      expect(props.length, 1);
      expect(props.first.path.length, 1);
      expect(props.first.path.first.name, "document");
      expect(props.first.dynamicElements, ["k", 1]);
    });

    test("Subdoc + normal property", () {
      final q = new BaseQuery<Parent>(context.entityForType(Parent));
      final props = q.identifyProperties((x) => [x.document["k"][1], x.field]);
      expect(props.length, 2);

      expect(props.first.path.length, 1);
      expect(props.first.path.first.name, "document");
      expect(props.first.dynamicElements, ["k", 1]);

      expect(props.last.path.length, 1);
      expect(props.last.path.first.name, "field");
      expect(props.last.dynamicElements, isNull);
    });

    test("Cannot include relationship in returning properties", () {
      try {
        new BaseQuery<Parent>(context.entityForType(Parent))
          ..returningProperties((p) => [p.children]);
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("Cannot select has-many or has-one relationship properties")) ;
      }
    });

    test("Can select nested properties", () {
      final q = new BaseQuery<Child>(context.entityForType(Child));
      final props = q.identifyProperties((x) => [x.parent.field]);
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

  @Relate(#children)
  Parent parent;

  Grandchild grandchild;
}

class Grandchild extends ManagedObject<_Grandchild> implements _Grandchild {}
class _Grandchild {
  @primaryKey
  int id;

  String field;

  Document document;

  @Relate(#grandchild)
  Child parent;
}

class BaseQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {

  BaseQuery(this.entity);

  @override
  Future<List<InstanceType>> update() async {
    return [];
  }

  @override
  Future<List<InstanceType>> fetch() async {
    return null;
  }

  @override
  QueryReduceOperation<InstanceType> get reduce {
    return null;
  }

  @override
  ManagedEntity entity;

  @override
  Future<InstanceType> updateOne() {
    return null;
  }

  @override
  Future<InstanceType> insert() {
    return null;
  }

  @override
  Future<int> delete() {
    return null;
  }

  @override
  Future<InstanceType> fetchOne() {
    return null;
  }

  @override
  ManagedContext context;
}