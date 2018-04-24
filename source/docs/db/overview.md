## Tasks

Aqueduct has an ORM to store data in a database and map database data to Dart objects.

- Defining a data model by declaring `ManagedObject<T>` subclasses
- Inserting, updating, reading and deleting data with `Query<T>`.
- Creating `ManagedObject<T>`s from HTTP request body data like JSON
- Encoding `ManagedObject<T>`s into an HTTP response body
- Generating and upgrading database schemas with the `aqueduct db` tool.

## Guides

- [Connecting to a Database](connecting.md)
- [Modeling Data](modeling_data.md)
- [Storage, Serialization and Deserialization](serialization.md)
- [Executing Queries](executing_queries.md)
- [Joins, Filtering and Paging](advanced_queries.md)
- [Executing Queries in a Transaction](transactions.md)
- [Adding Validations and Callbacks to ManagedObject](validations.md)
- [Aqueduct Database Tool](db_tools.md)
- [JSON Document Columns and Operations](json_columns.md)
