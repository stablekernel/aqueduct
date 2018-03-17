import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

import '../helpers.dart';

void main() {
  ManagedContext ctx;

  tearDown(() async {
    await ctx?.close();
  });

  test("Throws exception if no context has been created", () {
    try {
      new T();
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), contains("Did you forget to create a 'ManagedContext'?"));
    }
  });

  test("Can find entity creating managedobject", () {
    ctx = new ManagedContext(new ManagedDataModel.fromCurrentMirrorSystem(), new DefaultPersistentStore());
    final o = new T();
    o.id = 1;
    expect(o.id, 1);
  });

  test("Close context destroys data model", () async {
    ctx = new ManagedContext(new ManagedDataModel.fromCurrentMirrorSystem(), new DefaultPersistentStore());

    final o = new T();
    o.id = 1;
    expect(o.id, 1);

    await ctx.close();
    ctx = null;

    try {
      new T();
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), contains("Did you forget to create a 'ManagedContext'?"));
    }
  });

  test("Retained data model allows instantiation of ManagedObject", () async {
    final dm = new ManagedDataModel.fromCurrentMirrorSystem();
    ctx = new ManagedContext(dm, new DefaultPersistentStore());
    final retainedCtx = new ManagedContext(dm, new DefaultPersistentStore());
    await retainedCtx.close();

    final o = new T();
    o.id = 1;
    expect(o.id, 1);

    await ctx.close();
    ctx = null;

    try {
      new T();
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), contains("Did you forget to create a 'ManagedContext'?"));
    }
  });

}

class _T {
  @primaryKey
  int id;
}

class T extends ManagedObject<_T> implements _T {}
