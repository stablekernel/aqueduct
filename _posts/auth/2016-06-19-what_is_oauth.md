---
layout: page
title: "Overview"
category: auth
date: 2016-06-19 21:22:35
order: 6
---

OAuth 2.0 is a way to make sure the information and actions your application has can only be seen and used by the people it supposed to be seen and used by. This means two things:

  1. Making sure every time someone interacts your application, they aren't pretending to be someone else.
  2. Making sure that someone only has access to what you've allowed them to have access to.

It's best to picture how OAuth 2.0 works by pretending to be a drug dealer. So, let's say you were a small-time drug dealer.

You need to get some drugs to sell. You don't have drugs, nor can you create them, so you have to get a supplier. A supplier doesn't just sell drugs at volume to anyone off the street, that's how you get caught by undercover agents. So instead, the supplier makes you fill out a form and does a background check first. Once you are approved, you get a cell phone number that you can call.

However, you can't just call this number and place an order - the supplier has a lot of heat on them and someone could be listening in. (Also, this isn't the supplier's only number - they've got different numbers depending on the caller. East-siders call one number, west-siders call another, their distributor has a direct line, etc.) When you call, you have to say your full name and answer a question that was asked of you in the initial form that only you would know.

After being verified, you get a text message with an image of a bar code. You can take this bar code to a number of warehouses across the city, where a guard scans it and lets you in to pick up a shipment.

As a drug dealer, you are a user of a service that requires authentication and authorization. Once you have that authorization, you can access the contents of that service - in this case, order fulfillment warehouses. And that's what OAuth 2.0 does.

In this scenario, your drug-dealing alter ego is called a *resource owner*. It's a fancy word for 'user', but intentionally abstract enough that someone can make it super confusing on Wikipedia. (For example, read the [Wikipedia page on the number zero](https://en.wikipedia.org/wiki/0).) Is there more to a resource owner than just being a "user"? Yeah, but who cares? If you already know that, you aren't reading this, and you have to understand this before you can know that.

So, the resource owner is a person that is sitting at a computer or on their phone and using an application. They click some buttons and the application sends a request to a server to fulfill the user's command. This is where OAuth 2.0 creates a nuanced distinction: it treats the client application and the resource owner as different entities. We naturally think of the resource owner talking directly with the server, but in reality, the client application does the talking on the resource owner's behalf. It's the same difference between you and their cell phone: you punched the buttons to make the call, but the cell phone actually does the calling and exchanging of data.

This is a useful distinction. Let's say heat picks up on the eastside, the supplier might limit the number of warehouses a dealer might have access to if they are calling the eastside number. 

 When a resource owner enters their username and password, its the client application that

A resource owner sits at a computer and clicks things in a client application, because they want to see or do something. Your application server is


The client application is registered with your server, and your server gave the application developers a secret.
The user submits their username and password in the application login page. The application makes a request to the server with the username and password.

They have to know a client ID and client secret, which have to be registered with the application. They enter their username and password in a client application, and the application sends its
They send a request to your server - with the client ID and client secret in a header - plus their username and password. If that all checks out, they get back an access token. When they send a request for some resource on your server, they attach the bearer token

In order to pick up a shipment, you have to call the supplier from the

1. Register a Client ID/Secret
2. Have a 'Resource Owner'
3. Have Resource Owner ask for Access to Things, providing their client id/secret
4. Give Resource Owner a Token that represents their access
5. Allow Resource Owner to access Things with their token

6. Refresh their token
