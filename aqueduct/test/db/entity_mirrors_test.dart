import 'dart:mirrors';

import 'package:aqueduct/src/runtime/orm/entity_mirrors.dart';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  ManagedContext context;
  tearDown(() async {
    await context?.close();
    context = null;
  });

  test("Have access to type args in Map", () {
    final type = getManagedTypeFromType(typeOf(#mapOfInts));
    expect(type.kind, ManagedPropertyType.map);
    expect(type.elements.kind, ManagedPropertyType.integer);
  });

  test("Have access to type args in list of maps", () {
    final type = getManagedTypeFromType(typeOf(#listOfIntMaps));
    expect(type.kind, ManagedPropertyType.list);
    expect(type.elements.kind, ManagedPropertyType.map);
    expect(type.elements.elements.kind, ManagedPropertyType.integer);
  });

  test("Cannot create ManagedType from invalid types", () {
    try {
      getManagedTypeFromType(typeOf(#invalidMapKey));
      fail("unreachable");
      // ignore: empty_catches
    } on UnsupportedError {}
    try {
      getManagedTypeFromType(typeOf(#invalidMapValue));
      fail("unreachable");
      // ignore: empty_catches
    } on UnsupportedError {}
    try {
      getManagedTypeFromType(typeOf(#invalidList));
      fail("unreachable");
      // ignore: empty_catches
    } on UnsupportedError {}

    try {
      getManagedTypeFromType(typeOf(#uri));
      fail("unreachable");
      // ignore: empty_catches
    } on UnsupportedError {}
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int id;

  String n;
  DateTime t;
  int l;
  bool b;
  double d;
  Document doc;
}

class TypeRepo {
  Map<String, int> mapOfInts;
  List<Map<String, int>> listOfIntMaps;

  Map<int, String> invalidMapKey;
  Map<String, Uri> invalidMapValue;

  List<Uri> invalidList;

  Uri uri;
}

TypeMirror typeOf(Symbol symbol) {
  return (reflectClass(TypeRepo).declarations[symbol] as VariableMirror).type;
}
