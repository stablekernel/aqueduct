# Deploying an Aqueduct Application on a Local Machine

For other deployment options, see [Deploying Aqueduct Applications](index.md).

### Purpose

To run a local development version of an Aqueduct application with persistent storage. This is useful in developing client applications against an Aqueduct application. Make sure to also read [Testing Aqueduct Applications](../testing/index.md).


### Prerequisites

1. [Dart has been installed.](https://www.dartlang.org/install)
2. [PostgreSQL has been installed locally.](../index.md#getting_started)
2. [Aqueduct has been activated globally.](../index.md#getting_started)
3. [An application has been created with `aqueduct create`.](../index.md#getting_started)

If one or more of these is not true, see [Getting Started](../index.md#getting_started).

### Overview

1. Create a local database.
2. Upload the application schema to the local database.
3. Add an OAuth 2.0 client.
4. Modify the configuration file.
5. Run the application.

Estimated Time: <5 minutes.

### Step 1: Create a Local Database

Create a database with the same name as your application and a user that can access that database. Do not use the name 'dart_test' for the database; this database is used by Aqueduct to run tests by default.

Run the following SQL locally with a user that has privileges to create databases. (If using `Postgres.app`, open the `psql` terminal from the `Postgres.app` status menu item `Open psql`).

```sql
CREATE DATABASE app_name;
CREATE USER app_name_user WITH CREATEDB;
ALTER USER app_name_user WITH PASSWORD 'yourpassword';
GRANT ALL ON DATABASE app_name TO app_name_user;
```

### Step 2: Upload the Application Schema

Run the database schema generation tool from the project directory:

```bash
aqueduct db generate
```

This command creates the file `migrations/00000001_Initial.migration.dart`. Now, run the database migration tool to execute the migration file against the local database. Ensure that the values for the option `--connect` match those of the database created in the last step.

```bash
aqueduct db upgrade --connect postgres://app_name_user:yourpassword@localhost:5432/app_name
```

(Note that you may provide database credentials in a file named `database.yaml` instead of using `--connect`. See `aqueduct db --help` for details.)

### Step 3: Add an OAuth 2.0 client.

From the command line, run the following, ensuring that the values for the option `--connect` match the recently created database.

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

Your application is now running.

Note: You can add the `--observe` flag to `aqueduct serve` to run Observatory. Observatory will automatically open in a browser if the platform supports it.
