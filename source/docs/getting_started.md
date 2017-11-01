# Getting Started with Aqueduct

## Installation

1. [Install Dart](https://www.dartlang.org/install).
2. Activate the Aqueduct CLI

        pub global activate aqueduct

3. Create a new project.

        aqueduct create my_project

Open the project directory in an [IntelliJ IDE](https://www.jetbrains.com/idea/download/), [Atom](https://atom.io) or [Visual Studio Code](https://code.visualstudio.com). All three IDEs have a Dart plugin.

## How to Learn Aqueduct

There are different approaches depending on how you prefer to learn.

* The [guided tutorial](tut/getting-started.md) is a hands-on walkthrough where you build an application while learning basic Aqueduct concepts.
* The [example repository](https://github.com/stablekernel/aqueduct_examples) contains a few deployable applications that you may review or tinker with.
* The guides (located in the menu on this website) dive deeply into the concepts of Aqueduct and show example code.
* [Creating a new project](#creating-a-project) and using the [API reference](http://dartdocs.org/documentation/aqueduct/latest/) to jump right in.

It is best to first understand how HTTP requests are responded to - the foundation of Aqueduct - before moving on to topics such as the ORM and OAuth 2.0. Both the tutorial and the [HTTP guides](http/overview.md) are the primary source of this information. A project created by the `aqueduct` tool has example routes connected for modification, too.

## Creating a Project

The `aqueduct create` command-line tool creates new Aqueduct project directories. The default template contains the minimal project structure for running an Aqueduct application. A project name must be snake_case.

```
aqueduct create my_project_name
```

Other templates exist that contain foundational code for using Aqueduct's ORM and OAuth 2.0 implementation. These templates can be listed:

```
aqueduct create list-templates
```

You may provide the name of a template when creating a project to use that template:

```
aqueduct create -t db my_project_name
```

## Using the Aqueduct ORM

Aqueduct's ORM uses PostgreSQL. During development, you will need a locally running instance of PostgreSQL. On macOS, installing  [Postgres.app](https://postgresapp.com) is a very convenient way to run PostgreSQL locally. For other platforms, see [PostgreSQL's downloads page](https://www.postgresql.org/download/).

When creating a project, use the `db` template. If adding to an existing project, see [this guide](db/connecting.md).

To create a database, make sure PostgreSQL is running and open the command-line utility to connect to it.

```
psql
```

Then, create a database that your application will connect to and a user that it will connect with:

```sql
CREATE DATABASE my_database_name;
CREATE USER dart_app WITH PASSWORD 'dart';
GRANT ALL ON DATABASE my_database_name TO dart_app;
```

An application must create a `ManagedContext` that connects to this database:

```dart
class MyChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var store = new PostgreSQLPersistentStore.fromConnectionInfo(
      "dart_app", "dart", "localhost", 5432, "my_database_name");
    ManagedContext.defaultContext = new ManagedContext(dataModel, store);
  }

  ...
}
```

Once you have declared `ManagedObject`s in your application, generate the database schema by generating and executing migrations from your project's directory:

```
aqueduct db generate
aqueduct db upgrade --connect postgres://dart_app:dart@localhost:5432/my_database_name
```

See the guides on [connecting to a database](db/connecting.md) and [testing with a database](testing/database.md)
