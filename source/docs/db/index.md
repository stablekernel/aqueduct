## Tasks

Aqueduct's ORM stores data in a database and maps database data to Dart objects.

You create subclasses of `ManagedObject<T>` in your application code to define the database tables your application uses. The properties of these types have annotations like `Column` and `Validate` to customize the behavior of tables in your database.

Your application creates a `ManagedContext` service object during initialization that manages database access for your application. This service is injected into controllers that make database queries.

Instances of `Query<T>` are created to insert, update, read and delete data from a database. A `Query<T>` has many configurable options for filtering, joining, paging, sorting and performing aggregate functions on database rows.

The `aqueduct db` command-line tool manages databases that your application connects. This tool creates and executes migration scripts that update the schema of a database to match the requirements of your application.

The minimum version of PostgreSQL needed to work with Aqueduct is 9.6.

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
