part of aqueduct;

class OrderedSet<InstanceType extends Model> extends Object with ListMixin<InstanceType>, _QueryMatchableExtension implements QueryMatchable  {
  OrderedSet() {
    _innerValues = [];
    entity = ModelContext.defaultContext.dataModel.entityForType(InstanceType);
  }

  OrderedSet.from(Iterable<InstanceType> items) {
    _innerValues = items.toList();
    entity = ModelContext.defaultContext.dataModel.entityForType(InstanceType);
  }

  ModelEntity entity;
  bool includeInResultSet = false;
  InstanceType get matchOn {
    if (_matchOn == null) {
      _matchOn = entity.newInstance() as InstanceType;
      _matchOn._backing = new _ModelMatcherBacking();
    }
    return _matchOn;
  }

  int get length => _innerValues.length;
  void set length(int newLength) {
    _innerValues.length = newLength;
  }

  Map<String, dynamic> get _matcherMap => matchOn.backingMap;
  List<InstanceType> _innerValues;
  InstanceType _matchOn;

  void add(InstanceType item) {
    _innerValues.add(item);
  }

  void addAll(Iterable<InstanceType> items) {
    _innerValues.addAll(items);
  }

  operator [](int index) => _innerValues[index];
  operator []=(int index, InstanceType value) {
    _innerValues[index] = value;
  }
}
