import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import '../../helpers.dart';

void main() {
  group("ToOne graph", () {
    ModelContext context = null;

    setUpAll(() async {
      context = await contextWithModels([Child, Parent, Toy]);

      var o = ["A", "B", "C"];
      var owners = await Future.wait(o.map((x) {
        var q = new Query<Parent>()
          ..values.name = x;
        return q.insert();
      }));

      for (var o in owners) {
        if (o.name != "C") {
          var q = new Query<Child>()
            ..values.name = "${o.name}1"
            ..values.parent = (new Parent()
              ..id = o.id);
          await q.insert();
        }
      }
    });

    tearDownAll(() {
      context?.persistentStore?.close();
    });

    test("Join with single root object", () async {
      var q = new Query<Parent>()
          ..matchOn.id = 1
          ..include.child = whereExists;
      var o = (await q.fetch()).first.asMap();

      expect(o, {
        "id" : 1,
        "name" : "A",
        "child" : {
          "id" : 1,
          "name" : "A1",
          "parent" : {"id" : 1}
        }
      });
    });

    test("Join with null value still has key", () async {
      var q = new Query<Parent>()
        ..matchOn.id = 3
        ..include.child = whereExists;
      var o = (await q.fetch()).first.asMap();

      expect(o, {
        "id" : 3,
        "name" : "C",
        "child" : null
      });
    });

    test("Join with multi root object", () async {
      var q = new Query<Parent>()
        ..include.child = whereExists;
      var o = await q.fetch();

      var mapList = o.map((x) => x.asMap()).toList();
      expect(mapList, [
        {
          "id" : 1, "name" : "A", "child" : {
            "id" : 1,
            "name" : "A1",
            "parent" : {"id" : 1}
          }
        },
        {
          "id" : 2, "name" : "B", "child" : {
            "id" : 2,
            "name" : "B1",
            "parent" : {"id" : 2}
          }
        },
        {
          "id" : 3, "name" : "C", "child" : null
        }
      ]);
    });

    test("Multi-level join", () async {
      var q = new Query<Parent>()
        ..include.child.include.toy.matchOn.id = 1;

      var o = await q.fetch();

      print("${o.first.asMap()}");
    });
  });
}


class Parent extends Model<_Parent> implements _Parent {}
class _Parent {
  @primaryKey
  int id;
  String name;

  @Relationship.hasOne("parent")
  Child child;
}

class Child extends Model<_Child> implements _Child {}
class _Child {
  @primaryKey
  int id;
  String name;

  @Relationship.belongsTo("child")
  Parent parent;

  @Relationship.hasOne("child")
  Toy toy;
}

class Toy extends Model<_Toy> implements _Toy {}
class _Toy {
  @primaryKey
  int id;

  String name;

  @Relationship.belongsTo("toy")
  Child child;
}