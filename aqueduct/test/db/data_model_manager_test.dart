import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  ManagedContext ctx;

  tearDown(() async {
    await ctx?.close();
  });

  test("Throws exception if no context has been created", () {
    try {
      T();
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(),
          contains("Did you forget to create a 'ManagedContext'?"));
    }
  });

  test("Can find entity creating managedobject", () {
    ctx = ManagedContext(
        ManagedDataModel.fromCurrentMirrorSystem(), DefaultPersistentStore());
    final o = T();
    o.id = 1;
    expect(o.id, 1);
  });

  test("Close context destroys data model", () async {
    ctx = ManagedContext(
        ManagedDataModel.fromCurrentMirrorSystem(), DefaultPersistentStore());

    final o = T();
    o.id = 1;
    expect(o.id, 1);

    await ctx.close();
    ctx = null;

    try {
      T();
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(),
          contains("Did you forget to create a 'ManagedContext'?"));
    }
  });

  test("Retained data model allows instantiation of ManagedObject", () async {
    final dm = ManagedDataModel.fromCurrentMirrorSystem();
    ctx = ManagedContext(dm, DefaultPersistentStore());
    final retainedCtx = ManagedContext(dm, DefaultPersistentStore());
    await retainedCtx.close();

    final o = T();
    o.id = 1;
    expect(o.id, 1);

    await ctx.close();
    ctx = null;

    try {
      T();
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(),
          contains("Did you forget to create a 'ManagedContext'?"));
    }
  });
}

class _T {
  @primaryKey
  int id;
}

class T extends ManagedObject<_T> implements _T {}
