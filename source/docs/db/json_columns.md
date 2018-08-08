# JSON Document Storage

Learn how to store unstructured, binary JSON data in `ManagedObject<T>` properties.

## JSON Columns in Relational Databases

PostgreSQL supports many column data types like integers, strings, booleans and dates. A column may also be JSON data. This allows for storing unstructured data and simple objects in a table column. The data from JSON columns can be fetched all at once, or in pieces. Elements of JSON data can be used to filter the results of a query.

## The Document Data Type

JSON document columns are added to a database table by declaring a `Document` property in a `ManagedObject<T>`'s table definition. In PostgreSQL, a `Document` column data type is `jsonb`. A document column can only contain JSON-encodable data. This data is typically a `Map` or `List` that contains only JSON-encodable data. The following `ManagedObject<T>` declaration will have a `contents` column of type `jsonb`.

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

A `Document` object has a `data` property to hold its JSON-encodable data. When instantiating `Document`, this property defaults to null unless a value has been provided to the optional, ordered parameter in its constructor.

```dart
final doc = new Document();
assert(doc.data == null);

final doc = new Document({"key": "value"});
assert(doc.data is Map);

final doc = new Document([0]);
assert(doc.data is List);
```

The data in a document can be accessed through its `data` property, or through its subscript operator. `Document`'s subscript operator forwards the invocation to its `data` property.

```dart
final doc = new Document({"key": "value"});

assert(doc["key"] == doc.data["key"]);
```

The argument to the subscript operator may be a string (if `data` is a map) or an integer (if `data` is a list).

## Basic Operations on Document Properties

`Document` columns are like any other type of column, and can therefore be set during an insert or update, and read during a fetch.

### Inserting Rows with Document Properties

A `Document` property is first set when inserting with a `Query<T>`. The `values` property of the query is set to a `Document` object initialized with a JSON-encodable value.

```dart
final query = Query<Event>(context)
  ..values.timestamp = DateTime.now()
  ..values.contents = Document({
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
final query = Query<Event>(context)
  ..where((e) => e.id).equalTo(1);
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
final query = Query<Event>(context)
  ..where((e) => e.id).equalTo(1)
  ..values.contents = Document({
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
final doc = Document({"key": "value"});
final value = doc["key"] == "value";

// List Access by index
final doc = Document(["v1", "v2"]);
final value = doc[0] == "v1";
```

You can access nested elements with the same syntax:

```dart
final doc = Document([
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
final query = Query<Event>(context)
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
final query = Query<Event>(context)
  ..returningProperties((e) => [e.id, e.contents["tags"][0]]);
final eventsWithFirstTag = await query.fetchOne();
eventsWithFirstTag.contents.data == "v1";
```

If a key or index does not exist in the JSON document, the value of the returned property will be null. For this reason, you should use null-aware operators when accessing `Document.data`:

```dart
final query = Query<Event>(context)
  ..returningProperties((e) => [e.id, e.contents["tags"][7]]); // 7 is out of bounds
final eventsWithFirstTag = await query.fetchOne();
if (eventsWithFirstTag.contents?.data == "v1") {
  ...
}
```

When fetching elements from a JSON array, you may use negative indices to specify a index from the end of the array.

```dart
final query = Query<Event>(context)
  ..returningProperties((e) => [e.id, e.contents["tags"][-1]]);
final eventsWithLastTag = await query.fetchOne();
```

Note that you can only fetch a single sub-structure from a `Document` column per query. That is, you may not do the following:

```dart
// Invalid
final query = Query<Event>(context)
  ..returningProperties((e) => [e.id, e.contents["type"], e.contents["user"]]);
```

For operations not supported by `Query<T>`, you may use SQL directly:

```dart
final eventTagCounts = await context.persistentStore.execute("SELECT jsonb_array_length(contents->'tags') from _Event");
```
