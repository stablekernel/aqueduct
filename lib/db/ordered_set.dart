part of aqueduct;

class OrderedSet<T extends Model> extends Object with ListMixin<T>, _QueryMatchableExtension implements QueryMatchable  {
  OrderedSet() {
    _innerValues = [];
    entity = ModelContext.defaultContext.dataModel.entityForType(T);
  }

  OrderedSet.from(Iterable<T> items) {
    _innerValues = items.toList();
    entity = ModelContext.defaultContext.dataModel.entityForType(T);
  }

  ModelEntity entity;
  bool includeInResultSet = false;
  T get matchOn {
    if (_matchOn == null) {
      _matchOn = entity.newInstance() as T;
      _matchOn._backing = new _ModelMatcherBacking();
    }
    return _matchOn;
  }

  int get length => _innerValues.length;
  void set length(int newLength) {
    _innerValues.length = newLength;
  }

  Map<String, dynamic> get _matcherMap => matchOn.populatedPropertyValues;
  List<T> _innerValues;
  T _matchOn;

  void add(T item) {
    _innerValues.add(item);
  }

  void addAll(Iterable<T> items) {
    _innerValues.addAll(items);
  }

  operator [](int index) => _innerValues[index];
  operator []=(int index, T value) {
    _innerValues[index] = value;
  }
}
