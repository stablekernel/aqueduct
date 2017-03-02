# Deploying an Aqueduct Application

We've only touched on a small part of Aqueduct, but we've hit the fundamentals pretty well. The rest of the documentation should lead you towards more specific features, in a less hand-holding way. A lot of the code you have written throughout the tutorial is part of the templates that ship with Aqueduct. So it's likely that this is the last time you'll write the 'setup code' you wrote throughout this tutorial. To create a project from the templates, run:

```bash
aqueduct create my_project
```

Deploying Aqueduct applications involves using the `aqueduct serve` command to run the web server, and `aqueduct db` to upload your application's database schema to a live database. See the [Deployment Guide](../deploy/overview.md) for detailed instructions.
