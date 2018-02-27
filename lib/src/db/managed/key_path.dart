import 'package:aqueduct/src/db/managed/managed.dart';

class KeyPath {
  KeyPath(ManagedPropertyDescription root) : path = [root];

  final List<ManagedPropertyDescription> path;
  List<String> dynamicElements;

  void add(ManagedPropertyDescription element) {
    path.add(element);
  }

  void addDynamicElement(String element) {
    dynamicElements ??= [];
    dynamicElements.add(element);
  }
}
