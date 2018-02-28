import 'package:aqueduct/src/db/managed/managed.dart';

class KeyPath {
  KeyPath(ManagedPropertyDescription root) : path = [root];

  final List<ManagedPropertyDescription> path;
  List<dynamic> dynamicElements;

  void add(ManagedPropertyDescription element) {
    path.add(element);
  }

  void addDynamicElement(dynamic element) {
    dynamicElements ??= [];
    dynamicElements.add(element);
  }
}
