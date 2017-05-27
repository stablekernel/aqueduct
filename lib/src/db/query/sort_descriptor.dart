import 'query.dart';

/// The order in which a collection of objects should be sorted when returned from a database.
///
/// See [Query.sortBy] and [Query.pageBy] for more details.
class QuerySortDescriptor {
  QuerySortDescriptor(this.key, this.order);

  /// The name of a property to sort by.
  String key;

  /// The order in which values should be sorted.
  ///
  /// See [QuerySortOrder] for possible values.
  QuerySortOrder order;
}
