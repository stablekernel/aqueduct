class KeyPath {
  KeyPath(this.propertyKey);

  final String propertyKey;
  final List<String> elements = [];

  dynamic operator [](dynamic keyOrIndex) {
    elements.add(keyOrIndex);
    return this;
  }
}
