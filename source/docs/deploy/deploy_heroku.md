# Deploying an Aqueduct Application on Heroku

For other deployment options, see [Deploying Aqueduct Applications](overview.md).

### Purpose

To run a production Aqueduct application on Heroku. Make sure to also read [Testing Aqueduct Applications](../testing/overview.md).

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

Estimated Time: <5 minutes.

### Step 1: Setting up a Heroku Application

Create a new application in Heroku. Add the 'Heroku Postgres' add-on.

Navigate to the Settings tab in the Heroku web interface and click 'Reveal Config Vars'. Note the DATABASE_URL, it'll get used later.

### Step 2: Setting up an Aqueduct Application to Run on Heroku

If you have not yet, create a new Aqueduct application on your local machine, go into that directory, and initialize it as a git repository:

```bash
aqueduct create app_name
cd app_name
git init
```

Login to Heroku and run the Aqueduct tool to configure a project for Heroku. The value for `--heroku` *must* be the name of the Heroku application (not the Aqueduct application, unless they are the same, obvi).

```bash
heroku login
aqueduct setup --heroku=app_name
```

This command will create the files Heroku needs to run the application, remove `config.yaml` from `.gitignore` (you'll see why in a moment) and runs some `heroku` commands to set up the Heroku application's environment.

### Step 3: Configuring Application Values

Heroku provides configuration values through environment variables, where Aqueduct normally provides them in `config.yaml` file. Because Aqueduct uses [safe_config](https://pub.dartlang.org/packages/safe_config), configuration files can map keys to environment variables with a simple syntax. The `config.yaml` file's values get replaced with their environment variable names and it gets checked into source control. To map configuration values to an environment variable, the value for a configuration key is prefixed with a dollar sign (`$`) followed by the case-sensitive name of the environment variable.

Modify `config.yaml` to appear as follows:

```
database: $DATABASE_URL
logging:
 type: console
```

Recall that `aqueduct setup` with the `--heroku` option removes `config.yaml` from `.gitignore`.

### Step 4: Running the Aqueduct Application

First, create a database migration. The `Procfile` declared that Heroku will automatically run any migration files prior to running the application as long as they are checked into source control.

```bash
aqueduct db generate
```

Now, add all of the files to `git` and push it to heroku:

```bash
git add .
git commit -m "initial commit"
git push heroku master
```

Next, set up an OAuth 2.0 client id:

```bash
heroku run /app/dart-sdk/bin/pub global run aqueduct:aqueduct auth add-client --id com.app.standard --secret secret --connect \$DATABASE_URL
```

Finally, spin up a dyno and the application will start receiving requests:

```bash
heroku ps:scale web=1
```
