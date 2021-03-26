import 'dart:collection';

import 'managed.dart';

/// Instances of this type contain zero or more instances of [ManagedObject] and represent has-many relationships.
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
///          @Relate(#posts)
///          User user;
///        }
class ManagedSet<InstanceType extends ManagedObject> extends Object
    with ListMixin<InstanceType> {
  /// Creates an empty [ManagedSet].
  ManagedSet() {
    _innerValues = [];
  }

  /// Creates a [ManagedSet] from an [Iterable] of [InstanceType]s.
  ManagedSet.from(Iterable<InstanceType> items) {
    _innerValues = items.toList();
  }

  /// Creates a [ManagedSet] from an [Iterable] of [dynamic]s.
  ManagedSet.fromDynamic(Iterable<dynamic> items) {
    _innerValues = List<InstanceType>.from(items);
  }

  List<InstanceType> _innerValues;

  /// The number of elements in this set.
  @override
  int get length => _innerValues.length;

  @override
  set length(int newLength) {
    _innerValues.length = newLength;
  }

  /// Adds an [InstanceType] to this set.
  @override
  void add(InstanceType item) {
    _innerValues.add(item);
  }

  /// Adds an [Iterable] of [InstanceType] to this set.
  @override
  void addAll(Iterable<InstanceType> items) {
    _innerValues.addAll(items);
  }

  /// Retrieves an [InstanceType] from this set by an index.
  @override
  InstanceType operator [](int index) => _innerValues[index];

  /// Set an [InstanceType] in this set by an index.
  @override
  void operator []=(int index, InstanceType value) {
    _innerValues[index] = value;
  }
}
