# Modeling Data

In this guide, you will learn how to create types that are mapped to database tables. At the end of this guide are additional examples of data model types.

## Defining a Table

In your application, you declare types whose instances are stored in a database. Each of these types is mapped to a database table, where each property of the type is a column of the table. For example, consider modeling newspaper articles, where each article has a unique identifier, text contents and published date:

```dart
// This is a table definition of an 'article'
class _Article {
  @Column(primaryKey: true)
  int id;

  String contents;

  @Column(indexed: true)
  DateTime publishedDate;
}
```

This plain Dart class is called a *table definition* because it defines a database table named `_Article`. The table has three columns, `id`, `contents`, `publishedDate`. An example of the data stored in this table might look like this:

| id | contents | publishedDate |
| -- | -------- | ------------- |
| 1  | Today, the local... | 2018-02-01 00:00:00.000 |
| 2  | In other news, ... | 2018-03-01 04:30:00.000 |

A property in a table definition can optionally have a `Column` annotation. This annotation configures the behavior of the associated database column. If a property doesn't have an annotation, the column has default behavior. These behaviors are shown in the table below:

| Option | Type | Behavior | Default |
| ------ | ---- | -------- | ------- |
| primaryKey | `bool` | sets primary key column | false (not primary key) |
| databaseType | `ManagedPropertyType` | sets underlying column type | inferred from Dart type |
| nullable | `bool` | toggles whether column can be null | false (not nullable) |
| unique | `bool` | toggles whether column is unique across all rows | false (not unique) |
| defaultValue | `String` | provides default value for new rows when value is undefined | null |
| indexed | `bool` | whether an index should be created for the column | false (no index) |
| omitByDefault | `bool` | whether this column should be left out by default | false (fetch column value) |
| autoincrement | `bool` | whether this column's value is automatically generated from a series | false (not generated) |

You must use either zero or one `Column` annotation per property, and you must set all behaviors in one annotation, e.g.:

```dart
@Column(nullable: true, unique: true, indexed: true)
int field;
```

The data type of a column is inferred from the Dart type of the property as shown by the following table.

| Dart Type | General Column Type | PostgreSQL Column Type |
|-----------|---------------|------|
| `int` | integer number | `INT` or `SERIAL` |
| `double` | floating point number | `DOUBLE PRECISION` |
| `String` | text | `TEXT` |
| `DateTime` | timestamp | `TIMESTAMP` |
| `bool` | boolean | `BOOLEAN` |
| `Document` | a JSON object or array | `JSONB` |
| Any `enum` | text, restricted to enum cases | `TEXT` |

Some types can be represented by many database types; for example, an integer can be stored as 2, 4 or 8 bytes. Use the `databaseType` of a `Column` annotation to specify:

```dart
@Column(databaseType: ManagedType.bigInteger)
int bigNumber;
```

The only requirement of a table definition type is that it has exactly one primary key property. A primary key is an indexed, unique identifier for a database row and is set through the `Column` annotation.

```dart
@Column(primaryKey: true)
int id;
```

A primary key can be any supported data type, and it is always unique and indexed. It is common for primary keys to be 64-bit, auto-incrementing integers. The `primaryKey` constant exists as a convenience for a `Column` with these behaviors.

```dart
class _Article {
  @primaryKey // equivalent to @Column(primaryKey: true, databaseType: ManagedType.bigInteger, autoincrement: true)
  int id;

  ...
}
```

!!! note "Creating Tables"
    Tables are created in a database by using the `aqueduct` command line tool to generate and execute migration scripts. The tool inspects your database types and automatically synchronizes a databases schema to match your them.

By default, the name of the table definition is the name of the database table. You can configure this with the `Table` annotation.

```dart
@Table(name: "ArticleTable")
class _Article {
  @primaryKey
  int id;

  String contents;

  @Column(indexed: true)
  DateTime publishedDate;
}
```

It is convention that table definitions are *private classes*, that is, their name is prefixed with an underscore (`_`). This convention is discussed later in this guide.

## Defining a Managed Object Subclass

A table definition by itself is just a plain Dart class. You must also declare a `ManagedObject` subclass to bring your table definition to life. Here's an example:

```dart
class Article extends ManagedObject<_Article> implements _Article {}
```

A managed object subclass, also called the *instance type*, is the object type that you work with in your application code. For example, when you fetch rows from a database, you will get a list of managed objects. A managed object subclass declares its table definition in two places: once as the type argument of its superclass, and again as an interface it implements.

A managed object subclass inherits all of the properties from its table definition; i.e., an `Article` has an `id`, `contents` and `publishedDate` because `_Article` declares those properties. You create and use instances of a managed object subclass like any other object:

```dart
final article = new Article();
article.text = "Today, ...";
article.publishedDate = DateTime.now();
```

!!! warning "Managed Object Constructors"
    You can add new constructors to a managed object subclass, but you must always have a default, no-argument constructor. This default constructor is used when the ORM creates instances from rows in your database.

## Modeling Relationships

A managed object can have *relationships* to other managed objects. For example, an author can have many books, an article can belong to a newspaper, and an employee can have a manager. In a relational database, relationships between tables are established by storing the primary key of a table row in a column of the related table. This column is a *foreign key reference* to the related table.

When a table has a foreign key reference, it is said to *belong to* the related table. In the example of an employee and manager, the employee *belongs to* the manager and therefore the employee table has a foreign key reference to the manager table. The inverse of this statement is also true: a manager *has* employees. A manager has-many employees - this is called a *has-many relationship*. There are also *has-one relationships* - for example, a country has-one capital.

The following is an example of a country and a has-one relationship to a capital city:

```dart
class City extends ManagedObject<_City> implements _City {}
class _City {
  @primaryKey
  int id;

  @Relate(#capital)
  Country country;
}

class Country extends ManagedObject<_Country> implements _Country {}
class _Country {
  @primaryKey
  int id;

  City capital;
}
```

A relationship is formed between two tables by declaring properties in both table definition types. The type of those properties is the related managed object subclass - so a `Country` has a property of type `City`, and a `City` has a property of type `Country`.

Exactly one of those properties must have a `Relate` annotation. The `Relate` annotation designates the underlying column as a foreign key column. In this example, the city table has a foreign key column to the country table. Conceptually, then, a city *belongs to* a country and a country has-one capital city. A city can only belong to one country through this relationship, and that is true of all belongs-to relationship properties.

!!! note "Foreign Key Column Names"
    A foreign key column in the database is named by joining the name of the relationship property and the primary key of the related table with an underscore. For example, the column in the city table is named `country_id`.

The property without `Relate` is the *inverse* of the relationship and is conceptually either a has-one or has-many relationship property. In this example, a country's relationship to its capital is has-one. A relationship is has-many when the type of the inverse property is a `ManagedSet`. For example, if we wanted to model a relationship between a country and all of its cities, we'd declare a `ManagedSet<City>` property in the country:

```dart
class City extends ManagedObject<_City> implements _City {}
class _City {
  ...

  @Relate(#cities)
  Country country;
}

class Country extends ManagedObject<_Country> implements _Country {}
class _Country {
  ...

  ManagedSet<City> cities;
}
```

!!! note "ManagedSet Behavior"
    A `Relate` property can never be a `ManagedSet`. A `ManagedSet` is a `List`, and therefore can be used in the same way a list is used.

Notice that the `Relate` annotation takes at least one argument: a symbol that matches the name of the inverse property. This is what links two relationship properties to each other. In the first example, this argument was `#capital` because the name of the inverse property is `capital`; likewise, `#cities` and `cities`. This pairing name must match or an error will be thrown.

!!! note "Symbols"
    A symbol is a name identifier in Dart; a symbol can refer to a class, method, or property. The `#name` syntax is a *symbol literal*.

The `Relate` annotation has optional arguments to further define the relationship. Like `Column`, these are optional arguments, e.g.:

```dart
@Relate(#cities, isRequired: true, rule: DeleteRule.cascade)
```

A relationship may be be required or optional. For example, if `City.country` were required, than an `City` must always have an `Country`. By default, relationships are optional.

A relationship has a delete rule. When an object is deleted, any objects that belong to its relationships are subject to this rule. The following table shows the rules and their behavior:

| Rule | Behavior | Example |
| ---- | -------- | ------- |
| nullify (default) | inverse is set to null | When deleting an author, its articles' author becomes null |
| cascade | related objects are also deleted | When deleting an author, its articles are deleted |
| restrict | delete fails | When attempting to delete an author with articles, the delete operation fails |
| default | inverse set to a default value | When deleting an author, its articles author is set to the default value of the column |

## Special Behaviors

### Enum Types

Enums types can be used to declare properties in a table definition. The database will store the column as a string representation of the enumeration. Here's an example where a user can be an administrator or a normal user:

```dart
enum UserType {
  admin, user
}

class User extends ManagedObject<_User> implements _User {}
class _User {
  @primaryKey
  int id;

  String name;

  UserType role;
}

var query = Query<User>(context)
  ..values.name = "Bob"
  ..values.role = UserType.admin;
final bob = await query.insert();

query = Query<User>(context)
  ..where((u) => u.role).equalTo(UserType.admin);
final allAdmins = await query.fetch();
```

In the database, the `role` column is stored as a string. Its value is either "admin" or "user".

### Private Variables

A private variable in a table definition removes it from the serialized representation of an object. A private variable is always fetched when making a database query, but it is not read when invoking `read` and is not written when invoking `asMap`. Both of these methods are invoked when reading a managed object from a request body, or writing it to a response body.

### Transient Properties

Properties declares in a managed object subclass are called *transient* because they are not stored in a database. For example, consider an `Author` type that stores first and last name as separate columns. Instead of redundantly storing a 'full name' in the database, a transient property can combine the first and last name:

```dart
class Author extends ManagedObject<_Author> implements _Author {
  String get name => "$firstName $lastName";
  set name(String fullName) {
    firstName = fullName.split(" ").first;
    lastName = fullName.split(" ").last;
  }
}
class _Author {
  @primaryKey
  int id;

  String firstName;
  String lastName;
}
```

By default, a transient property is ignored when reading an object from a request body or writing the object to a response body (see the guide on [serialization](serialization.md) for more details). You can annotate a transient property with `Serialize` so that it is able to be read from a request body, written to a response body, or both. For example:

```dart
class Author extends ManagedObject<_Author> implements _Author {
  @Serialize()
  String get name => "$firstName $lastName";

  @Serialize()
  set name(String fullName) {
    firstName = fullName.split(" ").first;
    lastName = fullName.split(" ").last;
  }
}
```

You may declare getters, setters and properties to be serialized in this way. When declaring a property, you can control it with arguments to `Serialize`:

```dart
class Author extends ManagedObject<_Author> implements _Author {
  @Serialize(input: false, output: true)
  bool isCurrentlyPromoted;
}
```

## Project File Structure

A managed object subclass and its table definition together are called an *entity*. Each entity should be declared in the same file, and the table definition should be prefixed with an `_` to prevent it from being used elsewhere in the project. It is preferable to declare one entity per file, and store all entities in the `lib/model/` directory of your project.

The files your model definitions are declared in must be visible to Aqueduct tooling. In normal circumstances, this happens automatically because of the following:

1. Aqueduct tooling can find any file that is imported (directly or transitively) from your library file.
2. Your library file, by default, can see the file your `ApplicationChannel` is declared in.
3. Your application channel file must import any controller that it links.
4. Your controllers must import any model file they use.

When you use the `aqueduct` CLI to generate database migration scripts, it will report all of the `ManagedObject`s in your application that it was able to find. If a particular type is not listed, it may reveal that you aren't using that type. If you need to ensure that the tooling can see a particular model file that it is not locating, you may import it in your `channel.dart` file.

## Examples

### Example: One-to-Many Relationship

An author has many books:

```dart
class Author extends ManagedObject<_Author> implements _Author {}
class _Author {
  @primaryKey
  int id;

  String name;

  ManagedSet<Book> books;
}

class Book extends ManagedObject<_Book> implements _Book {}
class _Book {
  @primaryKey
  int id;

  String name;

  @Relate(#books)
  Author author;
}
```

To insert an author and a book associated with that author:

```dart
final authorQuery = Query<Author>(context)
  ..values.name = "Fred";
final author = await authorQuery.insert();

final bookQuery = Query<Book>(context)
  ..values.name = "Title"
  ..values.author.id = author.id;
final book = await bookQuery.insert();  
```

To fetch authors and their books:

```dart
final query = Query<Author>(context)
  ..join(set: (a) => a.books);
final authors = await query.fetch();
```

To fetch a book and their full author object:

```dart
final query = Query<Book>(context)
  ..where((b) => b.id).equalTo(1)
  ..join(object: (a) => a.author);
final books = await query.fetch();
```

### Example: One-to-One Relationship

```dart
class Country extends ManagedObject<_Country> implements _Country {}
class _Country {
  @primaryKey
  int id;

  String name;

  City capital;
}

class City extends ManagedObject<_City> implements _City {}
class _City {
  @primaryKey
  int id;

  String name;

  @Relate(#capital)
  Country country;
}
```

To fetch a country and its capital:

```dart
final query = Query<Country>(context)
  ..where((c) => c.id).equalTo(1)
  ..join(object: (a) => a.capital);
final countries = await query.fetch();
```

### Example: Many-to-Many Relationship

```dart
class Team extends ManagedObject<_Team> implements _Team {}
class _Team {
  @primaryKey
  int id;

  String name;

  ManagedSet<TeamPlayer> teamPlayers;
}

// This type is a join table
class TeamPlayer extends ManagedObject<_TeamPlayer> implements _TeamPlayer {}
class _TeamPlayer {
  @primaryKey
  int id;  

  @Relate(#teamPlayers)
  Team team;

  @Relate(#teamPlayers)
  Player player;
}

class Player extends ManagedObject<_Player> implements _Player {}
class _Player {
  @primaryKey
  int id;

  String name;

  ManagedSet<TeamPlayer> teamPlayers;
}
```

To fetch a team and its players:

```dart
// Note that the final join is not cascaded from the Team query,
// but from the Query created by joining with TeamPlayer
final query = Query<Team>(context)
  ..where((t) => t.id).equalTo(1)
  ..join(set: (t) => t.teamPlayers).join(object: (tp) => tp.player);
final team = await query.fetchOne();
```

The structure of this object is:

```json
{
  "id": 1,
  "name": "Badgers",
  "teamPlayers": [
    {
      "id": 1,
      "team": {
        "id": 1
      },
      "player": {
        "id": 1,
        "name": "Fred"
      }
    }
  ]
}
```

You can flatten this structure in a number of ways. In the simplest form, add a `Serialize`-annotated transient property to the `ManagedObject` subclass, and each time you fetch, remove the join table from the object and place the players in the transient property.

```dart
class Team extends ManagedObject<_Team> implements _Team {
  @Serialize(input: false, output: true)
  List<Player> players;
}

final team = ...;
team.players = team.teamPlayers.map((t) => t.player).toList();
// Remove teamPlayers; it is redundant
team.backing.removeProperty("teamPlayers");
```

### Example: Hierarchical Relationships (Self Referencing)

Hierarchical relationships follow the same rules as all other relationship, but declare the foreign key property and the inverse in the same type.

```dart
class Person extends ManagedObject<_Person> implements _Person {}
class _Person {
  @primaryKey
  int id;

  String name;

  ManagedSet<Person> children;

  @Relate(#children)
  Person parent;
}
```
