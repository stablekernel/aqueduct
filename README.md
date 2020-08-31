##  Added support for MySQL database （2020/4/25）

1. example:

``` shell
aqueduct db upgrade --connect mysql://username:password@host:port/databaseName
```

 or setting `database.yaml`:

 ``` yaml
 schema: postgres|mysql
 host: host
 port: port
 username: username
 password: password
 databaseName: databaseName
 ```

2.  `MySqlPersistentStore`:

``` dart
 final MySqlPersistentStore persistentStore = MySqlPersistentStore(
        _config.database.username,
        _config.database.password,
        _config.database.host,
        _config.database.port,
        _config.database.databaseName);

    context = ManagedContext(dataModel, persistentStore);

    /// ......
    final query = Query<User>(context,values: user)
      ..where((o) => o.username).equalTo(user.username);

    final res = await query.delete();
   /// ......
```
3. Support setting field size

``` dart
class _User extends ResourceOwnerTableDefinition {
  @Column(size: 11)
  String mobile;

  @override
  @Column(unique: true, indexed: true, size: 20)
  String username;
}

```



![Aqueduct](https://s3.amazonaws.com/aqueduct-collateral/aqueduct.png)

[![OSX/Linux Build Status](https://travis-ci.org/stablekernel/aqueduct.svg?branch=master)](https://travis-ci.org/stablekernel/aqueduct) [![Windows Build status](https://ci.appveyor.com/api/projects/status/l2uy4r0yguhg4pis?svg=true)](https://ci.appveyor.com/project/joeconwaystk/aqueduct) [![codecov](https://codecov.io/gh/stablekernel/aqueduct/branch/master/graph/badge.svg)](https://codecov.io/gh/stablekernel/aqueduct) 

[![Slack](https://slackaqueductsignup.herokuapp.com/badge.svg)](http://slackaqueductsignup.herokuapp.com/)

Aqueduct is a modern Dart HTTP server framework. The framework is composed of libraries for handling and routing HTTP requests, object-relational mapping (ORM), authentication and authorization (OAuth 2.0 provider) and documentation (OpenAPI). These libraries are used to build scalable REST APIs that run on the Dart VM.

If this is your first time viewing Aqueduct, check out [the tour](https://aqueduct.io/docs/tour/).

## Getting Started

1. [Install Dart](https://www.dartlang.org/install).
2. Activate Aqueduct

        pub global activate aqueduct

3. Create a new project.

        aqueduct create my_project

Open the project directory in [IntelliJ IDE](https://www.jetbrains.com/idea/download/), [Atom](https://atom.io) or [Visual Studio Code](https://code.visualstudio.com). All three IDEs have a Dart plugin. For IntelliJ IDEA users, there are [file and code templates](https://aqueduct.io/docs/intellij/) for Aqueduct.

## Tutorials, Documentation and Examples

Step-by-step tutorials for beginners are available [here](https://aqueduct.io/docs/tut/getting-started).

You can find the API reference [here](https://www.dartdocs.org/documentation/aqueduct/latest) or you can install it in [Dash](https://kapeli.com/docsets#dartdoc).

You can find in-depth and conceptual guides [here](https://aqueduct.io/docs/).

An ever-expanding repository of Aqueduct examples is [here](https://github.com/stablekernel/aqueduct_examples).
