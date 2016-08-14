# wildfire

An application built with [aqueduct](https://github.com/stablekernel/aqueduct).

## First Time Setup

You will need to install [Postgres.app](http://postgresapp.com). Install and run Postgres.app. From the Postgres status menu item (the elephant icon in the top menu, near your date & time), select 'Open psql'. This will launch a terminal window connected to the local database. Create a user and a database for your application's test to run against (keep the username, password and database name the same as this example to avoid later confusion):

    create database dart_test;
    create user dart with createdb;
    alter user dart with password 'dart';
    grant all on database dart_test to dart;

Note that you must open Postgres.app for the test database to be accessible in the future, so adding it to your Startup Items is helpful.

## Usage

Ensure that a config.yaml file exists in this directory with the same values as config.yaml.src.

To run this application, run the following command from this directory:

    sh restart.sh
