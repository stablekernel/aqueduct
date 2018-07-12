import 'dart:async';
import 'package:aqueduct/aqueduct.dart';

class RootObject extends ManagedObject<_RootObject> implements _RootObject {
  static int counter = 1;
  RootObject();
  RootObject.withCounter() {
    this.value1 = counter;
    this.value2 = counter;
    counter++;
  }

  @override
  bool operator ==(dynamic other) {
    return rid == other.cid;
  }

  @override
  int get hashCode => rid;
}

class _RootObject {
  @primaryKey
  int rid;

  int value1;
  int value2;

  ManagedSet<ChildObject> children;
  ChildObject child;

  ManagedSet<RootJoinObject> join;
}

class ChildObject extends ManagedObject<_ChildObject> implements _ChildObject {
  static int counter = 1;
  ChildObject();
  ChildObject.withCounter() {
    this.value1 = counter;
    this.value2 = counter;
    counter++;
  }

  @override
  bool operator ==(dynamic other) {
    return cid == other.cid;
  }

  @override
  int get hashCode => cid;
}

class _ChildObject {
  @primaryKey
  int cid;

  int value1;
  int value2;

  ManagedSet<GrandChildObject> grandChildren;
  GrandChildObject grandChild;

  @Relate(Symbol('children'))
  RootObject parents;

  @Relate(Symbol('child'))
  RootObject parent;
}

class GrandChildObject extends ManagedObject<_GrandChildObject>
    implements _GrandChildObject {
  static int counter = 1;
  GrandChildObject();
  GrandChildObject.withCounter() {
    this.value1 = counter;
    this.value2 = counter;
    counter++;
  }

  @override
  bool operator ==(dynamic other) {
    return gid == other.cid;
  }

  @override
  int get hashCode => gid;
}

class _GrandChildObject {
  @primaryKey
  int gid;

  int value1;
  int value2;

  @Relate(Symbol('grandChildren'))
  ChildObject parents;

  @Relate(Symbol('grandChild'))
  ChildObject parent;
}

class OtherRootObject extends ManagedObject<_OtherRootObject>
    implements _OtherRootObject {
  static int counter = 1;
  OtherRootObject();
  OtherRootObject.withCounter() {
    this.value1 = counter;
    this.value2 = counter;
    counter++;
  }

  @override
  bool operator ==(dynamic other) {
    return id == other.cid;
  }

  @override
  int get hashCode => id;
}

class _OtherRootObject {
  @primaryKey
  int id;

  int value1;
  int value2;

  ManagedSet<RootJoinObject> join;
}

class RootJoinObject extends ManagedObject<_RootJoinObject>
    implements _RootJoinObject {
  @override
  bool operator ==(dynamic other) {
    return id == other.cid;
  }

  @override
  int get hashCode => id;
}

class _RootJoinObject {
  @primaryKey
  int id;

  @Relate(Symbol('join'))
  OtherRootObject other;

  @Relate(Symbol('join'))
  RootObject root;
}

/*
[
  {"id": 1, "value1": 1, "value2": 1,
    "join": [{
        other: {"id": 1, "value1": 1, "value2": 1}
      }, {
        other: {"id": 2, "value1": 2, "value2": 2}
      }],
    child: {"id": 1, "value1": 1, "value2": 1,
      "grandChild": {"id": 1, "value1": 1, "value2": 1},
      "grandChildren": [
        {"id": 2, "value1": 2, "value2": 2}, {"id": 3, "value1": 3, "value2": 3}
      ]},
    "children": [
      {"id": 2, "value1": 2, "value2": 2,
        "grandChild": {"id": 4, "value1": 4, "value2": 4},
        "grandChildren": [
          {"id": 5, "value1": 5, "value2": 5}, {"id": 6, "value1": 6, "value2": 6}
      ]},
      {"id": 3, "value1": 3, "value2": 3,
        "grandChild": {"id": 7, "value1": 7, "value2": 7}
      },
      {"id": 4, "value1": 4, "value2": 4,
        "grandChildren": [{"id": 8, "value1": 8, "value2": 8}]},
      {"id": 5, "value1": 5, "value2": 5}
    ]},
  {"id": 2, "value1": 2, "value2": 2,
    "join": [{
      other: {"id": 3, "value1": 3, "value2": 3}
    }],
    child: {"id": 6, "value1": 6, "value2": 6},
    "children": [{"id": 7, "value1": 7, "value2": 7}]},
  {"id": 3, "value1": 3, "value2": 3,
    child: {"id": 8, "value1": 8, "value2": 8}},
  {"id": 4, "value1": 4, "value2": 4,
    "children": [{"id": 9, "value1": 9, "value2": 9}]},
  {"id": 5, "value1": 5, "value2": 5}
]
 */

Future<List<RootObject>> populateModelGraph(ManagedContext ctx) async {
  var rootObjects = <RootObject>[
    new RootObject.withCounter() // 1
      ..join = new ManagedSet.from([
        new RootJoinObject() // 1
          ..other = new OtherRootObject.withCounter(), // 1
        new RootJoinObject() // 2
          ..other = new OtherRootObject.withCounter() // 2
      ])
      ..child = (new ChildObject.withCounter() // 1
        ..grandChild = new GrandChildObject.withCounter() // 1
        ..grandChildren = new ManagedSet.from([
          new GrandChildObject.withCounter(), // 2
          new GrandChildObject.withCounter() // 3
        ]))
      ..children = new ManagedSet.from([
        (new ChildObject.withCounter() // 2
          ..grandChild = new GrandChildObject.withCounter() // 4
          ..grandChildren = new ManagedSet.from([
            new GrandChildObject.withCounter(), // 5
            new GrandChildObject.withCounter() // 6
          ])),
        (new ChildObject.withCounter() // 3
              ..grandChild = new GrandChildObject.withCounter() // 7
            ),
        (new ChildObject.withCounter() // 4
          ..grandChildren = new ManagedSet.from([
            new GrandChildObject.withCounter() // 8
          ])),
        new ChildObject.withCounter() // 5
      ]),
    new RootObject.withCounter() // 2
      ..join = new ManagedSet.from([
        new RootJoinObject() // 3
          ..other = new OtherRootObject.withCounter(), // 3
      ])
      ..child = new ChildObject.withCounter() // 6
      ..children = new ManagedSet.from([
        new ChildObject.withCounter() // 7
      ]),
    new RootObject.withCounter() // 3
      ..child = new ChildObject.withCounter(), // 8
    new RootObject.withCounter() // 4
      ..children = new ManagedSet.from([
        new ChildObject.withCounter() // 9
      ]),
    new RootObject.withCounter() // 5
  ];

  for (var root in rootObjects) {
    var q = new Query<RootObject>(ctx)..values = root;
    var r = await q.insert();
    root.rid = r.rid;

    if (root.child != null) {
      var child = root.child;
      child.parent = root;
      var cQ = new Query<ChildObject>(ctx)..values = child;
      child.cid = (await cQ.insert()).cid;

      if (child.grandChild != null) {
        var gc = child.grandChild;
        gc.parent = child;
        var gq = new Query<GrandChildObject>(ctx)..values = gc;
        gc.gid = (await gq.insert()).gid;
      }

      if (child?.grandChildren != null) {
        for (var gc in child.grandChildren) {
          gc.parents = child;
          var gq = new Query<GrandChildObject>(ctx)..values = gc;
          gc.gid = (await gq.insert()).gid;
        }
      }
    }

    if (root.children != null) {
      for (var child in root.children) {
        child.parents = root;
        var cQ = new Query<ChildObject>(ctx)..values = child;
        child.cid = (await cQ.insert()).cid;

        if (child.grandChild != null) {
          var gc = child.grandChild;
          gc.parent = child;
          var gq = new Query<GrandChildObject>(ctx)..values = gc;
          gc.gid = (await gq.insert()).gid;
        }

        if (child?.grandChildren != null) {
          for (var gc in child.grandChildren) {
            gc.parents = child;
            var gq = new Query<GrandChildObject>(ctx)..values = gc;
            gc.gid = (await gq.insert()).gid;
          }
        }
      }
    }

    if (root.join != null) {
      for (var join in root.join) {
        var otherQ = new Query<OtherRootObject>(ctx)..values = join.other;
        join.other.id = (await otherQ.insert()).id;

        join.root = new RootObject()..rid = root.rid;

        var joinQ = new Query<RootJoinObject>(ctx)..values = join;
        await joinQ.insert();
      }
    }
  }

  return rootObjects;
}

Map fullObjectMap(Type t, dynamic v, {Map<String, dynamic> and}) {
  var idName = "id";
  if (t == RootObject) {
    idName = "rid";
  } else if (t == ChildObject) {
    idName = "cid";
  } else if (t == GrandChildObject) {
    idName = "gid";
  }
  var m = {idName: v, "value1": v, "value2": v};
  if (and != null) {
    m.addAll(and);
  }
  return m;
}
