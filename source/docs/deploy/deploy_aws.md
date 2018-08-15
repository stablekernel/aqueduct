# Deploying an Aqueduct Application on Remote VMs

For other deployment options, see [Deploying Aqueduct Applications](index.md).

### Purpose

This document will describe the steps to deploy an Aqueduct application to a remote machine that you are able to `ssh` into. This is often the case for Amazon Web Service (AWS) EC2 instances, Google Cloud Compute Instances, Azure Virtual Machines, and rented boxes on platforms like Digital Ocean or other cloud providers.

If you are unfamiliar with deploying applications in this way, this is not a good beginner's guide and will not cover many of the steps necessary to deploy an application. Prefer to use a platform like Heroku or one that supports Docker. See the guides on [Heroku](deploy_heroku.md) and [Docker](deploy_docker.md) for better options.

### Summary

Aqueduct applications are run by using `aqueduct serve` or `dart bin/main.dart`.

```
# in project directory
aqueduct serve

# or

# in project directory
dart bin/main.dart
```

The target machine must have Dart installed. If you are using `aqueduct serve`, you must also activate the CLI on the target machine:

```
pub global activate aqueduct
```

Your source code must also be available on the target machine. You can transfer your source to a machine with tools like `ftp`, `scp`, `rsync` and `git`.

Aqueduct will listen on port 8888 by default. Change this value at the CLI `aqueduct serve --port 80` or in `bin/main.dart`. Ensure that security controls on your instance can accept connections on the port Aqueduct is listening on. It is preferable to use a reverse proxy (e.g. nginx or a load balancer) instead of serving the application directly.

Use tools like `supervisord` to ensure the application restarts if the VM crashes.

## Configuration Management

When deploying directly to a VM, it is your responsibility to manage your configuration file. This can often be done by transferring an environment specific `config.yaml` file to your target machine and storing it in your project's directory on the remote machine.

## CLI Tools

Many deployments will need to perform database migrations and OAuth 2.0 client identifier management with the `aqueduct` CLI. You can run these tools locally with the `--connect` flag to specify the location of your database instance. Ensure that you have the propery security controls to access the database instance from your local machine.
