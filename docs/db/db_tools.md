# Database Migration and Tooling

The `aqueduct db` command line tool synchronizes the declared `ManagedObject<T>` classes in an application with the tables of a database.

Migration Files
---

In code, database tables are described by `ManagedObject<T>` subclasses and their persistent type. Migration files describe a series of database commands that will create or modify a database schema to match an application's `ManagedObject<T>`s. Migration files are generated and ran on a database when an application is first deployed. When changes to the data model occur - like new `ManagedObject<T>` subclasses or changing the name of a `ManagedObject<T>` property - a new migration file is generated and ran on the same database. The new migration file only contains the changes that were made, not every command to recreate the database schema from scratch. For this reason, migrations files should be stored in source control.

The `aqueduct db` tool's primary purpose is to create an execute migration files.

Generating Migration Files
---

Migration files - including the initial migration file - are created by running: `aqueduct db generate` in an Aqueduct application directory. This tool finds every `ManagedObject<T>` subclass in an application and adds commands to the migration file to create a database table that matches its declaration. When subsequent migration files are generated, the difference between the schema created by existing migration files is compared to the current schema declared in an application's code. The commands to rectify those differences are added to the new migration file.

This tool will find all `ManagedObject<T>` subclasses that are visible from an application's library file. (In an application named `foo`, the library file is `lib/foo.dart`.) As a convention, every `ManagedObject<T>` subclass is declared in its own file in `lib/model`. The file `lib/<application_name>_model.dart` exports all files in `lib/model`. The main library file exports `/lib/<application_name>_model.dart`. When new `ManagedObject<T>` subclasses are added to an application, they are exported in `lib/<application_name>_model.dart`. For example, an application named `wildfire` would have a directory structure like:

```
wildfire/
  lib/
    wildfire.dart
    wildfire_model.dart
    model/
      user.dart
      account.dart
    ...
```

The files `user.dart` and `account.dart` declare `ManagedObject<T>` subclasses and their persistent type. The file `wildfire.dart` then exports `wildfire_model.dart`:

```dart
export 'wildfire_model.dart';
```

And `wildfire_model.dart` exports the files in `model/`:

```dart
export 'model/user.dart';
export 'model/account.dart';
```

Migration files are stored in an application's `migrations` directory, which gets created when the tool is run if it doesn't exist. Migration files are prefixed with a version number, a "0" padded eight digit number. The version number of the file - and the order it will get executed in - is determined from this string. For example, the first migration file's version number is "00000001" and the second is "00000002". When removing the 0s, they are versions 1 and 2 and will be replayed in that order.

Migration files are always suffixed with `.migration.dart`. Migration files may have an additional name that has no impact on the file or its order by inserting an underscore after the version number:

```
00000001_initial.migration.dart
00000002_add_user_nickname.migration.dart
```

Validating Migration Files
---

Migration files may be altered after they have been generated. This is often the case if `aqueduct db generate` can't say for certain how a database should change. For example, is renaming a property just renaming a column, or is it deleting a column and creating a new column? The `aqueduct db validate` tool ensures that the database schema after running all migration files matches the database schema declared by an application's `ManagedObject<T>`s. Any generated migration file will pass `aqueduct db validate`. The validate tool will display every difference found in the schemas.


Listing Migration Files
---

Use `aqueduct db list` to list all database migration files and their resolved version number.

Executing Migration Files
---

The tool `aqueduct db upgrade` will apply migration files to a running database. This tool is run in an application's directory and finds migration files in the `migrations` directory. The connection info for a the running database is provided with the `--connect` option. For example, the following would execute migration files on a PostgreSQL database:

```
aqueduct db upgrade --connect postgres://username:password@localhost:5432/my_application
```

The first time `aqueduct db upgrade` is executed, it creates a version table that keeps the version number and dates of upgrades. When `aqueduct db upgrade` is ran after the initial migration, the version number is fetched from the database. The tool only runs migration files after the version number stored in the database.

Connection information can also be stored in a database configuration file named `database.yaml` in the application directory. If this file exists with the following format, `--connect` can be omitted and connection information will be read from this file:

```
username: "user"
password: "password"
host: "host"
port: port
databaseName: "database"
```

Getting a Database's Version
---

You can fetch a database's current version number with `aqueduct db get-version`. This command takes `--connect` or a `database.yaml` file as described in the previous section to get connection info for the database.


When to Execute Migration Files
---

During development, there is no need to create a migration file for each change. Execute migration files prior to deployment of a new version of an application.

You may delete migration files. When `aqueduct db generate` is run again, will replay only the existing migration files before determining which commands to add to the new migration file. For example, if you have 10 migration files over time and delete them all - the next generated migration file will contain commands to recreate the entire database schema.
