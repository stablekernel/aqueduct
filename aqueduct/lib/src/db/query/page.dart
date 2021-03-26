import 'query.dart';

/// A description of a page of results to be applied to a [Query].
///
/// [QueryPage]s are a convenient way of accomplishing paging through a large
/// set of values. A page has the property to page on, the order in which the table is being
/// paged and a value that indicates where in the ordered list of results the paging should start from.
///
/// Paging conceptually works by putting all of the rows in a table into an order. This order is determined by
/// applying [order] to the values of [propertyName]. Once this order is defined, the position in that ordered list
/// is found by going to the row (or rows) where [boundingValue] is eclipsed. That is, the point where row N
/// has a value for [propertyName] that is less than or equal to [boundingValue] and row N + 1 has a value that is greater than
/// [boundingValue]. The rows returned will start at row N + 1, ignoring rows 0 - N.
///
/// A query page should be used in conjunction with [Query.fetchLimit].
class QueryPage {
  QueryPage(this.order, this.propertyName, {this.boundingValue});

  /// The order in which rows should be in before the page of values is searched for.
  ///
  /// The rows of a database table will be sorted according to this order on the column backing [propertyName] prior
  /// to this page being fetched.
  QuerySortOrder order;

  /// The property of the model object to page on.
  ///
  /// This property must have an inherent order, such as an [int] or [DateTime]. The database must be able to compare the values of this property using comparison operator '<' and '>'.
  String propertyName;

  /// The point within an ordered set of result values in which rows will begin being fetched from.
  ///
  /// After the table has been ordered by its [propertyName] and [order], the point in that ordered table
  /// is found where a row goes from being less than or equal to this value to greater than or equal to this value.
  /// Page results start at the row where this comparison changes.
  ///
  /// Rows with a value equal to this value are not included in the data set. This value may be null. When this value is null,
  /// the [boundingValue] is set to be the just outside the first or last element of the ordered database table, depending on the direction.
  /// This allows for query pages that fetch the first or last page of elements when the starting/ending value is not known.
  dynamic boundingValue;
}
