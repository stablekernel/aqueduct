import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  ManagedContext context;

  tearDown(() async {
    await context?.close();
    context = null;
  });

  group("Self-reference", () {
    setUp(() async {
      context = await contextWithModels([SelfRef]);
    });

    test("Insert an object that references an existing object", () async {
      final parent =
          await Query.insertObject(context, SelfRef()..name = "parent");

      var q = Query<SelfRef>(context)
        ..values.name = "child"
        ..values.parent = parent;
      final child = await q.insert();

      expect(parent.name, "parent");
      expect(child.name, "child");
      expect(child.parent.id, parent.id);

      q = Query<SelfRef>(context);
      final all = await q.fetch();
      expect(all.length, 2);
    });

    test("Update an object to reference itself", () async {
      final parent =
          await Query.insertObject(context, SelfRef()..name = "self");

      var q = Query<SelfRef>(context)
        ..where((s) => s.id).equalTo(parent.id)
        ..values.parent = parent;
      await q.updateOne();

      q = Query<SelfRef>(context);
      final all = await q.fetch();
      expect(all.map((s) => s.asMap()).toList(), [
        {
          "id": parent.id,
          "name": "self",
          "parent": {"id": parent.id}
        }
      ]);
    });

    test("Join from table without foreign key", () async {
      var q = Query<SelfRef>(context)..values.name = "parent";
      final parent = await q.insert();

      await Query.insertObjects(
          context,
          ["a", "b", "c"].map((n) {
            return SelfRef()
              ..name = n
              ..parent = parent;
          }).toList());

      q = Query<SelfRef>(context)
        ..where((s) => s.id).equalTo(parent.id)
        ..join(set: (s) => s.children)
            .sortBy((s) => s.name, QuerySortOrder.ascending);
      final all = await q.fetch();
      expect(all.map((s) => s.asMap()).toList(), [
        {
          "id": parent.id,
          "name": "parent",
          "parent": null,
          "children": [
            {
              "id": isNotNull,
              "name": "a",
              "parent": {"id": parent.id}
            },
            {
              "id": isNotNull,
              "name": "b",
              "parent": {"id": parent.id}
            },
            {
              "id": isNotNull,
              "name": "c",
              "parent": {"id": parent.id}
            },
          ]
        }
      ]);
    });

    test("Join from table with foreign key", () async {
      var q = Query<SelfRef>(context)..values.name = "parent";
      final parent = await q.insert();

      final objs = await Query.insertObjects(
          context,
          ["a", "b", "c"].map((n) {
            return SelfRef()
              ..name = n
              ..parent = parent;
          }).toList());

      q = Query<SelfRef>(context)
        ..where((s) => s.id).equalTo(objs.first.id)
        ..join(object: (s) => s.parent);
      final all = await q.fetch();
      expect(all.map((s) => s.asMap()).toList(), [
        {
          "id": objs.first.id,
          "name": "a",
          "parent": {"id": parent.id, "name": "parent", "parent": null},
        }
      ]);
    });

    test("Join multiple times", () async {
      var q = Query<SelfRef>(context)..values.name = "parent";
      final parent = await q.insert();

      final objs = await Query.insertObjects(
          context,
          ["a", "b", "c"].map((n) {
            return SelfRef()
              ..name = n
              ..parent = parent;
          }).toList());

      await Query.insertObject(
          context,
          SelfRef()
            ..name = "x"
            ..parent = objs.first);

      q = Query<SelfRef>(context)
        ..sortBy((s) => s.name, QuerySortOrder.ascending);
      final inner = q.join(set: (s) => s.children)
        ..sortBy((s) => s.name, QuerySortOrder.ascending);
      inner.join(set: (s) => s.children);

      final all = await q.fetch();
      expect(all.map((s) => s.asMap()).toList(), [
        {
          "id": isNotNull,
          "name": "a",
          "parent": {"id": parent.id},
          "children": [
            {
              "id": isNotNull,
              "name": "x",
              "parent": {"id": isNotNull},
              "children": []
            }
          ]
        },
        {
          "id": isNotNull,
          "name": "b",
          "parent": {"id": parent.id},
          "children": []
        },
        {
          "id": isNotNull,
          "name": "c",
          "parent": {"id": parent.id},
          "children": []
        },
        {
          "id": parent.id,
          "name": "parent",
          "parent": null,
          "children": [
            {
              "id": isNotNull,
              "name": "a",
              "parent": {"id": parent.id},
              "children": [
                {"id": isNotNull, "name": "x", "parent": isNotNull}
              ]
            },
            {
              "id": isNotNull,
              "name": "b",
              "parent": {"id": parent.id},
              "children": []
            },
            {
              "id": isNotNull,
              "name": "c",
              "parent": {"id": parent.id},
              "children": []
            },
          ]
        },
        {
          "id": isNotNull,
          "name": "x",
          "parent": {"id": isNotNull},
          "children": []
        }
      ]);
    });

    test("Join with a where clause on the primary table", () async {
      var q = Query<SelfRef>(context)..values.name = "parent";
      final parent = await q.insert();

      final objs = await Query.insertObjects(
          context,
          ["a", "b", "c"].map((n) {
            return SelfRef()
              ..name = n
              ..parent = parent;
          }).toList());

      await Query.insertObject(
          context,
          SelfRef()
            ..name = "x"
            ..parent = objs.first);

      q = Query<SelfRef>(context)..where((s) => s.id).equalTo(parent.id);
      q
          .join(set: (s) => s.children)
          .sortBy((s) => s.name, QuerySortOrder.ascending);

      final all = await q.fetch();
      expect(all.map((s) => s.asMap()).toList(), [
        {
          "id": parent.id,
          "name": "parent",
          "parent": null,
          "children": [
            {
              "id": isNotNull,
              "name": "a",
              "parent": {"id": parent.id},
            },
            {
              "id": isNotNull,
              "name": "b",
              "parent": {"id": parent.id},
            },
            {
              "id": isNotNull,
              "name": "c",
              "parent": {"id": parent.id},
            },
          ]
        }
      ]);
    });

    test("Join with a where clause on the joined table", () async {
      var q = Query<SelfRef>(context)..values.name = "parent";
      final parent = await q.insert();

      final objs = await Query.insertObjects(
          context,
          ["a", "b", "c"].map((n) {
            return SelfRef()
              ..name = n
              ..parent = parent;
          }).toList());

      await Query.insertObject(
          context,
          SelfRef()
            ..name = "x"
            ..parent = objs.first);

      q = Query<SelfRef>(context)
        ..sortBy((s) => s.name, QuerySortOrder.ascending);
      q.join(set: (s) => s.children).where((s) => s.name).greaterThan("b");

      final all = await q.fetch();
      expect(all.map((s) => s.asMap()).toList(), [
        {
          'id': 2,
          'name': 'a',
          'parent': {'id': 1},
          'children': [
            {
              'id': 5,
              'name': 'x',
              'parent': {'id': 2}
            }
          ]
        },
        {
          'id': 3,
          'name': 'b',
          'parent': {'id': 1},
          'children': []
        },
        {
          'id': 4,
          'name': 'c',
          'parent': {'id': 1},
          'children': []
        },
        {
          'id': 1,
          'name': 'parent',
          'parent': null,
          'children': [
            {
              'id': 4,
              'name': 'c',
              'parent': {'id': 1}
            }
          ]
        },
        {
          'id': 5,
          'name': 'x',
          'parent': {'id': 2},
          'children': []
        },
      ]);
    });

    test("Join with where clause on both the primary and joined table",
        () async {
      var q = Query<SelfRef>(context)..values.name = "parent";
      final parent = await q.insert();

      final objs = await Query.insertObjects(
          context,
          ["a", "b", "c"].map((n) {
            return SelfRef()
              ..name = n
              ..parent = parent;
          }).toList());

      await Query.insertObject(
          context,
          SelfRef()
            ..name = "x"
            ..parent = objs.first);

      q = Query<SelfRef>(context)..where((s) => s.name).greaterThan("o");
      q.join(set: (s) => s.children).where((s) => s.name).greaterThan("b");

      final all = await q.fetch();
      expect(all.map((s) => s.asMap()).toList(), [
        {
          'id': 1,
          'name': 'parent',
          'parent': null,
          'children': [
            {
              'id': 4,
              'name': 'c',
              'parent': {'id': 1}
            }
          ]
        },
        {
          "id": 5,
          "name": "x",
          "parent": {"id": 2},
          "children": []
        }
      ]);
    });
  });

  group("Reference to one another", () {
    setUp(() async {
      context = await contextWithModels([Left, Right]);
    });

    test("Insert an object that references an existing object", () async {
      final l = await Query.insertObject(context, Left()..name = "l1");

      var q = Query<Right>(context)
        ..values.name = "r1"
        ..values.belongsToLeft = l;
      final r = await q.insert();

      expect(l.name, "l1");
      expect(r.name, "r1");
      expect(r.belongsToLeft.id, l.id);
    });

    test("Updating and joining across tables", () async {
      final r1 = await Query.insertObject(context, Right()..name = "r1");
      final l1 = await Query.insertObject(
          context,
          Left()
            ..name = "l1"
            ..belongsToRight = r1);
      final updateQuery = Query<Right>(context)
        ..where((r) => r.id).equalTo(r1.id)
        ..values.belongsToLeft = l1;
      await updateQuery.updateOne();

      final q = Query<Left>(context)
        ..join(object: (l) => l.right).join(object: (r) => r.left);
      final all = await q.fetch();
      expect(all.map((s) => s.asMap()).toList(), [
        {
          "id": l1.id,
          "name": "l1",
          "belongsToRight": {"id": r1.id},
          "right": {
            "id": r1.id,
            "name": "r1",
            "left": {
              "id": l1.id,
              "name": "l1",
              "belongsToRight": {"id": r1.id},
            },
            "belongsToLeft": {"id": r1.id}
          }
        }
      ]);
    });
//
//    test("Join from table without foreign key", () async {
//      var q = Query<SelfRef>(context)..values.name = "Parent";
//      final parent = await q.insert();
//
//      await Query.insertObjects(
//        context,
//        ["a", "b", "c"].map((n) {
//          return SelfRef()
//            ..name = n
//            ..parent = parent;
//        }).toList());
//
//      q = Query<SelfRef>(context)
//        ..where((s) => s.id).equalTo(parent.id)
//        ..join(set: (s) => s.children)
//          .sortBy((s) => s.name, QuerySortOrder.ascending);
//      final all = await q.fetch();
//      expect(all.map((s) => s.asMap()).toList(), [
//        {
//          "id": parent.id,
//          "name": "Parent",
//          "parent": null,
//          "children": [
//            {
//              "id": isNotNull,
//              "name": "a",
//              "parent": {"id": parent.id}
//            },
//            {
//              "id": isNotNull,
//              "name": "b",
//              "parent": {"id": parent.id}
//            },
//            {
//              "id": isNotNull,
//              "name": "c",
//              "parent": {"id": parent.id}
//            },
//          ]
//        }
//      ]);
//    });
//
//    test("Join from table with foreign key", () async {
//      var q = Query<SelfRef>(context)..values.name = "Parent";
//      final parent = await q.insert();
//
//      final objs = await Query.insertObjects(
//        context,
//        ["a", "b", "c"].map((n) {
//          return SelfRef()
//            ..name = n
//            ..parent = parent;
//        }).toList());
//
//      q = Query<SelfRef>(context)
//        ..where((s) => s.id).equalTo(objs.first.id)
//        ..join(object: (s) => s.parent);
//      final all = await q.fetch();
//      expect(all.map((s) => s.asMap()).toList(), [
//        {
//          "id": objs.first.id,
//          "name": "a",
//          "parent": {"id": parent.id, "name": "Parent", "parent": null},
//        }
//      ]);
//    });
//
//    test("Join multiple times", () async {
//      var q = Query<SelfRef>(context)..values.name = "Parent";
//      final parent = await q.insert();
//
//      final objs = await Query.insertObjects(
//        context,
//        ["a", "b", "c"].map((n) {
//          return SelfRef()
//            ..name = n
//            ..parent = parent;
//        }).toList());
//
//      await Query.insertObject(
//        context,
//        SelfRef()
//          ..name = "x"
//          ..parent = objs.first);
//
//      q = Query<SelfRef>(context)
//        ..sortBy((s) => s.name, QuerySortOrder.ascending);
//      final inner = q.join(set: (s) => s.children)
//        ..sortBy((s) => s.name, QuerySortOrder.ascending);
//      inner.join(set: (s) => s.children);
//
//      final all = await q.fetch();
//      expect(all.map((s) => s.asMap()).toList(), [
//        {
//          "id": parent.id,
//          "name": "Parent",
//          "parent": null,
//          "children": [
//            {
//              "id": isNotNull,
//              "name": "a",
//              "parent": {"id": parent.id},
//              "children": [
//                {"id": isNotNull, "name": "x", "parent": isNotNull}
//              ]
//            },
//            {
//              "id": isNotNull,
//              "name": "b",
//              "parent": {"id": parent.id},
//              "children": []
//            },
//            {
//              "id": isNotNull,
//              "name": "c",
//              "parent": {"id": parent.id},
//              "children": []
//            },
//          ]
//        },
//        {
//          "id": isNotNull,
//          "name": "a",
//          "parent": {"id": parent.id},
//          "children": [
//            {
//              "id": isNotNull,
//              "name": "x",
//              "parent": {"id": isNotNull},
//              "children": []
//            }
//          ]
//        },
//        {
//          "id": isNotNull,
//          "name": "b",
//          "parent": {"id": parent.id},
//          "children": []
//        },
//        {
//          "id": isNotNull,
//          "name": "c",
//          "parent": {"id": parent.id},
//          "children": []
//        },
//        {
//          "id": isNotNull,
//          "name": "x",
//          "parent": {"id": isNotNull},
//          "children": []
//        }
//      ]);
//    });
//
//    test("Join with a where clause on the primary table", () async {
//      var q = Query<SelfRef>(context)..values.name = "Parent";
//      final parent = await q.insert();
//
//      final objs = await Query.insertObjects(
//        context,
//        ["a", "b", "c"].map((n) {
//          return SelfRef()
//            ..name = n
//            ..parent = parent;
//        }).toList());
//
//      await Query.insertObject(
//        context,
//        SelfRef()
//          ..name = "x"
//          ..parent = objs.first);
//
//      q = Query<SelfRef>(context)..where((s) => s.id).equalTo(parent.id);
//      q.join(set: (s) => s.children).sortBy((s) => s.name, QuerySortOrder.ascending);
//
//      final all = await q.fetch();
//      expect(all.map((s) => s.asMap()).toList(), [
//        {
//          "id": parent.id,
//          "name": "Parent",
//          "parent": null,
//          "children": [
//            {
//              "id": isNotNull,
//              "name": "a",
//              "parent": {"id": parent.id},
//            },
//            {
//              "id": isNotNull,
//              "name": "b",
//              "parent": {"id": parent.id},
//            },
//            {
//              "id": isNotNull,
//              "name": "c",
//              "parent": {"id": parent.id},
//            },
//          ]
//        }
//      ]);
//    });
//
//    test("Join with a where clause on the joined table", () async {
//      var q = Query<SelfRef>(context)..values.name = "Parent";
//      final parent = await q.insert();
//
//      final objs = await Query.insertObjects(
//        context,
//        ["a", "b", "c"].map((n) {
//          return SelfRef()
//            ..name = n
//            ..parent = parent;
//        }).toList());
//
//      await Query.insertObject(
//        context,
//        SelfRef()
//          ..name = "x"
//          ..parent = objs.first);
//
//      q = Query<SelfRef>(context);
//      q.join(set: (s) => s.children).where((s) => s.name).greaterThan("b");
//
//      final all = await q.fetch();
//      expect(all.map((s) => s.asMap()).toList(), [
//        {
//          'id': 1,
//          'name': 'Parent',
//          'parent': null,
//          'children': [{'id': 4, 'name': 'c', 'parent': {'id': 1}}]
//        },
//        {
//          'id': 2,
//          'name': 'a',
//          'parent': {'id': 1},
//          'children': [{'id': 5, 'name': 'x', 'parent': {'id': 2}}]
//        },
//        {'id': 5, 'name': 'x', 'parent': {'id': 2}, 'children': []},
//        {'id': 4, 'name': 'c', 'parent': {'id': 1}, 'children': []},
//        {'id': 3, 'name': 'b', 'parent': {'id': 1}, 'children': []}
//      ]);
//    });
//
//    test("Join with where clause on both the primary and joined table",
//        () async {
//        var q = Query<SelfRef>(context)..values.name = "Parent";
//        final parent = await q.insert();
//
//        final objs = await Query.insertObjects(
//          context,
//          ["a", "b", "c"].map((n) {
//            return SelfRef()
//              ..name = n
//              ..parent = parent;
//          }).toList());
//
//        await Query.insertObject(
//          context,
//          SelfRef()
//            ..name = "x"
//            ..parent = objs.first);
//
//        q = Query<SelfRef>(context)..where((s) => s.name).lessThan("a");
//        q.join(set: (s) => s.children).where((s) => s.name).greaterThan("b");
//
//        final all = await q.fetch();
//        expect(all.map((s) => s.asMap()).toList(), [
//          {
//            'id': 1,
//            'name': 'Parent',
//            'parent': null,
//            'children': [{'id': 4, 'name': 'c', 'parent': {'id': 1}}]
//          },
//        ]);
//      });
  });
}

class SelfRef extends ManagedObject<_SelfRef> implements _SelfRef {}

class _SelfRef {
  @primaryKey
  int id;

  String name;

  ManagedSet<SelfRef> children;

  @Relate(#children)
  SelfRef parent;
}

class Left extends ManagedObject<_Left> implements _Left {}

class _Left {
  @primaryKey
  int id;

  String name;

  Right right;

  @Relate(#left)
  Right belongsToRight;
}

class Right extends ManagedObject<_Right> implements _Right {}

class _Right {
  @primaryKey
  int id;

  String name;

  Left left;

  @Relate(#right)
  Left belongsToLeft;
}
