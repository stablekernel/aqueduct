import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'dart:isolate';
import 'dart:io';
import 'dart:async';

void main() {
  test("Success case", () {
    var yamlString =
        "port: 80\n"
        "name: foobar\n"
        "database:\n"
        "  user: bob\n"
        "  password: fred\n"
        "  name: dbname\n"
        "  port: 5000";

    var t = new TopLevelConfiguration(yamlString);
    expect(t.port, 80);
    expect(t.name, "foobar");
    expect(t.database.user, "bob");
    expect(t.database.password, "fred");
    expect(t.database.name, "dbname");
    expect(t.database.port, 5000);
  });

  test("Missing required top-level explicit", () {
    try {
      var yamlString =
          "name: foobar\n"
          "database:\n"
          "  user: bob\n"
          "  password: fred\n"
          "  name: dbname\n"
          "  port: 5000";

      var _ = new TopLevelConfiguration(yamlString);
    } on ConfigurationException catch (e) {
      expect(e.message, "port is required but was not found in configuration.");
    } catch (e) {
      expect(true, false, reason: "Should not reach here");
    }
  });

  test("Missing required top-level implicit", () {
    try {
      var yamlString =
          "port: 80\n"
          "name: foobar\n";
      var _ = new TopLevelConfiguration(yamlString);
    } on ConfigurationException catch (e) {
      expect(e.message, "database is required but was not found in configuration.");
    } catch (e) {
      expect(true, false, reason: "Should not reach here");
    }
  });

  test("Optional can be missing", () {
    var yamlString =
        "port: 80\n"
        "database:\n"
        "  user: bob\n"
        "  password: fred\n"
        "  name: dbname\n"
        "  port: 5000";

    var t = new TopLevelConfiguration(yamlString);
    expect(t.port, 80);
    expect(t.name, isNull);
    expect(t.database.user, "bob");
    expect(t.database.password, "fred");
    expect(t.database.name, "dbname");
    expect(t.database.port, 5000);
  });

  test("Nested optional can be missing", () {
    var yamlString =
        "port: 80\n"
        "name: foobar\n"
        "database:\n"
        "  password: fred\n"
        "  name: dbname\n"
        "  port: 5000";

    var t = new TopLevelConfiguration(yamlString);
    expect(t.port, 80);
    expect(t.name, "foobar");
    expect(t.database.user, isNull);
    expect(t.database.password, "fred");
    expect(t.database.name, "dbname");
    expect(t.database.port, 5000);
  });

  test("Nested required cannot be missing", () {
    try {
      var yamlString =
          "port: 80\n"
          "name: foobar\n"
          "database:\n"
          "  password: fred\n"
          "  port: 5000";

      var _ = new TopLevelConfiguration(yamlString);
    } on ConfigurationException catch (e) {
      expect(e.message, "name is required but was not found in configuration.");
    } catch (e) {
      expect(true, false, reason: "Should not reach here");
    }
  });

  test("Map and list cases", () {
    var yamlString =
        "strings:\n"
        "-  abcd\n"
        "-  efgh\n"
        "databaseRecords:\n"
        "- name: db1\n"
        "  port: 1000\n"
        "- user: bob\n"
        "  name: db2\n"
        "  port: 2000\n"
        "integers:\n"
        "  first: 1\n"
        "  second: 2\n"
        "databaseMap:\n"
        "  db1:\n"
        "    name: db1\n"
        "    port: 1000\n"
        "  db2:\n"
        "    user: bob\n"
        "    name: db2\n"
        "    port: 2000\n";

    var special = new SpecialInfo(yamlString);
    expect(special.strings, ["abcd", "efgh"]);
    expect(special.databaseRecords.first.name, "db1");
    expect(special.databaseRecords.first.port, 1000);
    expect(special.databaseRecords.last.user, "bob");
    expect(special.databaseRecords.last.name, "db2");
    expect(special.databaseRecords.last.port, 2000);
    expect(special.integers["first"], 1);
    expect(special.integers["second"], 2);
    expect(special.databaseMap["db1"].name, "db1");
    expect(special.databaseMap["db1"].port, 1000);
    expect(special.databaseMap["db2"].user, "bob");
    expect(special.databaseMap["db2"].name, "db2");
    expect(special.databaseMap["db2"].port, 2000);
  });

  test("DatabaseConfig", () {
    var yamlString =
        "database:\n"
        "  username: bob\n"
        "  password: fred\n"
        "  host: localhost\n"
        "  databaseName: dbname\n"
        "  port: 5000";
    var d = new ConstructorWrapper(yamlString);
    expect(d.database.databaseName, "dbname");
    expect(d.database.username, "bob");
    expect(d.database.host, "localhost");
    expect(d.database.password, "fred");
    expect(d.database.port, 5000);
  });
}

class TopLevelConfiguration extends ConfigurationItem {
  TopLevelConfiguration(String contents) {
    loadConfigurationFromString(contents);
  }

  @requiredConfiguration
  int port;

  @optionalConfiguration
  String name;

  DatabaseInfo database;
}

class DatabaseInfo extends ConfigurationItem {
  @optionalConfiguration
  String user;
  @optionalConfiguration
  String password;
  String name;
  int port;
}

class SpecialInfo extends ConfigurationItem {
  SpecialInfo(String contents) {
    loadConfigurationFromString(contents);
  }
  List<String> strings;
  List<DatabaseInfo> databaseRecords;
  Map<String, int> integers;
  Map<String, DatabaseInfo> databaseMap;
}

class ConstructorWrapper extends ConfigurationItem {
  ConstructorWrapper(String contents) {
    loadConfigurationFromString(contents);
  }

  DatabaseConnectionConfiguration database;
}