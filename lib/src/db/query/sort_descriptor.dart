/// Order value for [QuerySortDescriptor]s and [QueryPage]s.
enum QuerySortOrder {
  /// Ascending order. Example: 1, 2, 3, 4, ...
  ascending,

  /// Descending order. Example: 4, 3, 2, 1, ...
  descending
}

/// The order in which a collection of objects should be sorted when returned from a database.
///
/// See [Query.sortDescriptors] and [Query.pageDescriptor] for more details.
class QuerySortDescriptor {
  QuerySortDescriptor(this.key, this.order);

  /// The name of a property to sort by.
  String key;

  /// The order in which values should be sorted.
  ///
  /// See [QuerySortOrder] for possible values.
  QuerySortOrder order;
}
