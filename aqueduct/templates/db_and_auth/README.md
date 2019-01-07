# wildfire

## Project creation

To use this template, from the command line, enter `aqueduct create -t db_and_auth <project name>`. This document will assume that project was created w/ the name `wildfire`.

## Database

For ease, use the same db name as the tests. The tests are run with a local PostgreSQL database named `dart_test`. If this database does not exist, create it from your SQL prompt.

```
CREATE DATABASE dart_test;
CREATE USER dart WITH createdb;
ALTER USER dart WITH password 'dart';
GRANT all ON DATABASE dart_test TO dart;
```

## Running the Application Locally

Run `aqueduct serve` from this directory to run the application. For running within an IDE, run `bin/main.dart`.

You must have a `config.yaml` file that has correct database connection info, which should point to a local database. To configure a database to match your application's schema, run the following commands:

## OAuth 2.0 Setup

```
# Note: if this is a new project, run db generate first, assuming you setup the `dart_test` db with `userid:password` of `dart:dart`.
aqueduct db generate
aqueduct db upgrade --connect postgres://dart:dart@localhost:5432/wildfire
```

You must also configure OAuth 2.0 Client identifiers in this database.

```
aqueduct auth add-client --id com.local.test \
    --secret mysecret \
    --connect postgres://user:password@localhost:5432/wildfire
```

## Running CURL commands to test the end points

The following CURL commands will be hitting the end points that are defined in `channel.dart`.

### Getting the Base64Encoding string

Notice above that we have an `id` of `com.local.test` and a `secret` of `mysecret`. We will need the Base64Encoding of these values for use within the CURL scripts. For now, you can use [https://www.base64encode.org/](https://www.base64encode.org/) to generate the encoding.

The pattern for the input string is `id:secret`. Using the `id` and `secret` from above, our input string is `com.local.test:mysecret`.

Copy that string, `com.local.test:mysecret`, to the Base64Encoding page. Set the Destination charset to `UTF-8` and clidk the Encode> button. You should see the result of `Y29tLmxvY2FsLnRlc3Q6bXlzZWNyZXQ=`

### Register a user (POST /register)

To register a new user, we will hit the `/register` end point as defined in `channel.dart`. Use the following CURL command and replace the <username> and <password> with your own.

Notice how the Base64Encoding from above is referenced. If you changed the `id` or `secret` above then you will need to update this Base4Encoding with your particular value.

`curl -X POST http://localhost:8888/register -H 'Authorization: Basic Y29tLmxvY2FsLnRlc3Q6bXlzZWNyZXQ=' -H 'Content-Type: application/json' -d '{"username":"<username>", "password": "<password>"}' -v`

You should see a response similar to this:

```JSON
{"id":3,"username":"marilyn","authorization":{"access_token":"cUXqbTn0DIogyzq80jl2FHmCBa8BvIAyww","token_type":"bearer","expires_in":86399,"refresh_token":"26o8xEOVKBfFvB3jg0rH8qnF2wWV9QBp"}}

```

For the next step, we will need the `access_token`, namely `cUXqbTn0DIogyzq80jl2FHmCBa8BvIAyww` from above. Note that when you run this, you will have a different `access_token`.

### Read me (GET /me)

To read information about yourself, once you have the `access_token` from the previous step above, you can run this CURL:

```
curl -X GET http://localhost:8888/me -H 'Authorization: Bearer cUXqbTn0DIogyzq80jl2FHmCBa8BvIAy'
```

You should see a response similar to this:

```JSON
{"id":1,"username":"marilyn"}
```

### Read a specific User (GET /users/[:id])

For this example, we will use the end point `/users/[:id]`. In our example, our first user was `marilyn` and the record was created with the `id` of `1`. Again, referencing the `access_token` from above, we have this CURL:

```
curl -X GET http://localhost:8888/users/1 -H 'Authorization: Bearer cUXqbTn0DIogyzq80jl2FHmCBa8BvIAy'
```

You should see a response similar to this:

```JSON
{"id":1,"username":"marilyn"}
```

### Read all users (GET /users)

For this example, we will be hitting the same end point as above, namely `/users/[:id]` but we will not provide the `id`. By doing so, we will retrieve all the Users. Again, we will reference the `access_token` from above. We now have this CURL:

```
curl -X GET http://localhost:8888/users -H 'Authorization: Bearer cUXqbTn0DIogyzq80jl2FHmCBa8BvIAy'
```

You should have a response similar to this (assuming you Registered 2 other users, `barton` and `bob`). Note that the JSON objects are contained in a Array.

```JSON
[{"id":1,"username":"marilyn"},{"id":2,"username":"barton"},{"id":3,"username":"bob"}]
```

### Get a Auth Toke for a User (POST /auth/token)

For this example, we will hit the `/auth/token` end point. Now we won't be using the `access_token` but rather the Base64Encoding that we generated earlier, namely the value of `Y29tLmxvY2FsLnRlc3Q6bXlzZWNyZXQ=`. This request requires that the "username" and "password" are passed in for an **existing** user. In our example, we currently have the user `marilyn`. Here is the CURL:

```
curl -X POST http://localhost:8888/auth/token -H 'Authorization: Basic Y29tLmxvY2FsLnRlc3Q6bXlzZWNyZXQ=' -H 'Content-Type: application/x-www-form-urlencoded' -d 'username=marilyn&password=password&grant_type=password'

```

You should see a response similar to the following:

```JSON
{"access_token":"kliJ8X6Rf9OCw31qbkTFzZhwBQ5n5MgA","token_type":"bearer","expires_in":86399,"refresh_token":"73Awjp9zzTWnmEGnuz7hIBFBaXahFPLt"}
```

### Get an HTML Form (GET /auth/form)

For this example, we will hit the `/auth/form` end point. The response from this call is an HTML Form that could be presented to a user to log in. Here is the CURL:

```
curl -X GET  http://localhost:8888/auth/form?response_type=token
```

You should see a response similar to the following:

```HTML
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <title>Login</title>
</head>

<body>
<div class="container">
    <h1>Login</h1>
    <form action="/auth/form" method="POST">
        <input type="hidden" name="state" value="null">
        <input type="hidden" name="client_id" value="null">
        <input type="hidden" name="response_type" value="token">
        <div class="form-group">
            <label for="username">User Name</label>
            <input type="text" class="form-control" name="username" placeholder="Please enter your user name">
        </div>
        <div class="form-group">
            <label for="password">Password</label>
            <input type="password" class="form-control" name="password" placeholder="Please enter your password">
        </div>
        <button type="submit" class="btn btn-success">Login</button>
    </form>
</div>
</body>

</html>
```

## Swqgger UI Client

To generate a SwaggerUI client, run `aqueduct document client`.

## Running Application Tests

To run all tests for this application, run the following in this directory. Remember, the tests assume the database to be `dart_test`.

```
pub run test
```

The default configuration file used when testing is `config.src.yaml`. This file should be checked into version control. It also the template for configuration files used in deployment.

## Deploying an Application

See the documentation for [Deployment](https://aqueduct.io/docs/deploy/).
