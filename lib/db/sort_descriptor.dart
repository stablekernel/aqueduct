part of aqueduct;

/// Order value for [SortDescriptor]s and [QueryPage]s.
enum SortOrder {
  /// Ascending order. Example: 1, 2, 3, 4, ...
  ascending,

  /// Descending order. Example: 4, 3, 2, 1, ...
  descending
}

/// The order in which a collection of objects should be sorted when returned from a database.
///
/// See [Query.sortDescriptors] and [Query.pageDescriptor] for more details.
class SortDescriptor {
  SortDescriptor(this.key, this.order);

  /// The name of a property to sort by.
  String key;

  /// The order in which values should be sorted.
  ///
  /// See [SortOrder] for possible values.
  SortOrder order;
}
