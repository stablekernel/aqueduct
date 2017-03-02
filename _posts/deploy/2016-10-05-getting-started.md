---
layout: page
title: "Getting Started"
category: deploy
date: 2016-06-19 21:22:35
order: 2
---

Aqueduct is a web server framework. At a high level, it handles request routing and handling, authentication and authorization, database querying, instance configuration and logging. Aqueduct applications are written in [Dart](https://www.dartlang.org), a powerful and flexible language with a gentle learning curve.

To use Aqueduct, you must [install Dart SDK](https://www.dartlang.org/install). It's a very quick set of steps.

You must also install the `aqueduct` command line utility. After installing Dart, run the following command:

```bash
pub global activate aqueduct
```

Make sure you read the output of this command in full - it may have you do some extra setup.

To create new projects, use the following:

```bash
aqueduct create my_app
```

This command creates a new project directory from a template.

Once the `aqueduct` utility has been activated, you should setup your local machine to be able to run Aqueduct application tests. This is done with the following command:

```bash
aqueduct setup
```

This command will prompt you to install PostgreSQL locally and then create a test database that is configured such that Aqueduct can run tests against it.

The recommended IDE is [IntelliJ IDEA CE](https://www.jetbrains.com/idea/download/) (or any other IntelliJ platform, like Webstorm) with the [Dart Plugin](https://plugins.jetbrains.com/idea/plugin/6351-dart). (The plugin can be installed directly from the IntelliJ IDEA plugin preference pane.)

Other editors with good Dart plugins are [Atom](https://atom.io) and [Visual Studio Code](https://code.visualstudio.com).

In any of these editors, simply opening the project directory created by `aqueduct create` will do.

Please see the [Tutorials and Documentation](http://stablekernel.github.io/aqueduct/) as well as the `README.md` file in newly created projects.
