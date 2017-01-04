---
layout: page
title: "Creating and Using AuthServers"
category: auth
date: 2016-06-19 21:22:35
order: 2
---

An application stores data that shouldn't be accessed by just anyone. Information should be secured so that only authorized users can access it. The OAuth 2.0 framework defines how an application should allow someone to get access to information and which information they have access to.

In a typical scenario, there is a server (an Aqueduct application), a client that sends requests to the server (like a browser or mobile application) and a user that is using the client. When a user takes an action in a client, the client issues a request to server to access a resource. The server's job is to ensure the user is authorized to access the resource and the user is who they say they are. ([Recall that a *resource* is a meaningful term when talking about web server applications](routing.html).)

A user provides their *credentials* - a username and a password - to a client, usually in the form of a login page. The client then sends this information to the server in an HTTP request. This request is often something like `POST /auth/token`. If the password is correct, the server creates a new *access token*, stores it, and gives it to the client. When the user does more stuff in a client that accesses a resource on the server, it attaches the access token to the HTTP request for that resource. The server determines if the resource is accessible for the attached access token.

There are fun terms in OAuth 2.0 that sound more complex than they actually are. For example, what we might colloquially call a "user" or an "account", OAuth 2.0 calls a *resource owner*. That's an individual or entity that owns a particular resource. This doesn't mean that only the owner can access a resource. For example, in a social networking application, a user's profile is a resource. A user owns their profile, but other users can see it; or at least part of it. The user can probably see all of their own profile. Still, in some systems - like a banking application - no one but the owner can see their bank account.

An access token belongs to a resource owner. So in a simple implementation, a server figures out which resource owner an access token belongs to for every request, and figures out if that resource owner can access the resource. 
Your application uses its own logic to figure out what a. OAuth 2.0 has a bit of guidance for this called *access scopes*.

There are some resources that don't belong to a resource owner, but instead to the application itself.

In the context of OAuth 2.0, a "user" is called a *resource owner* - every resource is owned by a resource owner. For example,

*Authorization* is the process of ensuring that a particular user has access to a resource. *Authentication* is the process of a proving that a user is who they say they are.

An application also cannot trust that a client acting on behalf of a particular user is really being controlled by that user. Therefore, a user must provide a secret password that their client uses to prove to the application that they are who they say they are. This proving mechanism is called *authentication*. The secret password and identifier of the user (like a username or email) are called *credentials*.

The OAuth 2.0 framework provides a way for applications to secure information and determine if a client is authorized to access that information. Particular to HTTP web server applications like Aqueduct, OAuth 2.0 is implemented by exposing endpoints that allow for authentication information to be exchanged for authorization tokens. These tokens can be used to access secure HTTP resources.

Generally speaking, a user will enter their username and password into a client application. The client makes requests on the user's behalf to exchange these credentials for an authorization token. When the user issues requests for secured resources through that client, the client attaches the token to the requests so that the server can determine whether or not that user has access to a resource.



The purpose of this document is to describe the components that Aqueduct application use to provide authentication and authorization behavior.

<!-- -->

## Authorization Flows

In the context of OAuth 2.0, there must be some concept of a *resource owner*. This is typically something like a user or an account object; an individual or entity that has access to secure information. Authorization tokens belong to a resource owner; HTTP requests that include an authorization token allow that request to access the secure information of the corresponding resource owner. Therefore, there must be some mechanism to exchange credentials for an authorization token - and these mechanisms are what OAuth 2.0 defines.

OAuth 2.0 calls these different exchange mechanisms "flows". The most basic flow takes a username and password as input and outputs a token. This flow is called the *resource owner grant* flow and is used when you are building a client application that you control the source code for.

When you want to allow third-party applications to make authorized requests on behalf of a user in your system, the process is broken into two steps: first you exchange the username and password for an *authorization code*, and then you exchange the authorization code for a token. This two-step flow is called the *authorization code* flow.

Both the resource owner grant and authorization code flows are used to issue tokens that grant a client access to a resource owner's information. However, the application itself will have resources that are accessible by any trusted client, not just particular users.

(There is another type of flow called *implicit flow*, but that is not available in Aqueduct.)



## The Objects Involved in Authorization

An Aqueduct application must define a number of types to implement authorization.

First, there must be some concept of a *resource owner*. This is typically something like a user or an account object; an individual or entity that has access to secure information. In order to be a resource owner, an object must implement the `Authenticatable` interface; in other words, it must have a unique identifier, a unique username and storage for a hashed password and salt. While it is not necessary, it is often the case that resource owners are `ManagedObject<T>` subclasses named something like `User` or `Account`.

There must also be an object that represents the authorization tokens themselves. These tokens must have identifying information, dates from when they were issued and when they will expire, and the ability to reference the resource owner (an `Authenticatable`) that the token belongs to. Objects of this type must implement `AuthTokenizable<T>`, where `T` is the type of the unique identifier for the `Authenticatable` type the token belongs to. For example, if there is a `User` class that implements `Authenticatable` and has an `int` primary key, the tokens issued for that user must implement `AuthTokenizable<int>`.



In Aqueduct, a bearer token is represented by an instance of `AuthTokenizable<T>`. This abstract class declares all of the properties a bearer token needs to have. For example, a bearer token must have an expiration date and a reference to its "owner" (typically a user). An application declares a concrete implementation of `AuthTokenizable<T>`

## Creating Instances of AuthServer

## Implementing AuthServerDelegate
