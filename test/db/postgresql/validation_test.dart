import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ManagedContext ctx;
  setUpAll(() async {
    ctx = await contextWithModels([T, U, V, W]);
  });

  tearDownAll(() async {
    await ctx.persistentStore.close();
  });

  test("update runs update validations", () async {
    var q = new Query<T>()
      ..values.aOrb = "a";
    var objectID = (await q.insert()).id;

    q = new Query<T>()
      ..where.id = whereEqualTo(objectID)
      ..values.equalTo2OnUpdate = 2;
    var o = (await q.update()).first;
    expect(o.aOrb, "a");
    expect(o.equalTo2OnUpdate, 2);

    q = new Query<T>()
      ..where.id = whereEqualTo(objectID)
      ..values.aOrb = "c"
      ..values.equalTo2OnUpdate = 2;
    try {
      await q.update();
      expect(true, false);
    } on ValidationException catch (e) {
      expect(e.toString(), contains("Must be one of: 'a','b'"));
    }

    q = new Query<T>()
      ..where.id = whereEqualTo(objectID)
      ..values.aOrb = "b"
      ..values.equalTo2OnUpdate = 1;
    try {
      await q.update();
      expect(true, false);
    } on ValidationException catch (e) {
      expect(e.toString(), contains("Must be equal to '2'"));
    }

    q = new Query<T>()
      ..where.id = whereEqualTo(objectID)
      ..values.aOrb = "b"
      ..values.equalTo1OnInsert = 2
      ..values.equalTo2OnUpdate = 2;
    o = (await q.update()).first;
    expect(o.aOrb, "b");
    expect(o.equalTo1OnInsert, 2);
    expect(o.equalTo2OnUpdate, 2);
  });

  test("updateOne runs update validations", () async {
    var q = new Query<T>()
      ..where.id = whereEqualTo(1)
      ..values.equalTo2OnUpdate = 3;
    try {
      await q.updateOne();
      expect(true, false);
    } on ValidationException catch (e) {
      expect(e.toString(), contains("Must be equal to"));
    }
  });

  test("insert runs insert validations", () async {
    var q = new Query<T>()
      ..values.aOrb = "a"
      ..values.equalTo1OnInsert = 1;
    var o = await q.insert();
    expect(o.aOrb, "a");
    expect(o.equalTo1OnInsert, 1);

    q = new Query<T>()
      ..values.aOrb = "c"
      ..values.equalTo1OnInsert = 1;
    try {
      await q.insert();
      expect(true, false);
    } on ValidationException catch (e) {
      expect(e.toString(), contains("Must be one of"));
    }

    q = new Query<T>()
      ..values.aOrb = "b"
      ..values.equalTo1OnInsert = 2;
    try {
      await q.insert();
      expect(true, false);
    } on ValidationException catch (e) {
      expect(e.toString(), contains("Must be equal to"));
    }

    q = new Query<T>()
      ..values.aOrb = "b"
      ..values.equalTo1OnInsert = 1
      ..values.equalTo2OnUpdate = 1;
    o = await q.insert();
    expect(o.aOrb, "b");
    expect(o.equalTo1OnInsert, 1);
    expect(o.equalTo2OnUpdate, 1);
  });

  test("valueMap ignores validations", () async {
    var q = new Query<T>()
      ..valueMap = {
        "aOrb": "c",
        "equalTo1OnInsert": 10
      };
    var o = await q.insert();
    expect(o.aOrb, "c");
    expect(o.equalTo1OnInsert, 10);
  });

  test("willUpdate runs prior to update", () async {
    var q = new Query<U>();
    var o = await q.insert();
    q = new Query<U>()..where.id = whereEqualTo(o.id);
    o = (await q.update()).first;
    expect(o.q, "willUpdate");
  });

  test("willInsert runs prior to insert", () async {
    var q = new Query<U>();
    var o = await q.insert();
    expect(o.id, isNotNull);
    expect(o.q, "willInsert");

  });

  test("ManagedObject onUpdate is subject to all validations", () async {
    var q = new Query<V>();
    var o = await q.insert();

    q = new Query<V>()..where.id = whereEqualTo(o.id);
    try {
      await q.update();
      expect(true, false);
    } on ValidationException catch (e) {
      expect(e.toString(), contains("'f'"));
      expect(e.toString(), contains("Must be one of"));
    }
  });

  test("ManagedObject onInsert is subject to all validations", () async {
    var q = new Query<W>();
    try {
      await q.insert();
      expect(true, false);
    } on ValidationException catch (e) {
      expect(e.toString(), contains("'f'"));
      expect(e.toString(), contains("Must be one of"));
    }
  });
}

class T extends ManagedObject<_T> implements _T {}
class _T {
  @primaryKey
  int id;

  @Validate.oneOf(const ["a", "b"])
  @Column(nullable: true)
  String aOrb;

  @Validate.compare(equalTo: 1, onUpdate: false, onInsert: true)
  @Column(nullable: true)
  int equalTo1OnInsert;

  @Validate.compare(equalTo: 2, onUpdate: true, onInsert: false)
  @Column(nullable: true)
  int equalTo2OnUpdate;
}

class U extends ManagedObject<_U> implements _U {
  @override
  void willUpdate() {
    q = "willUpdate";
  }

  @override
  void willInsert() {
    q = "willInsert";
  }
}
class _U {
  @primaryKey
  int id;

  String q;
}

class V extends ManagedObject<_V> implements _V {
  @override
  void willUpdate() {
    f = "c";
  }
}
class _V {
  @primaryKey
  int id;

  @Validate.oneOf(const ["a", "b"])
  @Column(nullable: true)
  String f;
}

class W extends ManagedObject<_W> implements _W {
  @override
  void willInsert() {
    f = "c";
  }
}
class _W {
  @primaryKey
  int id;

  @Validate.oneOf(const ["a", "b"])
  @Column(nullable: true)
  String f;
}