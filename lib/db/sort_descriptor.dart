part of monadart;

/// Order value for [SortDescriptor]s.
enum SortDescriptorOrder {
  /// Ascending order; 1, 2, 3, 4, ...
  ascending,

  /// Descending order, 4, 3, 2, 1, ...
  descending
}

/// A key and order that defines the desired order of a collection of objects that contain key.
class SortDescriptor {
  /// The name of a property on an object to be sorted.
  ///
  /// Consider an object having the DateTime property 'dateCreated'. To define
  /// a [SortDescriptor] that sorts by that property, the key is simply the string 'dateCreated'.
  String key;

  /// The order in which values should be sorted.
  ///
  /// See [SortDescriptorOrder] for possible values.
  SortDescriptorOrder order;

  SortDescriptor(this.key, this.order);
}
