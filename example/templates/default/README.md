# wildfire

An application built with [aqueduct](https://github.com/stablekernel/aqueduct).

## First Time Setup

### If you are running on macOS:

You will need to install [Postgres.app](http://postgresapp.com). Install and run Postgres.app. From the Postgres status menu item (the elephant icon in the top menu, near your date & time), select 'Open psql'. This will launch a terminal window connected to the local database. Run the following commands to create a user and a database for your application's test to run against (keep the username, password and database name the same as this example to avoid later confusion):

    create database dart_test;
    create user dart with createdb;
    alter user dart with password 'dart';
    grant all on database dart_test to dart;

Note that you must open Postgres.app for the test database to be accessible in the future, so adding it to your Startup Items is helpful.

## Running Tests

Run the following command in this directory to run all of the tests:

```
pub run test -j 1
```

## Creating API Documentation

Run the following script from this directory to generate an OpenAPI 3.0 JSON specification file for your web server:

```
dart bin/document.dart
```

This will print the JSON file to stdout.

## Generating the Database Schema

Run the following script from this directory to generate a PostgreSQL command list for generating a schema for your web server:
 
 ```
 dart bin/schema.dart
 ```
 
This will print the list of commands to stdout. 

## Running wildfire

Ensure that a `config.yaml` file exists in this directory. The keys in `config.yaml.src` must exist in `config.yaml` and have values configured for your environment.
 
Then, start the server with the following command from this directory:

    sh restart.sh
