---
layout: page
title: "5. Deploying and Other Fun Things"
category: tut
date: 2016-06-23 13:27:59
order: 5
---

[Getting Started](getting-started.html) | [Writing Tests](writing-tests.html) | [Executing Queries](executing-queries.html) | [ManagedObject Relationships and Joins](model-relationships-and-joins.html) | Deployment

We've only touched on a small part of Aqueduct, but we've hit the fundamentals pretty well. The rest of the documentation should lead you towards more specific features, in a less hand-holding way. A lot of the code you have written throughout the tutorial is part of the templates that ship with Aqueduct. So it's likely that this is the last time you'll write the 'setup code' you wrote throughout this tutorial. To create a project from the templates, run:

```bash
aqueduct create my_project
```

Deploying Aqueduct applications involves using the `aqueduct serve` command to run the web server, and `aqueduct db` to upload your application's database schema to a live database. See the [Deployment Guide](deploy/overview.html) for detailed instructions.
