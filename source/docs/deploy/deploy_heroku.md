# Deploying an Aqueduct Application on Heroku

For other deployment options, see [Deploying Aqueduct Applications](index.md).

### Purpose

To run a production Aqueduct application on Heroku. Make sure to also read [Testing Aqueduct Applications](../testing/index.md).

### Prerequisites

1. [Dart has been installed.](https://www.dartlang.org/install)
2. [A Heroku account.](https://signup.heroku.com)
3. [`git` has been installed.](https://git-scm.com/downloads)
4. [`heroku` has been installed.](https://devcenter.heroku.com/articles/heroku-cli)
5. [Aqueduct has been activated.](../index.md#getting_started)

### Overview

1. Setting up a Heroku application
2. Setting up an Aqueduct application to run on Heroku
3. Configuring application values
4. Running the Aqueduct application

Estimated Time: 5 minutes.

### Step 1: Setting up a Heroku Application

Create a new application in Heroku. Add the 'Heroku Postgres' add-on.

Navigate to the Settings tab in the Heroku web interface and click 'Reveal Config Vars'. Note the DATABASE_URL, it'll get used later.

### Step 2: Setting up an Aqueduct Application to Run on Heroku

If you have not yet, create a new Aqueduct application on your local machine, go into that directory, and initialize it as a git repository if it is not already:

```bash
aqueduct create app_name
cd app_name
git init
```

Run the following commands to configure your project in Heroku's environment.

!!! warning "Heroku Application Name"
    In the following commands, ensure that `app_name` is the name of your *Heroku application* created in their web portal, not the name of your Aqueduct application.


```bash
heroku login
heroku git:remote -a app_name
heroku config:set DART_SDK_URL=https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip
heroku config:add BUILDPACK_URL=https://github.com/stablekernel/heroku-buildpack-dart.git
heroku config:set PATH=/app/bin:/usr/local/bin:/usr/bin:/bin:/app/.pub-cache/bin:/app/dart-sdk/bin
heroku config:set PUB_CACHE=/app/pub-cache
```

Then, create a new file in your project directory named `Procfile` (with no suffix) and enter the following:

```
release: /app/dart-sdk/bin/pub global run aqueduct:aqueduct db upgrade --connect \$DATABASE_URL
web: /app/dart-sdk/bin/pub global run aqueduct:aqueduct serve --port \$PORT --config-path heroku.yaml
```

This file tells Heroku how to run your application, and to execute any database migrations each time you push a release. Make sure this file is checked into version control:

```
git commit -am "Adds Procfile"
```

### Step 3: Configuring Application Values

Heroku provides configuration values through environment variables. In our `Procfile`, we indicated that we will use a file named `heroku.yaml` for configuration. This file will map configuration values in our application to environment variables in the Heroku platform. Your configuration file may vary, but it is important to note that if you are using a database, the database credentials are provided through a `connection string`. A connection string looks like this: `postgres://user:password@host:5432/name` and by default, Heroku stores it in the environment variable named `DATABASE_URL`.

In `heroku.yaml` (which you will need to create in your project directory), you can reference an environment variable by prefixing its name with a `$`. When using the built-in `DatabaseConfiguration` type, you can assign the connection string like so:

```yaml
database: $DATABASE_URL
```

!!! warning "Your heroku.yaml might be different"
    Make sure the structure of your `heroku.yaml` file matches the expected structure in your application's `Configuration` subclass.

Check `heroku.yaml` into version control.

```
git commit -am "add heroku.yaml"
```

### Step 4: Running the Aqueduct Application

If your application uses a database, make sure you have generated your migration file(s) and added it to version control. The `Procfile` will ensure that database is up to date with any migrations checked into source control before running your app. Generate your migration file with the following command from your project directory and then check it into version control:

```bash
aqueduct db generate
git commit -am "adds migration files"
```

Now, you can deploy your application. It's as simple as this:

```bash
git push heroku master
```

This command pushes your code to a remote git server hosted by Heroku, which triggers your application to run its release script.

Now that your application's database schema has been uploaded throug, you can configure your OAuth 2 server with client identifiers if you are using `package:aqueduct/managed_auth`. The following command will run within your application's remote environment.

```bash
heroku run /app/dart-sdk/bin/pub global run aqueduct:aqueduct auth add-client --id com.app.standard --secret secret --connect \$DATABASE_URL
```

Finally, scale up a dyno and the application will start receiving requests:

```bash
heroku ps:scale web=1
```

Now your application is running!
