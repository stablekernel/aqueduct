part of monadart;

class ModelMatcher extends ModelBackable {
  Map<String, MatcherExpression> _map = {};
  Predicate get predicate {
    if (_map.length == 1) {
      var exprKey = _map.keys.first;
      return _predicateForKey(exprKey, 0);
    }

    int index = 0;
    return Predicate.andPredicates(_map.keys.map((propertyKey) {
      var pred = _predicateForKey(propertyKey, index);
      index ++;

      return pred;
    }).toList());
  }

  MatcherExpression operator [](String key) {
    return _map[key];
  }

  void operator []=(String key, dynamic value) {
    _setMatcherForPropertyName(key, value);
  }

  Predicate _predicateForKey(String propertyKey, int index) {
    var expr = _map[propertyKey];
    if (expr is _AmbiguousModelMatcherExpression) {
      propertyKey = foreignKeyForProperty(propertyKey);
    }
    return expr.getPredicate(propertyKey, index);
  }

  bool get _isTypedSubclass {
    return reflect(this).type != reflectType(ModelMatcher);
  }

  void _setMatcherForPropertyName(String propertyName, dynamic value) {
    if (value is _AmbiguousModelMatcherExpression) {
      if (_isTypedSubclass) {
        var ivarType = _typeMirrorForProperty(propertyName);
        if (!(ivarType.isSubtypeOf(reflectType(Model)) || ivarType.isSubtypeOf(reflectType(List)))) {
          throw new PredicateMatcherException("Type mismatch for property $propertyName; not a Model or List<Model>.");
        }
      }

      _map[propertyName] = value;
    } else if (value is MatcherExpression) {
      _map[propertyName] = value;
    } else {
      if (_isTypedSubclass) {
        var ivarType = _typeMirrorForProperty(propertyName);
        var valueType = reflect(value).type;
        if (!valueType.isSubtypeOf(ivarType)) {
          var ivarTypeName = MirrorSystem.getName(ivarType.simpleName);
          var valueTypeName = MirrorSystem.getName(valueType.simpleName);

          var typeName = MirrorSystem.getName(reflect(this).type.simpleName);
          throw new PredicateMatcherException("Type mismatch for property $propertyName on ${typeName}, expected $ivarTypeName but got $valueTypeName.");
        }
      }
      _map[propertyName] = new _AssignmentMatcherExpression(value);
    }
  }

  noSuchMethod(Invocation i) {
    if (i.isGetter) {
      var propertyName  = MirrorSystem.getName(i.memberName);
      return _map[propertyName];
    } else if (i.isSetter) {
      var propertyName = MirrorSystem.getName(i.memberName);
      propertyName = propertyName.substring(0, propertyName.length - 1);

      var value = i.positionalArguments.first;
      if (value == null) {
        _map.remove(propertyName);
        return null;
      }

      _setMatcherForPropertyName(propertyName, value);

      return null;
    }
    return super.noSuchMethod(i);
  }
}

