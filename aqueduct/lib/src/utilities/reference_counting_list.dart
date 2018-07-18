import 'dart:collection';

class ReferenceCountingList<T extends ReferenceCountable> extends ListBase<T> {
  List<T> _inner = <T>[];

  @override
  T operator [](int index) {
    return _inner[index];
  }

  @override
  void operator []=(int index, T object) {
    _inner[index] = object.._owner = this;
  }

  @override
  int get length => _inner.length;

  @override
  set length(int l) => _inner.length = l;

  @override
  void add(T element) => _inner.add(element.._owner = this);

  @override
  void addAll(Iterable<T> iterable) {
    _inner.addAll(iterable.map((i) => i.._owner = this));
  }
}

class ReferenceCountable {
  ReferenceCountingList _owner;
  int _retainCount = 0;

  void release() {
    _retainCount--;
    if (_retainCount <= 0) {
      _owner?.remove(this);
      _owner = null;
    }
  }

  void retain() {
    _retainCount++;
  }
}
