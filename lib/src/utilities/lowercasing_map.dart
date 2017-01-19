import 'dart:collection';

class LowercaseMap<V> extends Object with MapMixin<String, V> {
  LowercaseMap();
  LowercaseMap.fromMap(Map<String, dynamic> m) {
    m.forEach((k, v) {
      _inner[k.toLowerCase()] = v;
    });
  }

  Map<String, V> _inner = {};

  Iterable<String> get keys => _inner.keys;

  V operator [](Object key) => _inner[key];

  operator []=(String key, V value) {
    _inner[key.toLowerCase()] = value;
  }

  void clear() {
    _inner.clear();
  }

  V remove(Object key) => _inner.remove(key);
}

class LowercaseMapException implements Exception {
  LowercaseMapException(this.message);
  String message;
  String toString() => "LowercaseMapException: $message";
}
