# The Aqueduct Setup Tool

The `aqueduct setup` tool is used for two tasks:

- Creating a local test database
- Modifying a project so that it can be deployed to Heroku.

During the initial setup of a development machine, after PostgreSQL has been installed locally, the following command creates a local database specifically for testing.

```
aqueduct setup
```

This creates a database user named `dart` with password `dart` and creates a database `dart_test` that `dart` has access to on the local machine.

For using `aqueduct setup` to deploy Heroku applications, see [this guide](../deploy/deploy_heroku.md).
