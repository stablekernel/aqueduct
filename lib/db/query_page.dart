part of aqueduct;

/// Page direction value for [QueryPage].
enum PageDirection {
  /// Indicates the page will contain results prior to the referenceValie.
  ///
  /// In the context of integer values, a page using [prior] and a [referenceValue]
  /// of 4 will specify 3, 2, 1, 0, -1, ... and so on. In the context of a DateTime, it
  /// will specify the moments before the [referenceValue].
  prior,

  /// Indicates the page will contain results after to the referenceValie.
  ///
  /// In the context of integer values, a page using [after] and a [referenceValue]
  /// of 1 will specify 2, 3, ... and so on. In the context of a DateTime, it
  /// will specify the moments after the [referenceValue].
  after
}

/// A description of a page of results to be applied to a [Query].
///
/// [QueryPage]s are a convenient way of accomplishing paging through a large
/// set of values.
///
/// A [QueryPage] instance defines three things to accomplish this.
/// The [referenceKey] is the property of the model that is being paged upon.
/// The [referenceValue] is a value that the consumer already has that represents
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
/// to traverse backward in the data set, a [QuerySet] would look like so:
///     var qp = new QueryPage(PageOrder.prior, "dateCreated", items.first.dateCreated);
///
class QueryPage {
  /// The direction to travel in relative to this [referenceValue].
  PageDirection direction;

  /// The property of the model object to page upon.
  String referenceKey;

  /// The value to page from.
  ///
  /// Objects with this value for [referenceKey] are NOT included in the data set, the [referenceValue]
  /// defines the bounds of the query, non-inclusive. For example, a reference value of 1 and a direction of after
  /// would yield results of >= 2, but never 1.
  /// This value may be null to indicate there is no reference value, and a fresh set of data should be returned
  /// from either the very beginning of very end of the ordered data set.
  dynamic referenceValue;

  QueryPage(this.direction, this.referenceKey, this.referenceValue);
}
