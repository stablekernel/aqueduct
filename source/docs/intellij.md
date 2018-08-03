# Aqueduct IntellIJ IDEA Templates

This document describes how to install file and code templates for Aqueduct when using an IntelliJ IDE (e.g., IDEA, IDEA CE, Webstorm).

## Installation

Download the [this file](../files/settings.jar) and import it into IntelliJ by selecting `Import Settings...` from the `File` menu.

## File Templates

File templates are created by selecting `New` from the `File` menu or by right-clicking a directory in the project navigator. The following templates exists:

| Template Name | Behavior |
|---|---|
| Aqueduct ResourceController | Creates a new file with the skeleton of an `ResourceController`. |
| Aqueduct ManagedObject | Creates a new file with the skeleton of a `ManagedObject` subclass |
| Aqueduct Test | Creates a new file that creates and installs a `TestHarness` subclass from your project. |

## Live Templates

Live templates are keywords that expand into a larger code block. Typing the keyword in a Dart file and hitting return will enter common Aqueduct code. Live templates often have placeholders that can by jumped between by using the return key.

### Live Templates: HTTP

| Shortcut | Behavior |
|---|---|
| `operation` | Creates a new operation method in a `ResourceController`. |
| `bindbody` | Adds a body binding to an operation method. |
| `bindheader` | Adds a header binding to an operation method. |
| `bindquery` | Adds a query binding to an operation method. |
| `bindpath` | Adds a path binding to an operation method. |

### Live Templates: ORM

| Shortcut | Behavior |
|---|---|
| `ps` | Enters the property selector syntax for `Query.where`, `Query.join` and other query configuration methods. |
| `column` | Adds a column annotated field to a `ManagedObject`. |
| `relate` | Adds a relationship annotated field to a `ManagedObject`. |

### Live Templates: Testing

| Shortcut | Behavior |
|---|---|
| `test` |  Creates a test closure in a test file. |
