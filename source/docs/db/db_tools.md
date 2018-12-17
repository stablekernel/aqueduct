# Database Migration and Tooling

The `aqueduct db` command line tool creates and executes *migration files*. A migration file contains Dart code that executes SQL commands to create and modify database tables. 

!!! warning "PostgreSQL 9.6 and Greater"
    The minimum version of PostgreSQL needed to work with Aqueduct is 9.6.

## Migration Files

An application's data model is described by its `ManagedObject<T>` subclasses and their [table definition](modeling_data.md). Migration files describe a series of database commands that will create or modify a database schema to match an application's data model. Migration files are executed on a database when an application is first deployed and when changes to the data model occur - like adding new `ManagedObject<T>` subclasses or adding an database index to a property.

A migration file is automatically generated from your code. Each migration file contains only the changes made since the last migration file was generated. For example, if you began your application with a `Author` type and generated a migration file, the migration file would create the author table. If you then added a `Book` type generated a new migration file, the new file would only create the book table. When a migration is used to upgrade a database schema, every migration file that has not yet been run will be run.

Migration files must be stored in version control so that you can manage multiple databases for different environments.

## Generating Migration Files

The `aqueduct db generate` command generates a new migration file. This tool finds all `ManagedObject<T>` subclasses - your data model - in your application and compares them to the data model the last time the tool was run. Any differences between the data models are represented as a command in the generated migration file. If the new migration file were to be used to upgrade a database, the database would match the current data model in your application.

!!! note "Finding ManagedObjects"
        A managed object subclass must be directly or transitively imported into your application channel file. A file in your project directory that is not imported will not be found. There is typically no need to import a managed object subclass file directly: your application is initialized in your channel, where imports all of your controllers and services, which in turn import the managed object subclasses they use. As long as you are using your managed object declarations in your application, they'll be found.

Migration files are stored in an project's `migrations/` directory. Migration files are prefixed with a version number, a "0" padded eight digit number, ad suffixed with `.migration.dart`. For example, `00000001_initial.migration.dart` is a migration filename. The version number portion of the filename is required, as is the `.migration.dart` suffix. The underscore and remainder of the filename are optional and have no effect, they are just a way to name the file. Here is an example of two migration file names:

```
00000001_initial.migration.dart
00000002_add_user_nickname.migration.dart
```

The version number of migration files indicate the order in which they are applied. Leading zeros are stripped from the filenames before their version numbers are compared. Version numbers do not necessarily have to be continuous, but doing otherwise is not recommended. Migration files may be created altered after they are generated (see [seeding data](#seeding-data)).

## Validating Migration Files

The `aqueduct db validate` tool validates that the database schema after running all migration files matches the application's data model. The validate tool will display differences found between the schema in code and the schema created by migration files.

## Listing Migration Files

Use `aqueduct db list` to list all database migration files and their resolved version number.

## Getting a Database's Version

You can fetch a database's current version number with `aqueduct db get-version`. This command takes `--connect` or a `database.yaml` file as described in the next section to get connection info for the database.

## Upgrading a Database Schema by Executing Migration Files

The tool `aqueduct db upgrade` will apply the commands of migration files to a running database. This tool is run in an application's directory and database connection info is provided with the `--connect` option. For example, the following would execute the current project directory's migration files on a PostgreSQL database:

```
aqueduct db upgrade --connect postgres://username:password@localhost:5432/my_application
```

Every migration file that has not yet been run on the targeted database will be run. This tool manages a version table in each database it upgrades that allows it to determine which migration files need to be run.

Connection information can alternatively be stored in a database configuration file named `database.yaml` in the application directory. If this file exists with the following format, `--connect` can be omitted and connection information will be read from this file:

```
username: "user"
password: "password"
host: "host"
port: port
databaseName: "database"
```

### When to Execute Migration Files

During development, there is no need to create a migration file for each change. Execute migration files prior to deployment of a new version of an application.

You may delete migration files (as long as you haven't ran them on a production database!). When `aqueduct db generate` is run again, will replay only the existing migration files before determining which commands to add to the new migration file. For example, if you have 10 migration files over time and delete them all - the next generated migration file will contain commands to recreate the entire database schema.

### Seeding Data

You may insert, delete, or edit rows during a database migration by overriding its `seed` method. You must run SQL queries instead of using `Query<T>` when seeding data. The `Migration` base class that all of your migrations extends have a property for a `PersistentStore` connected to the database the migration is being run on.


```dart
class Migration2 extends Migration {
  @override
  Future upgrade() async {
    ...
  }

  @override
  Future downgrade() async {
    ...
  }

  @override
  Future seed() async {
    await store.executeQuery("INSERT IN _mytable (a) VALUES (1)");
  }
}
```

Seeding is ran after a migration's `ugprade` method has completed. Seeding data also occurs in the same transaction as `upgrade`.

### Handling Non-nullable Additions

Some database upgrades can fail depending on the data currently in the database. A common scenario is adding a property to an existing managed object that is not-nullable. If the database table already has rows, those rows would not have a value for the new column and the migration would fail. If the database does not have any rows, the migration will succeed correctly. If the property has a default value attribute or is auto-incrementing, the migration will always succeed and the existing rows will have the default value for the new column.

You may also provide a value just for the existing rows to make the migration succeed. This is added as an argument to the schema-altering command that would violate non-nullability:

```dart
@override
Future upgrade() async {
  database.addColumn("_mytable", SchemaColumn(...), unencodedInitialValue: "'text'")
}
```

The unencoded initial value is inserted directly into a SQL command. This requires that the value be a SQL value literal as shown in the table:

| Type | Unencoded Initial Value | Value |
| ---- | ----------------------- | ----- |
| int | "1" | 1 |
| String | "'string'" | 'string' |
| double | "2.0" | 2.0 |
| DateTime | "'1900-01-02T00:00:00.000Z'" | 1/2/1900 |
