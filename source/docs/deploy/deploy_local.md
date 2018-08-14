# Deploying an Aqueduct Application on a Local Machine

For other deployment options, see [Deploying Aqueduct Applications](index.md).

### Purpose

To run a local development version of an Aqueduct application with persistent storage. This is useful when developing client applications with an Aqueduct application. Make sure to also read [Testing Aqueduct Applications](../testing/index.md).

### Prerequisites

1. [Dart has been installed.](https://www.dartlang.org/install)
2. [PostgreSQL has been installed locally.](../getting_started.md)
2. [Aqueduct has been activated globally.](../getting_started.md)
3. [An application has been created with `aqueduct create`.](../getting_started.md)

If one or more of these is not true, see [Getting Started](../getting_started.md).

### Overview

1. Create a local database.
2. Upload the application schema to the local database.
3. Add an OAuth 2.0 client.
4. Modify the configuration file.
5. Run the application.

Estimated Time: 5 minutes.

### Step 1: Create a Local Database

Create a database with the same name as your application and a user that can access that database. Run the following SQL locally with a user that has privileges to create databases. (If using `Postgres.app`, open the `psql` terminal from the `Postgres.app` status menu item `Open psql`.)

```sql
CREATE DATABASE app_name;
CREATE USER app_name_user WITH CREATEDB;
ALTER USER app_name_user WITH PASSWORD 'yourpassword';
GRANT ALL ON DATABASE app_name TO app_name_user;
```

!!! warning "dart_test database"
    Do not use the name 'dart_test' for the database; this database is used by Aqueduct to run tests by default.

### Step 2: Upload the Application Schema

If you have not yet created database migration files for your project, run the database schema generation tool from the project directory:

```bash
aqueduct db generate
```

This command creates the file `migrations/00000001_initial.migration.dart`. Now, run the database migration tool to execute the migration file against the local database. Ensure that the values for the option `--connect` match those of the database created in the last step.

```bash
aqueduct db upgrade --connect postgres://app_name_user:yourpassword@localhost:5432/app_name
```

(Note that you may provide database credentials in a file named `database.yaml` instead of using `--connect`. See `aqueduct db --help` for details.)

### Step 3: Add an OAuth 2.0 client.

If you are using `package:aqueduct/managed_auth`, you'll want to create an OAuth2 client identifier. From the command line, run the following, ensuring that the values for the option `--connect` match the recently created database.

```bash
aqueduct auth add-client --id com.app_name.standard --secret abcdefghi --connect postgres://app_name_user:yourpassword@localhost:5432/app_name
```

### Step 4: Modify the Configuration File

If `config.yaml` doesn't exist, create it by copying the configuration file template `config.yaml.src`.

In `config.yaml`, update the database credentials to the local database.

```yaml
database:
 username: app_name_user
 password: yourpassword
 host: localhost
 port: 5432
 databaseName: app_name
```

### Step 5: Run the Application

From the project directory, run:

```bash
aqueduct serve
```

Your application is now running. You may also run the generated start script in your project's `bin` directory:

```bash
dart bin/main.dart
```

If you restart the application, the data in your database will remain.
