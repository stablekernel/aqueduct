---
layout: page
title: "Getting Started: Building a Web Server"
category: tut
date: 2016-06-20 10:35:56
order: 1
---

* This guide is written for developers on Mac OS X.

Installing Dart
---

If you have Homebrew installed, run these commands from terminal:

```bash
brew tap dart-lang/dart
brew install dart
```

If you don't have Homebrew installed or you are on another platform, visit [https://www.dartlang.org/downloads](https://www.dartlang.org/downloads). It'll be quick, promise.

Creating a Project
---

Later on, we'll use a template generator, an IDE (IntelliJ IDEA Community Edition) and build an actual project. To start, though, we'll keep it simple. Create a new directory named `quiz` (ensure that it is lowercase). Within this directory, create a new file named `pubspec.yaml`. Dart uses this file to define your project and its dependencies. For the purposes of this getting started guide, you may want to use a capable text editor that you are familiar with and that supports both YAML and Dart. We suggest using [https://atom.io](https://atom.io).

In the pubspec, enter the following markup:

```yaml
name: quiz
description: A quiz web server
version: 0.0.1
author: Me

environment:
  sdk: '>=1.0.0 <2.0.0'

dependencies:
  aqueduct: any  
```

This pubspec now defines a project named `quiz` (all Dart files and project identifiers are snake case), indicates that it uses a version of the Dart SDK between 1.0 and 2.0, and depends on the `aqueduct` package. Save this file in the `quiz` directory.

Next, you will fetch the dependencies of the `quiz` project. From the command line, run the following command from inside the `quiz` directory:

```bash
pub get
```

Dependencies get stored in the directory ~/.pub-cache. Dart creates some project-specific files to reference the dependencies in that global cache in the project directory. You won't have to worry about that, though, since you'll never have to deal with it directly. Sometimes, it's just nice to know where things are. (There is one other file, called `pubspec.lock` that you do care about, but we'll chat about it later.)

Now, your project can use `aqueduct`. For this simple getting started guide, we won't structure a full project and just focus on getting an `aqueduct` web server up and running. Create a new directory named `bin` and add a file to it named `quiz.dart`. At the top of this file, import the `aqueduct` package:

```dart
import 'package:aqueduct/aqueduct.dart';

```

An `aqueduct` application is defined by its `ApplicationPipeline`. A pipeline is the entry point into your application-specific code for all HTTP requests, and defines how those requests should be routed and eventually responded to. 
