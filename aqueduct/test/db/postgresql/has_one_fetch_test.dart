import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

/*
  The test data is like so:

     A                B                C         D
     |                |                |
    C1               C2                C3
   / | \              |
  T1 V1 V2            V3
 */

void main() {
  group("Happy path", () {
    ManagedContext context;
    List<Parent> truth;
    setUpAll(() async {
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      truth = await populate(context);
    });

    tearDownAll(() async {
      await context?.close();
    });

    test("Fetch has-one relationship that is null returns null for property",
        () async {
      var q = Query<Parent>(context)
        ..join(object: (p) => p.child)
        ..where((o) => o.name).equalTo("D");

      var verifier = (Parent p) {
        expect(p.name, "D");
        expect(p.pid, isNotNull);
        expect(p.backing.contents["child"], isNull);
        expect(p.backing.contents.containsKey("child"), true);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetch has-one relationship that is null returns null for property, and more nested has relationships are ignored",
        () async {
      var q = Query<Parent>(context)..where((o) => o.name).equalTo("D");

      q.join(object: (p) => p.child)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations);

      var verifier = (Parent p) {
        expect(p.name, "D");
        expect(p.pid, isNotNull);
        expect(p.backing.contents["child"], isNull);
        expect(p.backing.contents.containsKey("child"), true);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetch has-one relationship that is non-null returns value for property with scalar values only",
        () async {
      var q = Query<Parent>(context)
        ..join(object: (p) => p.child)
        ..where((o) => o.name).equalTo("C");

      var verifier = (Parent p) {
        expect(p.name, "C");
        expect(p.pid, isNotNull);
        expect(p.child.cid, isNotNull);
        expect(p.child.name, "C3");
        expect(p.child.backing.contents.containsKey("toy"), false);
        expect(p.child.backing.contents.containsKey("vaccinations"), false);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetch has-one relationship, include has-one and has-many in that has-one, where bottom of graph has valid object for hasmany but not for hasone",
        () async {
      var q = Query<Parent>(context)..where((o) => o.name).equalTo("B");

      q.join(object: (p) => p.child)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations);

      var verifier = (Parent p) {
        expect(p.name, "B");
        expect(p.pid, isNotNull);
        expect(p.child.cid, isNotNull);
        expect(p.child.name, "C2");
        expect(p.child.backing.contents.containsKey("toy"), true);
        expect(p.child.toy, isNull);
        expect(p.child.vaccinations.length, 1);
        expect(p.child.vaccinations.first.vid, isNotNull);
        expect(p.child.vaccinations.first.kind, "V3");
      };

      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetch has-one relationship, include has-one and has-many in that has-one, where bottom of graph is all null/empty",
        () async {
      var q = Query<Parent>(context)..where((o) => o.name).equalTo("C");

      q.join(object: (p) => p.child)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations);

      var verifier = (Parent p) {
        expect(p.name, "C");
        expect(p.pid, isNotNull);
        expect(p.child.cid, isNotNull);
        expect(p.child.name, "C3");
        expect(p.child.backing.contents.containsKey("toy"), true);
        expect(p.child.toy, isNull);
        expect(p.child.vaccinations, []);
      };

      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetching multiple top-level instances and including next-level hasOne",
        () async {
      var q = Query<Parent>(context)
        ..join(object: (p) => p.child)
        ..where((o) => o.name).oneOf(["C", "D"]);

      var results = await q.fetch();
      expect(results.first.pid, isNotNull);
      expect(results.first.name, "C");
      expect(results.first.child.name, "C3");

      expect(results.last.pid, isNotNull);
      expect(results.last.name, "D");
      expect(results.last.backing.contents.containsKey("child"), true);
      expect(results.last.child, isNull);
    });

    test("Fetch entire graph", () async {
      var q = Query<Parent>(context);
      q.join(object: (p) => p.child)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations);

      var all = await q.fetch();

      var originalIterator = truth.iterator;
      for (var p in all) {
        originalIterator.moveNext();
        expect(p.pid, originalIterator.current.pid);
        expect(p.name, originalIterator.current.name);
        expect(p.child?.cid, originalIterator.current.child?.cid);
        expect(p.child?.name, originalIterator.current.child?.name);
        expect(p.child?.toy?.tid, originalIterator.current.child?.toy?.tid);
        expect(p.child?.toy?.name, originalIterator.current.child?.toy?.name);

        var vacIter = originalIterator.current.child?.vaccinations?.iterator ??
            <Vaccine>[].iterator;
        p?.child?.vaccinations?.forEach((v) {
          vacIter.moveNext();
          expect(v.vid, vacIter.current.vid);
          expect(v.kind, vacIter.current.kind);
        });
        expect(vacIter.moveNext(), false);
      }
      expect(originalIterator.moveNext(), false);
    });
  });

  group("Happy path with predicates", () {
    ManagedContext context;

    setUpAll(() async {
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      await populate(context);
    });

    tearDownAll(() {
      context?.close();
    });

    test("Predicate impacts top-level objects when fetching object graph",
        () async {
      var q = Query<Parent>(context)..where((o) => o.name).equalTo("A");
      q.join(object: (p) => p.child)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations)
            .sortBy((v) => v.vid, QuerySortOrder.ascending);

      var results = await q.fetch();

      expect(results.length, 1);

      var p = results.first;
      expect(p.name, "A");
      expect(p.child.name, "C1");
      expect(p.child.toy.name, "T1");
      expect(p.child.vaccinations.first.kind, "V1");
      expect(p.child.vaccinations.last.kind, "V2");
    });

    test("Predicate impacts 2nd level objects when fetching object graph",
        () async {
      var q = Query<Parent>(context);
      q.join(object: (p) => p.child)
        ..where((o) => o.name).equalTo("C1")
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations)
            .sortBy((v) => v.vid, QuerySortOrder.ascending);

      var results = await q.fetch();

      expect(results.length, 4);

      var p = results.first;
      expect(p.name, "A");
      expect(p.child.name, "C1");
      expect(p.child.toy.name, "T1");
      expect(p.child.vaccinations.first.kind, "V1");
      expect(p.child.vaccinations.last.kind, "V2");

      for (var other in results.sublist(1)) {
        expect(other.child, isNull);
        expect(other.backing.contents.containsKey("child"), true);
      }
    });

    test("Predicate impacts 3rd level objects when fetching object graph",
        () async {
      var q = Query<Parent>(context);
      var childJoin = q.join(object: (p) => p.child)
        ..join(object: (c) => c.toy);
      childJoin
          .join(set: (c) => c.vaccinations)
          .where((o) => o.kind)
          .equalTo("V1");

      var results = await q.fetch();

      expect(results.length, 4);

      var p = results.first;
      expect(p.name, "A");
      expect(p.child.name, "C1");
      expect(p.child.toy.name, "T1");
      expect(p.child.vaccinations.first.kind, "V1");
      expect(p.child.vaccinations.length, 1);

      for (var other in results.sublist(1)) {
        expect(other.child?.vaccinations ?? [], []);
      }
    });

    test(
        "Predicate that omits top-level objects but would include lower level object return no results",
        () async {
      var q = Query<Parent>(context)..where((o) => o.pid).equalTo(5);

      var childJoin = q.join(object: (p) => p.child)
        ..join(object: (c) => c.toy);
      childJoin
          .join(set: (c) => c.vaccinations)
          .where((o) => o.kind)
          .equalTo("V1");
      var results = await q.fetch();
      expect(results.length, 0);
    });

    test(
        "Can use two 'where' criteria on the child object when not joining child object explicitly",
        () async {
      var q = Query<Parent>(context)
        ..where((o) => o.child.name).equalTo("C1")
        ..where((o) => o.child.cid).equalTo(1);
      final res1 = await q.fetchOne();
      expect(res1.pid, 1);
      expect(res1.backing.contents.containsKey("child"), false);

      var q2 = Query<Parent>(context)
        ..where((o) => o.child.name).equalTo("C1")
        ..where((o) => o.child.cid).equalTo(2);
      final res2 = await q2.fetch();
      expect(res2.length, 0);
    });
  });

  group("Result keys", () {
    ManagedContext context;

    setUpAll(() async {
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      await populate(context);
    });

    tearDownAll(() async {
      await context?.close();
    });

    test("Can fetch graph when omitting foreign or primary keys from query",
        () async {
      var q = Query<Parent>(context)..returningProperties((p) => [p.name]);

      var childQuery = q.join(object: (p) => p.child)
        ..returningProperties((c) => [c.name]);
      childQuery
          .join(set: (c) => c.vaccinations)
          .returningProperties((v) => [v.kind]);

      var parents = await q.fetch();
      for (var p in parents) {
        expect(p.name, isNotNull);
        expect(p.pid, isNotNull);
        expect(p.backing.contents.length, 3);

        if (p.child != null) {
          expect(p.child.name, isNotNull);
          expect(p.child.cid, isNotNull);
          expect(p.child.backing.contents.length, 3);

          for (var v in p.child.vaccinations) {
            expect(v.kind, isNotNull);
            expect(v.vid, isNotNull);
          }
        }
      }
    });

    test("Can specify result keys for all joined objects", () async {
      var q = Query<Parent>(context)..returningProperties((p) => [p.pid]);

      var childQuery = q.join(object: (p) => p.child)
        ..returningProperties((c) => [c.cid]);

      childQuery
          .join(set: (c) => c.vaccinations)
          .returningProperties((v) => [v.vid]);

      var parents = await q.fetch();
      for (var p in parents) {
        expect(p.pid, isNotNull);
        expect(p.backing.contents.length, 2);

        if (p.child != null) {
          expect(p.child.cid, isNotNull);
          expect(p.child.backing.contents.length, 2);

          for (var v in p.child.vaccinations) {
            expect(v.vid, isNotNull);
            expect(v.backing.contents.length, 1);
          }
        }
      }
    });
  });

  group("Offhand assumptions about data", () {
    ManagedContext context;

    setUpAll(() async {
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      await populate(context);
    });

    tearDownAll(() {
      context?.close();
    });

    test("Objects returned in join are not the same instance", () async {
      var q = Query<Parent>(context)
        ..where((o) => o.pid).equalTo(1)
        ..join(object: (p) => p.child);

      var o = await q.fetchOne();
      expect(identical(o.child.parent, o), false);
    });
  });

  group("Bad usage cases", () {
    ManagedContext context;

    setUpAll(() async {
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      await populate(context);
    });

    tearDownAll(() {
      context?.close();
    });

    test("Trying to fetch hasOne relationship through resultProperties fails",
        () async {
      try {
        Query<Parent>(context).returningProperties((p) => [p.pid, p.child]);
        expect(true, false);
      } on ArgumentError catch (e) {
        expect(
            e.toString(),
            contains(
                "Cannot select has-many or has-one relationship properties"));
      }

      try {
        var q = Query<Parent>(context);
        q
            .join(object: (p) => p.child)
            .returningProperties((c) => [c.cid, c.toy]);
        expect(true, false);
      } on ArgumentError catch (e) {
        expect(
            e.toString(),
            contains(
                "Cannot select has-many or has-one relationship properties"));
      }
    });

    test("Including paging on a join fails", () async {
      var q = Query<Parent>(context)
        ..join(object: (p) => p.child)
        ..pageBy((p) => p.pid, QuerySortOrder.ascending);

      try {
        await q.fetchOne();
        expect(true, false);
      } on StateError catch (e) {
        expect(
            e.toString(),
            contains(
                "Cannot set both 'pageDescription' and use 'join' in query"));
      }
    });
  });
}

class Parent extends ManagedObject<_Parent> implements _Parent {}

class _Parent {
  @primaryKey
  int pid;
  String name;

  Child child;
}

class Child extends ManagedObject<_Child> implements _Child {}

class _Child {
  @primaryKey
  int cid;
  String name;

  @Relate(Symbol('child'))
  Parent parent;

  Toy toy;

  ManagedSet<Vaccine> vaccinations;
}

class Toy extends ManagedObject<_Toy> implements _Toy {}

class _Toy {
  @primaryKey
  int tid;

  String name;

  @Relate(Symbol('toy'))
  Child child;
}

class Vaccine extends ManagedObject<_Vaccine> implements _Vaccine {}

class _Vaccine {
  @primaryKey
  int vid;
  String kind;

  @Relate(Symbol('vaccinations'))
  Child child;
}

Future<List<Parent>> populate(ManagedContext context) async {
  /*
                A            B      C
                C1           C2     C3
              T1  V1,V2       V3

   */
  var modelGraph = <Parent>[];
  var parents = [
    Parent()
      ..name = "A"
      ..child = (Child()
        ..name = "C1"
        ..toy = (Toy()..name = "T1")
        ..vaccinations = ManagedSet<Vaccine>.from([
          Vaccine()..kind = "V1",
          Vaccine()..kind = "V2",
        ])),
    Parent()
      ..name = "B"
      ..child = (Child()
        ..name = "C2"
        ..vaccinations = ManagedSet<Vaccine>.from([Vaccine()..kind = "V3"])),
    Parent()
      ..name = "C"
      ..child = (Child()..name = "C3"),
    Parent()..name = "D"
  ];

  for (var p in parents) {
    var q = Query<Parent>(context)..values.name = p.name;
    var insertedParent = await q.insert();
    modelGraph.add(insertedParent);

    if (p.child != null) {
      var childQ = Query<Child>(context)
        ..values.name = p.child.name
        ..values.parent = insertedParent;
      insertedParent.child = await childQ.insert();

      if (p.child.toy != null) {
        var toyQ = Query<Toy>(context)
          ..values.name = p.child.toy.name
          ..values.child = insertedParent.child;
        insertedParent.child.toy = await toyQ.insert();
      }

      if (p.child.vaccinations != null) {
        insertedParent.child.vaccinations = ManagedSet<Vaccine>.from(
            await Future.wait(p.child.vaccinations.map((v) {
          var vQ = Query<Vaccine>(context)
            ..values.kind = v.kind
            ..values.child = insertedParent.child;
          return vQ.insert();
        })));
      }
    }
  }

  return modelGraph;
}
