import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

/*
  The test data is like so:

           A       B       C      D
         /   \     | \     |
        C1    C2  C3  C4  C5
      / | \    |   |
    T1 V1 V2  T2  V3
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

    test("Fetch has-many relationship that has none returns empty OrderedSet",
        () async {
      var q = Query<Parent>(context)
        ..join(set: (p) => p.children)
        ..where((o) => o.name).equalTo("D");

      var verifier = (Parent p) {
        expect(p.name, "D");
        expect(p.pid, isNotNull);
        expect(p.children, []);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetch has-many relationship that is empty returns empty, and deeper nested relationships are ignored even when included",
        () async {
      var q = Query<Parent>(context)..where((o) => o.name).equalTo("D");

      q.join(set: (p) => p.children)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations);

      var verifier = (Parent p) {
        expect(p.name, "D");
        expect(p.pid, isNotNull);
        expect(p.children, []);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetch has-many relationship that is non-empty returns values for scalar properties in subobjects only",
        () async {
      var q = Query<Parent>(context)
        ..join(set: (p) => p.children)
        ..where((o) => o.name).equalTo("C");

      var verifier = (Parent p) {
        expect(p.name, "C");
        expect(p.pid, isNotNull);
        expect(p.children.first.cid, isNotNull);
        expect(p.children.first.name, "C5");
        expect(p.children.first.backing.contents.containsKey("toy"), false);
        expect(p.children.first.backing.contents.containsKey("vaccinations"),
            false);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetch has-many relationship, include has-one and has-many in that has-many, where bottom of graph has valid object for hasmany but not for hasone",
        () async {
      var q = Query<Parent>(context)..where((o) => o.name).equalTo("B");

      q.join(set: (p) => p.children)
        ..sortBy((c) => c.cid, QuerySortOrder.ascending)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations);

      var verifier = (Parent p) {
        expect(p.name, "B");
        expect(p.pid, isNotNull);
        expect(p.children.first.cid, isNotNull);
        expect(p.children.first.name, "C3");
        expect(p.children.first.backing.contents.containsKey("toy"), true);
        expect(p.children.first.toy, isNull);
        expect(p.children.first.vaccinations.length, 1);
        expect(p.children.first.vaccinations.first.vid, isNotNull);
        expect(p.children.first.vaccinations.first.kind, "V3");

        expect(p.children.last.cid, isNotNull);
        expect(p.children.last.name, "C4");
        expect(p.children.last.backing.contents.containsKey("toy"), true);
        expect(p.children.last.toy, isNull);
        expect(p.children.last.vaccinations, []);
      };

      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetch has-many relationship, include has-one and has-many in that has-many, where bottom of graph has valid object for hasone but not for hasmany",
        () async {
      var q = Query<Parent>(context)..where((o) => o.name).equalTo("A");

      q.join(set: (p) => p.children)
        ..sortBy((c) => c.cid, QuerySortOrder.ascending)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations)
            .sortBy((v) => v.vid, QuerySortOrder.ascending);

      var verifier = (Parent p) {
        expect(p.name, "A");
        expect(p.pid, isNotNull);
        expect(p.children.first.cid, isNotNull);
        expect(p.children.first.name, "C1");
        expect(p.children.first.toy.tid, isNotNull);
        expect(p.children.first.toy.name, "T1");
        expect(p.children.first.vaccinations.length, 2);
        expect(p.children.first.vaccinations.first.vid, isNotNull);
        expect(p.children.first.vaccinations.first.kind, "V1");
        expect(p.children.first.vaccinations.last.vid, isNotNull);
        expect(p.children.first.vaccinations.last.kind, "V2");

        expect(p.children.last.cid, isNotNull);
        expect(p.children.last.name, "C2");
        expect(p.children.last.toy.tid, isNotNull);
        expect(p.children.last.toy.name, "T2");
        expect(p.children.last.vaccinations, []);
      };

      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test(
        "Fetching multiple top-level instances and including one level of subobjects",
        () async {
      var q = Query<Parent>(context)
        ..sortBy((p) => p.pid, QuerySortOrder.ascending)
        ..join(set: (p) => p.children)
        ..where((o) => o.name).oneOf(["A", "C", "D"]);
      var results = await q.fetch();
      expect(results.length, 3);

      expect(results.first.pid, isNotNull);
      expect(results.first.name, "A");
      expect(results.first.children.length, 2);
      expect(results.first.children.first.name, "C1");
      expect(results.first.children.first.backing.contents.containsKey("toy"),
          false);
      expect(
          results.first.children.first.backing.contents
              .containsKey("vaccinations"),
          false);
      expect(results.first.children.last.name, "C2");
      expect(results.first.children.last.backing.contents.containsKey("toy"),
          false);
      expect(
          results.first.children.last.backing.contents
              .containsKey("vaccinations"),
          false);

      expect(results[1].pid, isNotNull);
      expect(results[1].name, "C");
      expect(results[1].children.length, 1);
      expect(results[1].children.first.name, "C5");
      expect(
          results[1].children.first.backing.contents.containsKey("toy"), false);
      expect(
          results[1]
              .children
              .first
              .backing
              .contents
              .containsKey("vaccinations"),
          false);

      expect(results.last.pid, isNotNull);
      expect(results.last.name, "D");
      expect(results.last.children.length, 0);
    });

    test("Fetch entire graph", () async {
      var q = Query<Parent>(context);
      q.join(set: (p) => p.children)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations);

      var all = await q.fetch();

      var originalIterator = truth.iterator;
      for (var p in all) {
        originalIterator.moveNext();
        expect(p.pid, originalIterator.current.pid);
        expect(p.name, originalIterator.current.name);

        var originalChildrenIterator = p.children.iterator;
        p.children?.forEach((child) {
          originalChildrenIterator.moveNext();
          expect(child.cid, originalChildrenIterator.current.cid);
          expect(child.name, originalChildrenIterator.current.name);
          expect(child.toy?.tid, originalChildrenIterator.current.toy?.tid);
          expect(child.toy?.name, originalChildrenIterator.current.toy?.name);

          var vacIter =
              originalChildrenIterator.current.vaccinations?.iterator ??
                  <Vaccine>[].iterator;
          child.vaccinations?.forEach((v) {
            vacIter.moveNext();
            expect(v.vid, vacIter.current.vid);
            expect(v.kind, vacIter.current.kind);
          });
          expect(vacIter.moveNext(), false);
        });
      }
      expect(originalIterator.moveNext(), false);
    });
  });

  ////

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

      q.join(set: (p) => p.children)
        ..sortBy((c) => c.cid, QuerySortOrder.ascending)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations)
            .sortBy((v) => v.vid, QuerySortOrder.ascending);

      var results = await q.fetch();

      expect(results.length, 1);

      var p = results.first;

      expect(p.name, "A");
      expect(p.children.first.name, "C1");
      expect(p.children.first.toy.name, "T1");
      expect(p.children.first.vaccinations.first.kind, "V1");
      expect(p.children.first.vaccinations.last.kind, "V2");
      expect(p.children.last.name, "C2");
      expect(p.children.last.toy.name, "T2");
      expect(p.children.last.vaccinations, []);
    });

    test("Predicate impacts 2nd level objects when fetching object graph",
        () async {
      var q = Query<Parent>(context);

      q.join(set: (p) => p.children)
        ..where((o) => o.name).equalTo("C1")
        ..sortBy((c) => c.cid, QuerySortOrder.ascending)
        ..join(set: (c) => c.vaccinations)
            .sortBy((v) => v.vid, QuerySortOrder.ascending)
        ..join(object: (c) => c.toy);

      var results = await q.fetch();

      expect(results.length, 4);

      for (var p in results.sublist(1)) {
        expect(p.children, []);
      }

      var p = results.first;
      expect(p.children.length, 1);
      expect(p.children.first.name, "C1");
      expect(p.children.first.toy.name, "T1");
      expect(p.children.first.vaccinations.first.kind, "V1");
      expect(p.children.first.vaccinations.last.kind, "V2");
    });

    test("Predicate impacts 3rd level objects when fetching object graph",
        () async {
      var q = Query<Parent>(context);

      var childJoin = q.join(set: (p) => p.children)
        ..join(object: (c) => c.toy);
      childJoin
          .join(set: (c) => c.vaccinations)
          .where((o) => o.kind)
          .equalTo("V1");

      var results = await q.fetch();

      expect(results.length, 4);

      expect(results.first.name, "A");
      expect(results.first.children.first.name, "C1");
      expect(results.first.children.first.toy.name, "T1");
      expect(results.first.children.first.vaccinations.length, 1);
      expect(results.first.children.first.vaccinations.first.kind, "V1");
      expect(results.first.children.last.name, "C2");
      expect(results.first.children.last.toy.name, "T2");
      expect(results.first.children.last.vaccinations.length, 0);

      expect(results[1].name, "B");
      expect(results[1].children.first.name, "C3");
      expect(results[1].children.first.toy, isNull);
      expect(results[1].children.first.vaccinations.length, 0);
      expect(results[1].children.last.name, "C4");
      expect(results[1].children.last.toy, isNull);
      expect(results[1].children.last.vaccinations.length, 0);

      expect(results[2].name, "C");
      expect(results[2].children.first.name, "C5");
      expect(results[2].children.first.toy, isNull);
      expect(results[2].children.first.vaccinations.length, 0);

      expect(results[3].name, "D");
      expect(results[3].children, []);
    });

    test(
        "Predicate that omits top-level objects but would include lower level object return no results",
        () async {
      var q = Query<Parent>(context)..where((o) => o.pid).equalTo(5);

      var childJoin = q.join(set: (p) => p.children)
        ..join(object: (c) => c.toy);
      childJoin
          .join(set: (c) => c.vaccinations)
          .where((o) => o.kind)
          .equalTo("V1");

      var results = await q.fetch();
      expect(results.length, 0);
    });
  });

  group("Sort descriptor impact", () {
    ManagedContext context;
    List<Parent> truth;

    setUpAll(() async {
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      truth = await populate(context);
    });

    tearDownAll(() {
      context?.close();
    });

    test(
        "Sort descriptor on top-level object doesn't impact lower level objects",
        () async {
      var q = Query<Parent>(context)
        ..sortBy((p) => p.name, QuerySortOrder.descending);

      q.join(set: (p) => p.children)
        ..join(object: (c) => c.toy)
        ..join(set: (c) => c.vaccinations);

      var results = await q.fetch();

      var originalIterator = truth.reversed.iterator;
      for (var p in results) {
        originalIterator.moveNext();
        expect(p.pid, originalIterator.current.pid);
        expect(p.name, originalIterator.current.name);

        var originalChildrenIterator = p.children.iterator;
        p.children?.forEach((child) {
          originalChildrenIterator.moveNext();
          expect(child.cid, originalChildrenIterator.current.cid);
          expect(child.name, originalChildrenIterator.current.name);
          expect(child.toy?.tid, originalChildrenIterator.current.toy?.tid);
          expect(child.toy?.name, originalChildrenIterator.current.toy?.name);

          var vacIter =
              originalChildrenIterator.current.vaccinations?.iterator ??
                  <Vaccine>[].iterator;
          child.vaccinations?.forEach((v) {
            vacIter.moveNext();
            expect(v.vid, vacIter.current.vid);
            expect(v.kind, vacIter.current.kind);
          });
          expect(vacIter.moveNext(), false);
        });
      }
      expect(originalIterator.moveNext(), false);
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
        ..join(set: (p) => p.children);

      var o = await q.fetchOne();
      for (var c in o.children) {
        expect(identical(c.parent, o), false);
      }
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

    test("Trying to fetch hasMany relationship through resultProperties fails",
        () async {
      try {
        Query<Parent>(context).returningProperties((p) => [p.pid, p.children]);
      } on ArgumentError catch (e) {
        expect(
            e.toString(),
            contains(
                "Cannot select has-many or has-one relationship properties"));
      }
    });

    test(
        "Trying to fetch nested hasMany relationship through resultProperties fails",
        () async {
      try {
        final q = Query<Parent>(context);
        q
            .join(set: (p) => p.children)
            .returningProperties((p) => [p.cid, p.vaccinations]);

        expect(true, false);
      } on ArgumentError catch (e) {
        expect(
            e.toString(),
            contains(
                "Cannot select has-many or has-one relationship properties"));
      }
    });
  });
}

class Parent extends ManagedObject<_Parent> implements _Parent {}

class _Parent {
  @primaryKey
  int pid;
  String name;

  ManagedSet<Child> children;
}

class Child extends ManagedObject<_Child> implements _Child {}

class _Child {
  @primaryKey
  int cid;
  String name;

  @Relate(Symbol('children'))
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
  var modelGraph = <Parent>[];
  var parents = [
    Parent()
      ..name = "A"
      ..children = ManagedSet<Child>.from([
        Child()
          ..name = "C1"
          ..toy = (Toy()..name = "T1")
          ..vaccinations = ManagedSet<Vaccine>.from([
            Vaccine()..kind = "V1",
            Vaccine()..kind = "V2",
          ]),
        Child()
          ..name = "C2"
          ..toy = (Toy()..name = "T2")
      ]),
    Parent()
      ..name = "B"
      ..children = ManagedSet<Child>.from([
        Child()
          ..name = "C3"
          ..vaccinations = ManagedSet<Vaccine>.from([Vaccine()..kind = "V3"]),
        Child()..name = "C4"
      ]),
    Parent()
      ..name = "C"
      ..children = ManagedSet<Child>.from([Child()..name = "C5"]),
    Parent()..name = "D"
  ];

  for (var p in parents) {
    var q = Query<Parent>(context)..values.name = p.name;
    var insertedParent = await q.insert();
    modelGraph.add(insertedParent);

    insertedParent.children = ManagedSet<Child>();
    for (var child in p.children ?? <Child>[]) {
      var childQ = Query<Child>(context)
        ..values.name = child.name
        ..values.parent = insertedParent;
      insertedParent.children.add(await childQ.insert());

      if (child.toy != null) {
        var toyQ = Query<Toy>(context)
          ..values.name = child.toy.name
          ..values.child = insertedParent.children.last;
        insertedParent.children.last.toy = await toyQ.insert();
      }

      if (child.vaccinations != null) {
        insertedParent.children.last.vaccinations = ManagedSet<Vaccine>.from(
            await Future.wait(child.vaccinations.map((v) {
          var vQ = Query<Vaccine>(context)
            ..values.kind = v.kind
            ..values.child = insertedParent.children.last;
          return vQ.insert();
        })));
      }
    }
  }

  return modelGraph;
}
