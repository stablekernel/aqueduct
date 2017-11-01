# Connecting to a Database from Aqueduct

The interface to a database from Aqueduct is an instance of `ManagedContext`, which contains the following two objects:

- a `ManagedDataModel` that describes your application's data model
- a `PersistentStore` that creates database connections and transmits data across that connection.

A `ManagedContext` uses these two objects to coordinate moving data to and from your application and a database when executing `Query<T>`s. A `ManagedContext` - and its store and data model - are created in a `ApplicationChannel` constructor.

```dart
class MyApplicationChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        "username", "password", "host", 5432, "databaseName");

    ManagedContext.defaultContext = new ManagedContext(dataModel, psc);
  }
}
```

A `ManagedDataModel` should be instantiated with its `fromCurrentMirrorSystem` convenience constructor. You may optionally pass a list of `ManagedObject<T>` subclasses to its default constructor.

```dart
var dataModel = new ManagedDataModel([User, Post, Friendship]);
```

There is one `defaultContext` in an application. When executing a `Query<T>`, the default context is chosen if no other context is provided to its constructor. A default context must be instantiated before using any Aqueduct ORM objects or behavior.

Connection information for a database is often configured through a configuration file.

```dart
class MyConfigurationItem extends ConfigurationItem {
  MyConfigurationItem(String configPath) : super.fromFile(configPath);

  DatabaseConnectionConfiguration database;
}

class MyApplicationChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    var appConfig = new MyConfigurationItem(config.configurationFilePath);

    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        appConfig.database.username,
        appConfig.database.password,
        appConfig.database.host,
        appConfig.database.port,
        appConfig.database.databaseName);        

    ManagedContext.defaultContext = new ManagedContext(dataModel, psc);
  }
}
```

A YAML configuration file loaded by this application must look like this:

```
database:
  username: bob
  password: bobspassword
  host: localhost
  port: 5432
  databaseName: my_app
```

A `PersistentStore` is an interface. Concrete implementations - like `PostgreSQLPersistentStore` - implement that interface to transmit data to a database in the format it expects. A `PostgreSQLPersistentStore` will automatically connect and maintain a persistent connection to a database. If the connection is lost for some reason, it will automatically reconnect the next time a query is executed. If a connection cannot be established, a `QueryException` is thrown that yields a 503 status code response.
