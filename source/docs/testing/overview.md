## Tasks

Aqueduct applications can be run, tested, debugged and profiled.

Using these test utilities requires adding `aqueduct_test` to your `pubspec.yaml` `dev_dependences`. By default, applications created with the template include this dependency.

An example `pubspec.yaml` for an application looks like this:

```yaml
name: wildfire
description: An Aqueduct application with a database connection and data model.
version: 1.0.0

environment:
  sdk: ^2.0.0

dependencies:
  aqueduct: ^3.0.0

dev_dependencies:
  test: '>=0.12.0 <0.13.0'
  aqueduct_test: ^1.0.0  
```

## Guides

- [Best Practices for Aqueduct Development](best_practices.md)
- [Using a Local Database](database.md)
- [Developing Client Applications](clients.md)
- [Using the Debugger and Profiling](debugger.md)
- [Writing Tests](tests.md)
- [Use Mock Services](mock.md)
