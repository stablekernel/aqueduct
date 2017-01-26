import 'dart:collection';

import 'backing.dart';
import '../../http/serializable.dart';
import 'managed.dart';
import 'query_matchable.dart';

/// Instances of this type contain zero or more instances of [ManagedObject].
///
/// 'Has many' relationship properties in [ManagedObject]s are represented by this type. [ManagedSet]s properties may only be declared in the persistent
/// type of a [ManagedObject]. Example usage:
///
///        class User extends ManagedObject<_User> implements _User {}
///        class _User {
///           ...
///           ManagedSet<Post> posts;
///        }
///
///        class Post extends ManagedObject<_Post> implements _Post {}
///        class _Post {
///          ...
///          @ManagedRelationship(#posts)
///          User user;
///        }
class ManagedSet<InstanceType extends ManagedObject> extends Object
    with ListMixin<InstanceType>, QueryMatchableExtension
    implements QueryMatchable, HTTPSerializable {
  /// Creates an empty [ManagedSet].
  ManagedSet() {
    _innerValues = [];
    entity =
        ManagedContext.defaultContext.dataModel.entityForType(InstanceType);
  }

  /// Creates a [ManagedSet] from an [Iterable] of [InstanceType]s.
  ManagedSet.from(Iterable<InstanceType> items) {
    _innerValues = items.toList();
    entity =
        ManagedContext.defaultContext.dataModel.entityForType(InstanceType);
  }

  /// The [ManagedEntity] that represents the [InstanceType].
  ManagedEntity entity;

  /// Used when building a [Query] to include instances of this type.
  ///
  /// A [Query] will, by default, fetch rows from a single table and return them as instances
  /// of the appropriate [ManagedObject] subclass. A [Query] may join on multiple database tables
  /// when setting this property to true in its [Query.where] subproperties. For example, the following
  /// query will fetch both 'Parent' and 'children' managed objects, where 'children' is a [ManagedSet].
  ///
  ///         var query = new Query<Parent>()
  ///           ..where.children.includeInResultSet = true;
  ///
  ///
  bool includeInResultSet = false;

  /// Used by [Query] to apply constraints to fetching instances from this [ManagedSet].
  ///
  /// See [Query.where] for more details. When constructing a [Query.where] that includes
  /// instances from this [ManagedSet], you may add matchers (such as [whereEqualTo]) to this property's properties to further
  /// constrain the values returned from the [Query].
  InstanceType get matchOn {
    if (_matchOn == null) {
      _matchOn = entity.newInstance() as InstanceType;
      _matchOn.backing = new ManagedMatcherBacking();
    }
    return _matchOn;
  }

  /// The number of elements in this set.
  int get length => _innerValues.length;
  void set length(int newLength) {
    _innerValues.length = newLength;
  }

  Map<String, dynamic> get backingMap => matchOn.backingMap;
  List<InstanceType> _innerValues;
  InstanceType _matchOn;

  /// Adds an [InstanceType] to this set.
  void add(InstanceType item) {
    _innerValues.add(item);
  }

  /// Adds an [Iterable] of [InstanceType] to this set.
  void addAll(Iterable<InstanceType> items) {
    _innerValues.addAll(items);
  }

  /// Retrieves an [InstanceType] from this set by an index.
  InstanceType operator [](int index) => _innerValues[index];

  /// Set an [InstanceType] in this set by an index.
  operator []=(int index, InstanceType value) {
    _innerValues[index] = value;
  }

  /// Returns a serialized [List] of the elements in this set.
  dynamic asSerializable() {
    return _innerValues.map((i) => i.asSerializable()).toList();
  }
}
