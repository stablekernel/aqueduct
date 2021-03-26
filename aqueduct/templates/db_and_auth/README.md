# wildfire

## Database

You will need a local database for testing, and another database for running the application locally. The behavior and configuration of these databases are documented here: http://aqueduct.io/docs/testing/mixins/.

To run tests, you must have a configuration file named `config.src.yaml`. By default, it is configured to connect your application to a database named `dart_test` (documented in the link above) and should not need to be edited. Tables are automatically created and deleted during test execution.

To run your application locally, you must have a `config.yaml` file that has correct database connection info, which should point to a local database specific to your application (documented in link above).
When running locally, you must apply database migrations to your database before using it. The following commands generate a migration file from your project and then apply it to a database. Replace your database's connection details with the details below.

```
aqueduct db generate
aqueduct db upgrade --connect postgres://dart:dart@localhost:5432/wildfire
```

### Configure OAuth

To run your application locally, you must also register OAuth 2.0 clients in the application database. Use the same database credentials after you have applied the migration.

```
aqueduct auth add-client --id com.local.test \
    --secret mysecret \
    --connect postgres://user:password@localhost:5432/wildfire
```

To run your tests with OAuth 2.0 client identifiers, see this documentation: http://aqueduct.io/docs/testing/mixins/#testing-applications-that-use-oauth-20.

## Running the server locally

Run `aqueduct serve` from this directory to run the application. For running within an IDE, run `bin/main.dart`.

## Running CURL commands to test the end points

The following CURL commands are valid HTTP requests for the routes configured by generating this project. If you get a 503 error, your application is not connecting to the database.

### Endpoints Requiring Client Authentication

Endpoints that are not associated with a user must have client authentication using the credentials added with `aqueduct auth`. These routes are `POST /register` and `POST /auth/token`.

The client id and client secret are combined into a colon (`:`) delimited string, then base64 encoded and added as a `Basic` authorization header. For example, the client id `com.local.test` and secret `mysecret` is combined into `com.local.test:mysecret` then base64 encoded. The header `Authorization: Basic $base64Credentials` must be added to each endpoint requiring this type of authentication.

### Register a user (POST /register)

To register a new user, send a `POST /register` request. Use the following CURL command and replace the `<username>` and `<password>` with your new user and `base64Client` with your base64 encoded client credentials.

`curl -X POST http://localhost:8888/register -H 'Authorization: Basic <base64Client>=' -H 'Content-Type: application/json' -d '{"username":"<username>", "password": "<password>"}' -v`

You should see a response similar to this:

```JSON
{"id":3,"username":"marilyn","authorization":{"access_token":"cUXqbTn0DIogyzq80jl2FHmCBa8BvIAyww","token_type":"bearer","expires_in":86399,"refresh_token":"26o8xEOVKBfFvB3jg0rH8qnF2wWV9QBp"}}

```

For the next step, we will need the `access_token` from your response.

### Get User Profile (GET /me)

To get information about the user who was issued an access token:

```
curl -X GET http://localhost:8888/me -H 'Authorization: Bearer <access_token>'
```

Notice the Authorization header is `Bearer <token>` (not the base64 encoded client credentials). You should see a response similar to this:

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
curl -X GET http://localhost:8888/users -H 'Authorization: Bearer <access_token>'
```

You should have a response similar to the following. Note that the JSON object is contained in a Array.

```JSON
[{"id":1,"username":"marilyn"}]
```

### Update a User (PUT /users/[:id])

For this example, we will update our User. We can only update our own user. So we will need two things to be in sync, the `id` of the user and the `access_token` for that user.

Here is the CURL command:

```
curl -X PUT http://localhost:8888/users/1 -H 'Authorization: Bearer <access_token>'  -H "Content-Type: application/json" -d '{"username": "bob roy"}'
```

You should see a response similar to the following:

```JSON
{"id":1,"username":"bob roy"}
```

### Delete a User (DELETE /users/[:id])

For this example, we will delete our User. We can only delete our own user. So we will need 2 things to be in sync, the `id` of the user and the `access_token` for that user.

```
curl -X GET http://localhost:8888/users/1 -H 'Authorization: Bearer <access_token>'
```

For this command, there is no CURL output. To validate the record is deleted, try fetching it again with `GET /users/1`.

### Get a Auth Token for a User (POST /auth/token)

This is a 'login' request that requires a user to already be registered. Client credentials are provided in the Authorization header, and user credentials in the body (in the query string format, not JSON).

```
curl -X POST http://localhost:8888/auth/token -H 'Authorization: Basic <access_token>' -H 'Content-Type: application/x-www-form-urlencoded' -d 'username=<username>>&password=<password>&grant_type=password'

```

You should see a response similar to the following:

```JSON
{"access_token":"kliJ8X6Rf9OCw31qbkTFzZhwBQ5n5MgA","token_type":"bearer","expires_in":86399,"refresh_token":"73Awjp9zzTWnmEGnuz7hIBFBaXahFPLt"}
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
