# wildfire

A project template generator for [aqueduct](https://github.com/stablekernel/aqueduct). 

## First Time Setup

There is no need to clone this repository. There are two steps to complete for first-time installation, assuming you have Dart installed.

First, from the terminal, run the following:

    pub global activate --source git https://github.com/stablekernel/wildfire.git

You will also need to install [Postgres.app](http://postgresapp.com). Install and run Postgres.app. From the Postgres status menu item (the elephant icon in the top menu, near your date & time), select 'Open psql'. This will launch a terminal window connected to the local database. Create a user and a database for your application's test to run against (keep the username, password and database name the same as this example to avoid later confusion):

    create database dart_test;
    create user dart with createdb;
    alter user dart with password 'dart';
    grant all on database dart_test to dart;
    
Note that you must open Postgres.app for the test database to be accessible in the future, so adding it to your Startup Items is helpful.

## Usage

To create a new project, run the following in your terminal:

    pub global run wildfire:ignite ProjectName
    
ProjectName may also be a path (the project will be created at that path, where the last path component is the name of the project) and should use camel case.
