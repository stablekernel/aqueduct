import 'package:aqueduct/src/db/managed/managed.dart';

class KeyPath {
  KeyPath(ManagedPropertyDescription root) : path = [root];
  KeyPath.from(KeyPath original, int offset) : path = original.path.sublist(offset);

  final List<ManagedPropertyDescription> path;
  List<dynamic> dynamicElements;

  int get length => path.length;

  void add(ManagedPropertyDescription element) {
    path.add(element);
  }

  void addDynamicElement(dynamic element) {
    dynamicElements ??= [];
    dynamicElements.add(element);
  }
}
