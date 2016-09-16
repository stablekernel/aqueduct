## The Layers Between Aqueduct and Your Database

Aqueduct applications use a number of objects to facilitate integrating with a database. Your application code will create instances of `Query` that get executed against a `ModelContext`. A `ModelContext` uses an instance of a `PersistentStore` to map queries to a specific database flavor. The data returned from a database is then mapped into `Model` objects by the `ModelContext`. The context is able to performing this mapping with its instance of `DataModel`, which contains `ModelEntity`s that represent the model objects in your application.

### ModelContext is the Bridge from Aqueduct to a Database

An instance of a `ModelContext` is necessary for interaction with a database. It is the interface between your application code and a database. When you execute a `Query`, that query is executed on a specific instance of `ModelContext`. A `ModelContext` will take the results of a `Query` and map them back to model objects. Most applications will only have one `ModelContext`. (Applications that talk to more than one database or different schemas within a database will have more.) A `ModelContext` is responsible for using a `PersistentStore` and `DataModel` to translate `Model` object to and from database rows and `Query` objects to and from SQL.

Because most applications only have one `ModelContext`, there is a default context for every application. If you are only creating a single `ModelContext` in an application, that context is set to be the default context without any further action. By default, a new `Query` will run on the default context of an application. The default context can be changed, but this is rarely done:

```dart
ModelContext.defaultContext = new ModelContext(dataModel, persistentStore);
```

Contexts are typically instantiated in a `ApplicationPipeline`'s constructor or some other point in an application's startup process. Contexts are rarely accessed directly after they are created.  A `Query`, when executed, will work with private methods on a context to carry out its job. A context must be instantiated with a `DataModel` and `PersistentStore`, and the context effectively coordinates these two objects to carry out its tasks.

### DataModels Describe an Application's Entities

Instances of `DataModel` are one of the two components of a `ModelContext`. A `DataModel` has a definition for all of the model objects that can be interacted with in a particular context. In most applications, this means every model/persistent type pair you declare in your application. `DataModels` are instantiated with a `List` of model types. The `DataModel` will create instances of `ModelEntity` to describe each model type it is given. In other words, a `DataModel` compiles your model class declarations into entities that contain information at runtime to map data back and forth between a database.

`ModelEntity`s are the description of a database table in your application.  A `ModelEntity` contains references to the two types that make up an fully formed entity. They also contain the information derived from these types - the attributes and relationships - into a more readily available format.

`ModelEntity`s store relationship and attribute information in instances of `RelationshipDescription` and `AttributeDescription`, both of which extend `PropertyDescription`. This information is used by the rest of Aqueduct to determine how database rows and model objects are translated back and forth. This information is derived from persistent and model type declarations, and `AttributeHint`s and `RelationshipInverse` metadata that is used when defining your model classes.

A `DataModel` will also validate all entities and their relationships. If validation fails, an exception will be thrown. As `DataModel`s are created at the beginning of the application's startup, this behavior will stop your application from running if there are data model errors.

### Persistent Stores Handle Database Queries

`Query`s created in an Aqueduct application are database-agnostic. They are defined in the domain of your `DataModel` and its `ModelEntity`s. A `PersistentStore` is responsible for translating a `Query` into a specific flavor of SQL and execute that query against a remote database. A `ModelContext` uses a `PersistentStore` to carry out data transmission.

`PersistentStore` is an abstract class. To connect to and interact with a specific flavor of SQL - like PostgreSQL or MySQL - a flavor-specific implementation of `PersistentStore` must exist. By default, Aqueduct ships with a `PostgreSQLPersistentStore`. A persistent store implementation does the actual translation from Aqueduct `Query`s to a SQL query. It also manages a database connection and the transmission of data between your application and a database instance.

There is nothing that prevents a `PersistentStore` implementation from connecting to and working with a NoSQL database, but the interface is certainly more geared towards SQL databases.

`PersistentStore`s are not used directly. Instead, a `ModelContext` has a persistent store that it uses to coordinate database queries. Prior to sending a `Query` to a persistent store, a `ModelContext` will transform a `Query` into a `PersistentStoreQuery`. `PersistentStoreQuery`s are effectively the 'compiled' version of a `Query`. There is no reason to use a `PersistentStoreQuery` directly.
