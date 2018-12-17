# Connecting to a Database from Aqueduct

The purpose of this document is to guide you through creating a new PostgreSQL database and setting up an Aqueduct application that connects to it.

## Creating a Database

To use the Aqueduct ORM, you must have a PostgreSQL database server and create a database for your application. When developing locally, use [Postgres.app](https://postgresapp.com) to set up a development database server quickly. After running this application, create or select a new database server from the left-hand menu, and then double-click any of the database icons to open the `psql` command-line tool. (If you are not using `Postgres.app`, make sure `psql` is in your `$PATH` and run it from the command-line.)

Inside `psql`, enter the following commands to create a database and a database user for your application:

```sql
CREATE DATABASE my_app_name;
CREATE USER my_app_name_user WITH PASSWORD 'password';
GRANT ALL ON DATABASE my_app_name TO my_app_name_user;
```

## Using ManagedContext to Connect to a Database

The interface to a database from Aqueduct is an instance of `ManagedContext` that contains the following two objects:

- a `ManagedDataModel` that describes your application's data model
- a `PersistentStore` that manages a connection to a single database

A `ManagedContext` uses these two objects to coordinate moving data to and from your application and a database. A`Query<T>` object uses a context's persistent store to determine which database to send commands to, and a data model to map database rows to objects and vice versa.

A context, like all service objects, is created in `ApplicationChannel.prepare`.

```dart
class MyApplicationChannel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    var dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    var psc = PostgreSQLPersistentStore.fromConnectionInfo(
        "my_app_name_user", "password", "localhost", 5432, "my_app_name");

    context = ManagedContext(dataModel, psc);
  }
}
```

The `ManagedDataModel.fromCurrentMirrorSystem` finds every `ManagedObject<T>` subclass in your application's code. Optionally, you may specify an exact list:

```dart
var dataModel = ManagedDataModel([User, Post, Friendship]);
```

!!! note "Finding ManagedObjects"
        A managed object subclass must be directly or transitively imported into your application channel file. A file in your project directory that is not imported will not be found. There is typically no need to import a managed object subclass file directly: your application is initialized in your channel, where imports all of your controllers and services, which in turn import the managed object subclasses they use. As long as you are using your managed object declarations in your application, they'll be found.

Controllers that need to execute database queries must have a reference to a context; this is typically accomplished by passing the context to a controller's constructor:

```dart
class MyApplicationChannel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    context = ManagedContext(...);
  }

  @override
  Controller get entryPoint {
    return Router()
      ..route("/users/[:id]").link(() => UserController(context));
  }
}
```

## Using a Configuration File

Connection information for a database is most often read from a configuration file. This allows you to create configurations for different environments (production, development, etc.), without having to modify code. This is very important for testing, because you will want to run your automated tests against an empty database. ([See more on configuration files.](../application/configure.md).)

```dart
class MyConfiguration extends Configuration {
  MyConfiguration(String configPath) : super.fromFile(configPath);

  DatabaseConfiguration database;
}

class MyApplicationChannel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    final config = MyConfiguration(options.configurationFilePath);

    final dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    final psc = PostgreSQLPersistentStore.fromConnectionInfo(
        config.database.username,
        config.database.password,
        config.database.host,
        config.database.port,
        config.database.databaseName);        

    context = ManagedContext(dataModel, psc);
  }
}
```

The declaration of `MyConfiguration` requires that a YAML file must have the following structure:

```
database:
  username: bob
  password: bobspassword
  host: localhost
  port: 5432
  databaseName: my_app
```

### Connection Behavior

A persistent store manages one database connection. This connection is automatically maintained - the first time a query is executed, the connection is opened. If the connection is lost, the next query will reopen the connection. If a connection fails to open, an exception is thrown when trying to execute a query. This connection will return a 503 response if left uncaught.
