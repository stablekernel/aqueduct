part of aqueduct;

class OrderedSet<T extends Model> extends Object with ListMixin<T> {
  OrderedSet() {
    _innerValues = [];
    entity = ModelContext.defaultContext.dataModel.entityForType(T);
  }

  OrderedSet.from(Iterable<T> items) {
    _innerValues = items.toList();
    entity = ModelContext.defaultContext.dataModel.entityForType(T);
  }

  /// The [ModelEntity] this instance is described by.
  ModelEntity entity;

  List<T> _innerValues;
  T get matchOn {
    if (_matchOn == null) {
      _matchOn = entity.newInstance() as T;
      _matchOn._backing = new _ModelMatcherBacking();
    }
    return _matchOn;
  }
  T _matchOn;

  T get include {
    if (_include == null) {
      _include = entity.newInstance() as T;
      _include._backing = new _ModelMatcherBacking();
    }
    return _include;
  }
  T _include;

  void add(T item) {
    _innerValues.add(item);
  }

  void addAll(Iterable<T> items) {
    _innerValues.addAll(items);
  }

  int get length => _innerValues.length;
  void set length(int newLength) {
    _innerValues.length = newLength;
  }
  operator [](int index) => _innerValues[index];
  operator []=(int index, T value) {
    _innerValues[index] = value;
  }
}
