part of aqueduct;

/// A description of a page of results to be applied to a [Query].
///
/// [QueryPage]s are a convenient way of accomplishing paging through a large
/// set of values.
///
/// A [QueryPage] instance defines three things to accomplish this.
/// The [propertyName] is the property of the model that is being paged upon.
/// The [boundingValue] is a value that the consumer already has that represents
/// the last item in its previous page.
/// The [order] is the direction to move in to receive the next page.
///
/// Example: Consider a model where each item has a 'dateCreated' timestamp.
/// In a data set, an item has been created once a day for the last year (there are 365 items).
/// A consumer has retrieve the first 10 items from the data set. To retrieve the next 10 according this timestamp,
/// they would create a [QueryPage] as follows:
///     var qp = new QueryPage(PageOrder.after, "dateCreated", items.last.dateCreated);
///
/// This would identify the items in the data set after the last item the consumer has access to. Likewise,
/// to traverse backward in the data set, a [QueryPage] would look like so:
///     var qp = new QueryPage(PageOrder.prior, "dateCreated", items.first.dateCreated);
///
class QueryPage {
  /// The direction to travel in relative to this [boundingValue].
  QuerySortOrder order;

  /// The property of the model object to page upon.
  String propertyName;

  /// The value to page from.
  ///
  /// Objects with this value for [propertyName] are NOT included in the data set, the [boundingValue]
  /// defines the bounds of the query, non-inclusive. For example, a reference value of 1 and a direction of after
  /// would yield results of >= 2, but never 1.
  /// This value may be null to indicate there is no reference value, and a fresh set of data should be returned
  /// from either the very beginning of very end of the ordered data set.
  dynamic boundingValue;

  QueryPage(this.order, this.propertyName, {this.boundingValue});
}
