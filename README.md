![Aqueduct](https://s3.amazonaws.com/aqueduct-collateral/aqueduct.png)

[![OSX/Linux Build Status](https://travis-ci.org/stablekernel/aqueduct.svg?branch=master)](https://travis-ci.org/stablekernel/aqueduct) [![codecov](https://codecov.io/gh/stablekernel/aqueduct/branch/master/graph/badge.svg)](https://codecov.io/gh/stablekernel/aqueduct) [![Windows Build status](https://ci.appveyor.com/api/projects/status/l2uy4r0yguhg4pis?svg=true)](https://ci.appveyor.com/project/joeconwaystk/aqueduct)

[![Slack](https://slackaqueductsignup.herokuapp.com/badge.svg)](http://slackaqueductsignup.herokuapp.com/)

Aqueduct is a server-side framework for building and deploying multi-threaded REST applications. It is written in Dart and targets the Dart VM. Its goal is to provide an integrated, consistently styled API. If this is your first time viewing Aqueduct, check out [the tour](https://aqueduct.io/docs/tour/).

The framework contains behavior for routing, OAuth 2.0, a PostgreSQL ORM, testing, and more.

The `aqueduct` command-line tool serves applications, manages database schemas and OAuth 2.0 clients, and generates OpenAPI specifications.

In-depth documentation is available [here](https://aqueduct.io/docs).

## Getting Started

1. [Install Dart](https://www.dartlang.org/install).
2. Activate Aqueduct

        pub global activate aqueduct

3. Create a new project.

        aqueduct create my_project

Open the project directory in an [IntelliJ IDE](https://www.jetbrains.com/idea/download/), [Atom](https://atom.io) or [Visual Studio Code](https://code.visualstudio.com). All three IDEs have a Dart plugin. IntelliJ IDEA is preferred and has [file and code templates](https://aqueduct.io/docs/intellij/) specific to Aqueduct.

## Tutorials, Documentation and Examples

Step-by-step tutorials for beginners are available [here](https://aqueduct.io/docs/tut/getting-started).

You can find the API reference [here](https://www.dartdocs.org/documentation/aqueduct/latest) or you can install it in [Dash](https://kapeli.com/docsets#dartdoc).

You can find in-depth and conceptual guides [here](https://aqueduct.io/docs/).

An ever-expanding repository of Aqueduct examples is [here](https://github.com/stablekernel/aqueduct_examples).
