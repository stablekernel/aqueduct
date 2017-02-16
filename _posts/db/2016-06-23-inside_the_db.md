---
layout: page
title: "Inside Aqueduct's ORM"
category: db
date: 2016-06-20 10:35:56
order: 6
---

Aqueduct applications use a number of objects to manage its relationship to a database. A `Query<T>` is an interface to a concrete class that translates it into flavor-specific SQL. `Query<T>`s are executed in a `ManagedContext`, which has two important properties: a `PersistentStore` and a `ManagedDataModel`. A `PersistentStore` is also an interface to a concrete class that manages flavor-specific SQL connections. A `ManagedDataModel` keeps all of the information about the `ManagedObject<T>`s in your application. This data model contains an instance of `ManagedEntity` for each `ManagedObject<T>` declared.

All of these objects work together to move data in and out of an Aqueduct application from where it came from and where it needs to go. They are all instantiated when an application starts up in the `RequestSink`'s constructor:

```dart
class MyRequestSink extends RequestSink {

  MyRequestSink(ApplicationConfiguration config) : super(config) {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        config.connectionInfo.username,
        config.connectionInfo.password,
        config.connectionInfo.host,
        config.connectionInfo.port,
        config.connectionInfo.databaseName);

    ManagedContext.defaultContext = new ManagedContext(dataModel, psc);
  }

  ...
}
```

This code will create a data model by reflecting on the codebase and finding every `ManagedObject<T>` subclass, creating and storing `ManagedEntity` for each. Then, it creates a concrete subclass of `PersistentStore`, `PostgreSQLPersistentStore`, with all the information it needs to connect to a PostgreSQL database. Finally, the context itself is created and assigned as the `ManagedContext.defaultContext`. (Even if you did not assign the new context to `defaultContext`, the last instantiated `ManagedContext` is always assigned as the default context.)

### ModelContext is the Bridge from Aqueduct to a Database

An instance of a `ManagedContext` is the container for all things related to a single database. It keeps a reference to its `PersistentStore` and `ManagedDataModel`, which together allow for the translation and transmission to and from a database into an Aqueduct application.  Most applications will only have one `ManagedContext`. Applications that talk to more than one database or different schemas within a database will have more.

Because most applications only have one `ManagedContext`, there is a default context for every application. If you are only creating a single `ManagedContext` in an application, that context is set to be the default context without any further action. The default context can be changed, but this is rarely done:

```dart
ManagedContext.defaultContext = new ManagedContext(dataModel, persistentStore);
```

Objects and methods that need a `ManagedContext` will default to the `defaultContext`, so its rare that you'd see `ManagedContext` anywhere outside of where it is first instantiated.

### ManagedDataModels Describe an Application's ManagedEntitys

Instances of `ManagedDataModel` are one of the two components of a `ManagedContext`. A `ManagedDataModel` has a definition for all of the managed objects in a context. In most applications, this means every `ManagedObject<T>` subclass you declare in your application. The `ManagedDataModel` will create instances of `ManagedEntity` to describe each `ManagedObject<T>`. In other words, a `ManagedDataModel` compiles your data model into entities that contain information at runtime to map data back and forth between a database.

`ManagedEntity`s are the description of a database table in your application.  A `ManagedEntity` contains references to the two types that make up a fully formed entity - the instance type (subclass of `ManagedObject<T>`) and its persistent type. They also contain the information derived from these types - the attributes and relationships - in a quickly accessible format. (More specifically, the reflection on all `ManagedObject<T>`s happens at startup only and all information is cached for use later.)

`ManagedEntity`s store relationship and attribute information in instances of `ManagedRelationshipDescription` and `ManagedAttributeDescription`, both of which extend `ManagedPropertyDescription`. This information is used by the rest of Aqueduct to determine how database columns are mapped to properties and back. This information is derived from the class declarations, and `ManagedColumnAttributes` and `ManagedRelationship` metadata that is used when defining your persistent types.

A `ManagedDataModel` will also validate all entities and their relationships. If validation fails, an exception will be thrown. As `ManagedDataModel`s are created at the beginning of the application's startup, this behavior will stop your application from running if there are data model errors.

### Persistent Stores Manage Database Connections and Versioning

`PersistentStore` is an abstract class. To connect to and interact with a specific flavor of SQL - like PostgreSQL or MySQL - a flavor-specific implementation of `PersistentStore` must exist. By default, Aqueduct ships with a `PostgreSQLPersistentStore`. There is nothing that prevents a `PersistentStore` implementation from connecting to and working with a NoSQL database, but the interface is geared towards SQL databases.

`PersistentStore`s are rarely used directly. Instead, a concrete implementation of `Query<T>` will send SQL to a `PersistentStore` for it to execute. `PersistentStore`s may be used directly to issue direct SQL to its underlying database connection. This is often useful for scripts and tests that modify a database schema. For this purpose, `PersistentStore` has an `execute` method to run raw SQL.

The tools to run database migrations invoke methods on a `PersistentStore` that must be implemented by a flavor-specific subclass.
