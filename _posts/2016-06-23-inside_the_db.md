---
layout: page
title: "Inside Aqueduct's ORM"
category: db
date: 2016-06-20 10:35:56
order: 4
---

Aqueduct applications use a number of objects to facilitate integrating with a database. Your application code will create instances of `Query<T>` that get executed against a `ManagedContext`. A `ManagedContext` uses an instance of a `PersistentStore` to map queries to a specific database flavor. The data returned from a database is then mapped into `ManagedObject<T>` objects by the `ManagedContext`. The context is able to performing this mapping with its instance of `ManagedDataModel`, which contains `ManagedEntity`s that represent the model objects in your application.

### ModelContext is the Bridge from Aqueduct to a Database

An instance of a `ManagedContext` is necessary for interaction with a database. It is the interface between your application code and a database. When you execute a `Query<T>`, that query is executed on a specific instance of `ManagedContext`. A `ManagedContext` will take the results of a `Query<T>` and map them back to managed objects. Most applications will only have one `ManagedContext`. (Applications that talk to more than one database or different schemas within a database will have more.) A `ManagedContext` uses a `PersistentStore` and `ManagedDataModel` to translate `ManagedObject<T>` objects to and from database rows and `Query<T>` objects to and from SQL.

Because most applications only have one `ManagedContext`, there is a default context for every application. If you are only creating a single `ManagedContext` in an application, that context is set to be the default context without any further action. By default, a new `Query<T>` will run on the default context of an application. The default context can be changed, but this is rarely done:

```dart
ManagedContext.defaultContext = new ManagedContext(dataModel, persistentStore);
```

Contexts are typically instantiated in a `RequestSink`'s constructor or some other point in an application's startup process. Contexts are rarely accessed directly after they are created.  A `Query<T>`, when executed, will work with private methods on a context to carry out its job. A context must be instantiated with a `ManagedDataModel` and `PersistentStore`, and the context effectively coordinates these two objects to carry out its tasks.

### ManagedDataModels Describe an Application's ManagedEntities

Instances of `ManagedDataModel` are one of the two components of a `ManagedContext`. A `ManagedDataModel` has a definition for all of the managed objects in a particular context. In most applications, this means every `ManagedObject<T>` subclass you declare in your application. The `ManagedDataModel` will create instances of `ManagedEntity` to describe each `ManagedObject<T>`. In other words, a `ManagedDataModel` compiles your data model into entities that contain information at runtime to map data back and forth between a database.

`ManagedEntity`s are the description of a database table in your application.  A `ManagedEntity` contains references to the two types that make up a fully formed entity - the subclass of `ManagedObject<T>` and its persistent type. They also contain the information derived from these types - the attributes and relationships - into a more readily available format.

`ManagedEntity`s store relationship and attribute information in instances of `ManagedRelationshipDescription` and `ManagedAttributeDescription`, both of which extend `ManagedPropertyDescription`. This information is used by the rest of Aqueduct to determine how database rows and model objects are translated back and forth. This information is derived from the class declarations, and `ColumnAttributes` and `ManagedRelationship` metadata that is used when defining your managed object classes.

A `ManagedDataModel` will also validate all entities and their relationships. If validation fails, an exception will be thrown. As `ManagedDataModel`s are created at the beginning of the application's startup, this behavior will stop your application from running if there are data model errors.

### Persistent Stores Handle Database Queries

`Query<T>`s created in an Aqueduct application are database-agnostic. They are defined in the domain of your `ManagedDataModel` and its `ManagedEntity`s. A `PersistentStore` is responsible for translating a `Query<T>` into a specific flavor of SQL and execute that query against a remote database. A `ManagedContext` uses a `PersistentStore` to carry out data transmission.

`PersistentStore` is an abstract class. To connect to and interact with a specific flavor of SQL - like PostgreSQL o'r MySQL - a flavor-specific implementation of `PersistentStore` must exist. By default, Aqueduct ships with a `PostgreSQLPersistentStore`. A persistent store implementation does the actual translation from Aqueduct `Query<T>`s to a SQL query. It also manages a database connection and the transmission of data between your application and a database instance.

There is nothing that prevents a `PersistentStore` implementation from connecting to and working with a NoSQL database, but the interface is certainly more geared towards SQL databases.

`PersistentStore`s are rarely used directly. Instead, a `ManagedContext` has a persistent store that it uses to coordinate database queries. Prior to sending a `Query<T>` to a persistent store, a `ManagedContext` will transform a `Query<T>` into a `PersistentStoreQuery`. `PersistentStoreQuery`s are effectively the 'compiled' version of a `Query<T>`.

`PersistentStore`s may be used directly to issue direct SQL to its underlying database connection. This is often useful for scripts and tests that modify a database schema. For this purpose, `PersistentStore` has an `execute` method to run raw SQL.
