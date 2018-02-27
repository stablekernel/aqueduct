# JSON Document Storage

Learn how to store unstructured, binary JSON data in `ManagedObject<T>` properties.

## JSON Columns in Relational Databases

PostgreSQL supports many column data types like integers, strings, booleans and dates. A column may also be JSON data. This allows for storing unstructured data and simple objects in a table column. The data from JSON columns can be fetched all at once, or in pieces. Elements of JSON data can be used to filter the results of a query.

## The Document Data Type

JSON document columns are added to a database table by declaring a `Document` property in a `ManagedObject<T>`'s persistent type. A document column can contain either a JSON-encodable `Map` or `List`.

```dart
class Event extends ManagedObject<_Event> implements _Event {}
class _Event {
  @primaryKey
  int id;

  @Column(indexed: true)
  DateTime timestamp;

  Document contents;
}
```

In PostgreSQL, a `Document` column data type is `jsonb`.

## Basic Operations on Document Properties

`Document` columns are like any other type of column, and can therefore be set during an insert or update, and read during a fetch.

### Inserting Rows with Document Properties

A `Document` property is first set when inserting with a `Query<T>`. The `values` property of the query is set to a `Document` object initialized with a JSON-encodable value.

```dart
final query = new Query<Event>()
  ..values.timestamp = new DateTime.now()
  ..values.contents = new Document({
    "type": "push",
    "user": "bob",
    "tags": ["v1"]
  });
final event = await query.insert();  
```

In the above, the argument to `Document` will be JSON-encoded and stored in the database for column `contents`. If the object can't be encoded as JSON, an exception will be thrown.

### Fetching Rows with Document Properties

When fetching an object with `Document` properties with a `Query<T>`, you access the column's value through the document's `data` property.

```dart
final query = new Query<Event>()
  ..where.id = whereEqualTo(1);
final event1 = await query.fetchOne();
event1.contents.data == {
  "type": "push",
  "user": "bob",
  "tags": ["v1"]
};
```

When fetching `Document` properties, the JSON data is decoded into the appropriate type. This is likely a `Map` or `List`, but can be any JSON-encodable object. Because the data stored in a `Document` property is unstructured, the type of `data` is `dynamic`. It is good practice to store consistent data structures in a column; i.e., always storing a `Map` or always storing a `List`.

### Updating Rows with Document Properties

Updating a row with `Document` properties works the same as inserting rows.

```dart
final query = new Query<Event>()
  ..where.id = whereEqualTo(1)
  ..values.contents = new Document({
    "type": "push",
    "user": "bob",
    "tags": ["v1", "new"]
  });
final event = await query.updateOne();  
```

When updating in this way, the document stored in the column is replaced entirely.

### Accessing Document Values

The type of `Document.data` is `dynamic` - it can be any valid JSON type and may be casted to the expected type when used. This data can also be nested - a `List` of `Maps`, for example. When accessing object keys or list indices, you may use the subscript operator directly on `Document`.

```dart
// Object Access by key
final doc = new Document({"key": "value"});
final value = doc["key"] == "value";

// List Access by index
final doc = new Document(["v1", "v2"]);
final value = doc[0] == "v1";
```

You can access nested elements with the same syntax:

```dart
final doc = new Document([
  {"id": 1},
  {"id": 2}
]);

final obj1 = doc[0]["id"]; // == 1
final obj2 = doc[1]["id"]; // == 2
```

Note that using the subscript operator on a `Document` simply invokes it on its `data` property. Therefore, any subscript values must be valid for Dart `List` and `Map` types.

## Fetching Sub-documents

When fetching a `Document` property, the default behavior is to return the entire JSON document as it is stored in the database column. You may fetch parts of the document you need by using `Query.returningProperties` and the subscript operator.

```dart
final query = new Query<Event>()
  ..returningProperties((e) => [e.id, e.contents["tags"]]);
final eventsWithTags = query.fetch();
```

When using the subscript operator on a returned `Document` property, only the value for that key is returned. For example, if the above query were executed and the stored column's value were:

```json
{
  "type": "push",  
  "user": "bob",
  "tags": ["v1"]  
}
```

The value of `Event.contents` would only contain the array for the key "tags":

```json
["v1"]
```

You may also index arrays in a JSON column using the same subscript operator, and the subscript operator can also be nested. For example, the following query would fetch the "tags" array, and then fetch the string at index 0 from it:

```dart
final query = new Query<Event>()
  ..returningProperties((e) => [e.id, e.contents["tags"][0]]);
final eventsWithFirstTag = await query.fetchOne();
eventsWithFirstTag.contents.data == "v1";
```

If a key or index does not exist in the JSON document, the value of the returned property will be null. For this reason, you should use null-aware operators when accessing `Document.data`:

```dart
final query = new Query<Event>()
  ..returningProperties((e) => [e.id, e.contents["tags"][7]]); // 7 is out of bounds
final eventsWithFirstTag = await query.fetchOne();
if (eventsWithFirstTag.contents?.data == "v1") {
  ...
}
```

When fetching elements from a JSON array, you may use negative indices to specify a index from the end of the array.

```dart
final query = new Query<Event>()
  ..returningProperties((e) => [e.id, e.contents["tags"][-1]]);
final eventsWithLastTag = await query.fetchOne();
```

Note that you can only fetch a single sub-structure from a `Document` column per query. That is, you may not do the following:

```dart
// Invalid
final query = new Query<Event>()
  ..returningProperties((e) => [e.id, e.contents["type"], e.contents["user"]]);
```

For operations not supported by `Query<T>`, you may use SQL directly:

```dart
final eventTagCounts = await context.query("SELECT jsonb_array_length(contents->'tags') from _Event");
```

## Using JSON Documents to Filter Query Results

The values stored in a `Document` column can be used to filter the results returned from a query. The following example will return objects that have the value 'bob' for the key 'user' in their `contents` property.

```dart
final query = new Query<Event>()
  ..where.contents["user"] = whereEqualTo("bob");
final events = await query.fetch();
```

If an `event.contents` has another value for 'user' or does not have a 'user' key at all, that event will not be fetched.

When matching a value stored in a document property, you must subscript the `Document` property. The matcher is applied to the subscripted key path. You may also use index arrays to match array elements, and use nested subscript operators to match values deeper in the object structure. All comparison matchers may be used in this way.

The matcher `whereContains` is the only matcher that can be also applied directly to a `Document` property. It tests whether the top-level object or array contains an element. For objects, it tests whether the key exists in the object. For arrays, it tests whether the the argument is contained in that array. The following would only fetch events that have a 'type' key.

```dart
final query = new Query<Event>()
  ..where.contents = whereContains("type");
final eventsWithAnyType = await query.fetch();
```

### Important Note on Indexing and Performance

## Modifying a JSON Document

Typically when updating a `Document` property, you fetch it, modify it in memory, and then use the modified value in an update query. For some situations, it may make sense to update the contents of a `Document` property without first fetching it.

Existing values in a JSON document can be modified using the subscript operator with an update query's `values`. The following query sets the 'status' of every event's contents to 'complete'.

```dart
final query = new Query<Event>()
  ..values.contents["status"] = "complete";
final events = await query.update();
```

If 'status' did not exist in `contents`, it would be added to the object.

You may also modify nested values, as well as modify objects in an array. For example, the following query sets the value of the first 'items' to 'flashlight'.

```dart
final query = new Query<Event>()
  ..values.contents["items"][0] = "flashlight";
final events = await query.update();
```

Note that if the key 'items' does not exist in `contents`, no operation is performed because there is no array to index into.

If an index is out of bounds for an array, the value will be inserted at the end of the array. Otherwise, the value is replaced in the array. You may use negative indices to replace values by counting from the end of the array. It is not currently possible to insert an object into an array without first fetching it (unless you use SQL directly).
