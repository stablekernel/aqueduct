---
layout: page
title: "Passwords and Authorization Headers"
category: auth
date: 2016-06-19 21:22:35
order: 5
---

In an authentication system, a password is a secret string of characters that proves to the system that a user is who they say they are. A system has to validate the password of a user, and so a naive authentication system may just store the password and compare it to any password it receives to validate it. However, this is a dangerous thing to do: if someone gets access to your system's database, they will have access to the passwords for all of your users. Many people reuse the same email and password for different services, and so even if you aren't concerned with the safety of the information you store, you should be concerned with your users' security on the internet as a whole.

Therefore, passwords are transformed via a one-way, cryptographic hash function. A hash function takes a password as input and spits out a bunch of gibberish as output. That gibberish is so gibberish-y that it'd take a computer many years to de-gibberish it and get the original password. This gibberish is a hashed password, and Aqueduct only stores the hashed password. When a user sends their password to verify who they are, the same function is applied and the output is compared to the stored hashed password. Aqueduct uses the Password-Based Key Derivation Function 2 (PBKDF2) algorithm for this purpose.

## Hashes, Salts and PBKDF2

If you are using the built-in classes for handling authentication tasks - like `AuthServer` - then you won't have to bother with using the `PBKDF2` class. If, however, you wish to generate a password hash, you may use the `PBKDF2.generateKey` method. This method takes (among a few other things) a clear-text password and a salt and outputs a list of bytes that can be stored somewhere. If you run this method multiple times with the same inputs, you will get the same result. You may also use `AuthServer.generatePasswordHash` to invoke `PBKDF2.generateKey` on your behalf.

A salt is a random string of bytes whose purpose is to just be random. This large random value is combined with a password to form the output hash. This random generation ensures that if someone somehow finds a both a password and its hash, they can't reverse engineer the hashing algorithm and figure out other passwords just by knowing their hash. You can generate a random salt with `AuthServer.generateRandomSalt`.


## Parsing the Authorization Header

There are two built-in utilities for parsing an HTTP request's Authorization header: `AuthorizationBasicParser` and `AuthorizationBearerParser`. Both are used as follows:

```dart
Request request = ...;
var authHeader = request.innerRequest.headers.value("authorization");

var basic = AuthorizationBasicParser.parse(authHeader);
var username = basic.username;
var password = basic.password;

var token = AuthorizationBearerParser.parse(authHeader);
```

In either case, if the Authorization header is null, an `HTTPResponseException` is thrown with a status code of 401. If the header is malformed in any way, an `HTTPResponseException` with status code 400 is returned.

When parsing a bearer token authorization header, the value is first ensured to start with the term `Bearer `. Then, anything that comes after that is the bearer token.

When parsing a basic authorization header, the value is first ensured to start with the term `Basic `. The string following this syntax is then Base-64 decoded and split by the `:` character. An instance of `AuthorizationBasicElements` is created and returned, its `username` is the string preceding the `:` and its `password` is the characters after `:`.
