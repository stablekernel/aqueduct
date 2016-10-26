![Aqueduct](https://raw.githubusercontent.com/stablekernel/aqueduct/master/images/aqueduct.png)

[![Build Status](https://travis-ci.org/stablekernel/aqueduct.svg?branch=master)](https://travis-ci.org/stablekernel/aqueduct)

Aqueduct is a server-side framework written in Dart.

## Getting Started

1. [Install Dart](https://www.dartlang.org/install).
2. Activate Aqueduct

        pub global activate aqueduct

3. Run first time setup.

        aqueduct setup

4. Create a new project.

        aqueduct create -n my_project

Open the project directory in the editor of your choice. Our preferred editor is [IntellIJ IDEA Community Edition](https://www.jetbrains.com/idea/download/) (with the [Dart Plugin](https://plugins.jetbrains.com/plugin/6351)). [Atom](https://atom.io) is also a good editor, but support for running Dart tests is lacking.

## Major Features

1. HTTP Request Routing.
2. Multiple CPU support, without adding complicated multi-threading logic.
3. CORS Support.
4. Automatic OpenAPI specification/documentation generation.
5. OAuth 2.0 implementation.
6. Fully-featured ORM, with clear, type- and name-safe syntax, and SQL Join support. (Supports PostgreSQL by default.)
7. Database migration tooling.
8. Template projects for quick starts.
9. Integration with CI tools. (Supports TravisCI by default.)
10. Integrated testing utilities for clean and productive tests.
11. Logging

## Tutorials

Need a walkthrough? Read the [tutorials](http://stablekernel.github.io/aqueduct/). They take you through the steps of building an Aqueduct application.

## Documentation

You can find the API reference [here](https://www.dartdocs.org/documentation/aqueduct/latest).
You can find in-depth guides and tutorials [here](http://stablekernel.github.io/aqueduct/).
