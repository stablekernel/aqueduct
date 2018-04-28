![Aqueduct](https://s3.amazonaws.com/aqueduct-collateral/aqueduct.png)

[![Build Status](https://travis-ci.org/stablekernel/aqueduct.svg?branch=master)](https://travis-ci.org/stablekernel/aqueduct) [![codecov](https://codecov.io/gh/stablekernel/aqueduct/branch/master/graph/badge.svg)](https://codecov.io/gh/stablekernel/aqueduct)

<a href="http://slackaqueductsignup.herokuapp.com/"><img src="https://slackaqueductsignup.herokuapp.com/badge.svg" alt="Slack"/></a><br/>

# 3.0 Pre-release Note

This documentation is the 3.0 pre-release documentation for Aqueduct. It has not been finalized and is subject to change.

## Installing Pre-release Aqueduct

You’ll need to upgrade to the developer release of Dart 2.0. On macOS, you install with Homebrew:

```bash
brew upgrade dart --devel
```

Once you have Dart 2.0, clone Aqueduct locally, switch to the 3.0 branch, and install the CLI from your local repository.

```bash
git clone https://github.com/stablekernel/aqueduct.git
cd aqueduct
git checkout 3.0

# Don't forget the dot at the end of the next command
pub global activate -spath .
```

Move to another directory and create a new project that targets Aqueduct 3.

```bash
# Make sure you aren't in the aqueduct directory
aqueduct create my_app
```

Because your project was created from a local version of Aqueduct, it’s pubspec.yaml file will point at that directory on your filesystem. To stay up to date with 3.0 (or to build remotely), change your pubspec.yaml file to reference the 3.0 branch on GitHub:

```yaml
aqueduct:
  git:
    url: git@github.com:stablekernel/aqueduct.git
    ref: “3.0”
```

You can access the pre-release API reference [here](https://aqueduct.io/prerelease-3.0/api/index.html).

## Aqueduct

Aqueduct is a server-side framework for building and deploying REST applications. It is written in Dart.

## Important Links

[Getting Started and Installation](getting_started.md)

[Tutorial](tut/getting-started.md).

[API Reference](https://www.dartdocs.org/documentation/aqueduct/latest) (or you can install it in [Dash](https://kapeli.com/docsets#dartdoc)).

[Example Repository](https://github.com/stablekernel/aqueduct_examples)

Check out [Snippets](snippets/index.md) for quick code snippets to get you up and running faster.

Import [this file](https://s3.amazonaws.com/aqueduct-intellij/aqueduct.jar) into IntelliJ IDEA for Aqueduct file and code templates.

## How to Use this Documentation

Each topic covers a major component of the Aqueduct framework and are displayed in the side menu. Within each topic, there is an overview page and a number of guides. Each guide contains example code, explanations and best practices for building Aqueduct applications.

Guides create an initial understanding and give context to the Aqueduct framework. The API reference details each type, property and method in the Aqueduct framework. The tutorial is a guided exercise that teaches the very basics of Aqueduct while creating a server application.
