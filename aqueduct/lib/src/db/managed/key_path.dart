import 'package:aqueduct/src/db/managed/managed.dart';

class KeyPath {
  KeyPath(ManagedPropertyDescription root) : path = [root];

  KeyPath.byRemovingFirstNKeys(KeyPath original, int offset)
      : path = original.path.sublist(offset);

  KeyPath.byAddingKey(KeyPath original, ManagedPropertyDescription key)
      : path = List.from(original.path)..add(key);

  final List<ManagedPropertyDescription> path;
  List<dynamic> dynamicElements;

  ManagedPropertyDescription operator [](int index) => path[index];

  int get length => path.length;

  void add(ManagedPropertyDescription element) {
    path.add(element);
  }

  void addDynamicElement(dynamic element) {
    dynamicElements ??= [];
    dynamicElements.add(element);
  }
}
