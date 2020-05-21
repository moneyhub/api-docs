---
title: Moneyhub API Documentation
language_tabs:
  - shell: Shell
  - http: HTTP
  - javascript: JavaScript
  - javascript--nodejs: Node.JS
  - ruby: Ruby
  - python: Python
  - java: Java
  - go: Go
toc_footers: []
includes: []
search: true
highlight_theme: darkula
headingLevel: 2

---
# Moneyhub Auth API

###### Version 0.8

We provide an OpenID Connect compliant interface that should work well with any OpenID Connect certified relying party software.

This document will provide a high level overview, but we recommend that users familiarise themselves with the following specs:

- [OpenID Connect Core](http://openid.net/specs/openid-connect-core-1_0.html)
- [Financial Grade API Read Only Profile](https://bitbucket.org/openid/fapi/src/master/Financial_API_WD_001.md)
- [Financial Grade API Read/Write Profile](https://bitbucket.org/openid/fapi/src/master/Financial_API_WD_002.md)

Base URL:

- <a href="https://identity.moneyhub.co.uk">https://identity.moneyhub.co.uk</a>

# Overview

Our identity service supports the following use cases:

1. Allowing a user to connect to a financial institution and grant permissioned access to their data from that financial institution.
2. Allowing a user to connect to multiple financial institutions through a single profile and gain access to the data from those institutions.

We provide these features via an OpenID Provider interface that supports standard OAuth 2 based flows to issue access tokens that can be used to gain access to financial data via our API Gateway.

[Moneyhub Data API documentation](#moneyhub-data-api).

[Moneyhub Data API Swagger documentation](https://api.moneyhub.co.uk/docs)

[Moneyhub API client](https://github.com/moneyhub/moneyhub-api-client)

[Moneyhub Admin portal](https://admin-portal.moneyhub.co.uk/)

## Flow for use case 1

> Connecting to a financial institution
> ![Use case 1](first-use-case.png)

- Partner generates an authorisation url to the [Authorisation Endpoint](#authorization-endpoint) with the [Financial Institution scope](#financial-institutions) to connect to and the [Data scopes](#data-access) required as part of the [Claims](#claims)
- Partner redirects user to the authorisation url
- Moneyhub Auth API gains consent from the user to access their banking data
- Moneyhub Auth API redirects the user to the bank
- Bank authenticates the user and sends them back to the Moneyhub Auth API
- Moneyhub redirects the user back to the partner with an `authorization_code`
- Partner exchanges this code for an `access_token` using the [Token endpoint](#token-endpoint)
- Partner uses the access token at the [Moneyhub Data API](#moneyhub-data-api) to access user's financial data

## Flow for use case 2

> Registering a user and connecting to a financial institution
> ![Use case 2](second-use-case.png)

> This example assumes the use of an OpenID Client (e.g. [Node OpenId client](https://github.com/panva/node-openid-client))

```js
const { access_token } = await client.grant({
  grant_type: "client_credentials",
  scope: "user:create",
})

const user = await got.post(`#{identityServiceUrl}/`, {
  headers: {
    Authorization: `Bearer ${access_token}`,
  },
  json: true,
  body: { clientUserId: "some-id" },
})

const authParams = {
  client_id: client_id,
  scope: "openid id:some-bankid",
  state: "your-state-value",
  redirect_uri: redirect_uri,
  response_type: "code",
  prompt: "consent",
}

const claims = {
  id_token: {
    sub: {
      essential: true,
      value: user.userId,
    },
    mh:con_id: {
      essential: true,
    },
  },
}

const request = await client.requestObject({
  ...authParams,
  claims,
  max_age: 86400,
})

const url = client.authorizationUrl({
  ...authParams,
  request,
})

// redirect the user to this url
// if everything is succesful they will be redirected to your `redirect_uri` with `code` and `state` as query parameters.

const tokens = await client.authorizationCallback(
  redirect_uri,
  { code, state },
  { state: expectedState }
)
// these tokens confirm that the account has been added, however cannot be used for data access
// the `id_token` will contain the id of the connection that has just been created

const { access_token } = await client.grant({
  grant_type: "client_credentials",
  scope: "accounts:read transactions:read:all",
  sub: user.userId,
})

const accounts = await got(`#{resourceServerUrl}/accounts`, {
  headers: {
    Authorization: `Bearer ${access_token}`,
  },
  json: true,
})

const transactions = await got(`#{resourceServerUrl}/transactions`, {
  headers: {
    Authorization: `Bearer ${access_token}`,
  },
  json: true,
})
```

- Partner requests an access token from the identity service with the scope `user:create` using the [Token endpoint](#token-endpoint)
- Partner uses this token to create a profile at the [User endpoint](#post-users)
- Partner generates an authorisation url to the [Authorisation Endpoint](#authorization-endpoint) with the [Financial Institution scope](#financial-institutions) to connect to, and with the id of the new user profile as part of the [Claims](#claims)
- Partner redirects user to the authorisation url
- Moneyhub Auth API gains consent from the user to access their banking data
- Moneyhub Auth API redirects the user to the bank
- Bank authenticates the user and sends them back to the Moneyhub Auth API
- Moneyhub redirects the user back to the partner with an `authorization_code`
- Partner exchanges the `authorization_code` for an `access_token` and `id_token`to complete the connection using the [Token endpoint](#token-endpoint). This `access_token` do not contains any data scopes so it can't be used to gain access to the user's financial data. The `id_token` contains the `connection_id`
- Partner requests an access token from the Moneyhub Auth API with the [Data scopes](#data-access) required and a `sub` parameter in the [Claims](#claims) that contains the profile id using the [Token endpoint](#token-endpoint)
- Partner uses the access token at the [Moneyhub Data API](#moneyhub-data-api) to access the user's financial data

# API clients

You can register an OAuth client through our [Admin portal](https://admin-portal.moneyhub.co.uk/).
We will then generate a `client_id` and `client_secret` corresponding to your client. These credentials will be used to authenticate your client on every route of our Auth API.

To correctly authenticate your client, you will need to send your client credentials in the `Authorization` header in the following format:

`Authorization: Basic Base64_encode(<client_id>:<client_secret>)`

[API Client Metadata](https://openid.net/specs/openid-connect-registration-1_0.html#ClientMetadata)

## Production

Ideally a production API client should have the following settings:

1. Either a JWKS key set registered or a jwks_uri configured, i.e. either the JWKS or JWKS_URI field filled in.
2. Client Authentication configured to be `private_key_jwt`
3. Request Object signing alg configured to be one of the RS*, ES* or PS\* algorithms
4. ID token signing alg configured to be one of the RS*, ES* or PS\* algorithms
5. Response type set to be `code`
6. Grant types to be authorization_code, refresh_token and client_credentials
7. Redirect uris are required to be https://

These are a couple of security enhanncemnets that can be implemented on your side:
   - A nonce to be added to the request object when generating an authorization url ([OpenId Nonce](https://openid.net/specs/openid-connect-core-1_0.html#NonceNotes))
   - The same nonce value needs to be used when exchanging the authorization code for the token set at the end of the authorization process.

## JWKS Key Set

> Example creating JWKS key set using the Moneyhub api client

```console
node examples/jwks/create-jwks.js

Options

  --key-alg string
  --key-use string
  --key-size number
  --alg string
```

> Public keys - This can be used as the jwks in your API client configuration in the Moneyhub Admin portal

```json
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "lNWK3qGU9eQMLqH96ZB5Jf4i3hEdhqNKpaDBGmREt5Q",
      "use": "sig",
      "e": "AQAB",
      "n": "kHkz5oM6xis2NIJJtbeffY_F9DLNO6Tx9JsYtwTFSvqI5x3msssgDbYs8VjUR_Dt5yurz1dHBkJLK1ZvvTIUwTSc_TG8y0m3-MsszVM5jbEvI5AUATRca6zQJhRQCYgvAeFPGQgUNh8zjsAzlwc3VXdEYBT69orNdOru-MEGynnFJpi23ikm57IWKlpfZplGh7FxHZgABNJ1PPhFZGJFAxVtI5LbMlwIsHWtP7gxUw4U0-U7rLL-_fFqSEMP6aGI4GMDSpTh6P7mRTORfXUIE3ycOzXJiK5fOfwQzNOMD41uMshOsyMAu0BsNZQuKqefb9qT5lfGP15zmQnVqePOZw",
      "alg": "RS256"
    }
  ]
}
```

> Private keys - This can be used as the keys value when configuring the moneyhub api client

```json
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "lNWK3qGU9eQMLqH96ZB5Jf4i3hEdhqNKpaDBGmREt5Q",
      "use": "sig",
      "e": "AQAB",
      "n": "kHkz5oM6xis2NIJJtbeffY_F9DLNO6Tx9JsYtwTFSvqI5x3msssgDbYs8VjUR_Dt5yurz1dHBkJLK1ZvvTIUwTSc_TG8y0m3-MsszVM5jbEvI5AUATRca6zQJhRQCYgvAeFPGQgUNh8zjsAzlwc3VXdEYBT69orNdOru-MEGynnFJpi23ikm57IWKlpfZplGh7FxHZgABNJ1PPhFZGJFAxVtI5LbMlwIsHWtP7gxUw4U0-U7rLL-_fFqSEMP6aGI4GMDSpTh6P7mRTORfXUIE3ycOzXJiK5fOfwQzNOMD41uMshOsyMAu0BsNZQuKqefb9qT5lfGP15zmQnVqePOZw",
      "d": "B4ssmJa1lO9grzE2ZBSocUf2kB-u87RTJfCLQ9Mt8hJO37KB_0f37n9arWdz_iWoZm-zUuo9vSftAOBMiVZ6GvSCVf4o23yH7Ke_OSFlWe6shXDaeo2fXcfyPmrFGxpPSgvXs3jmhUTvzj5e8z3fN8k4esPdrs3kmHxD6h06G4xXwtmEHOuygn96IdpK5Zql4wy8L0goo8mOrP_4caPOLdBDeATDwqWXMTeXMW8NGsp90sBjDxVzqqysH0gnQZV0ZfVH2K1fgPoKNJtyX28RVcrjOW6oU5lxARVfxI3bwTGbJ8MaLNrKrd7KjUFaJ_owvpX3ifo6woHL3IrBP-rnwQ",
      "p": "5orIAF7rPBZzw0A9sj2ems2AO6xwR6jJy_xSJ6jflstW3Cmz0DdG3u9IUrQpQb9G1oO-L_So5iaCKjSfLessu3uVzvWLfkOP-zNeSjL86zlW0cFtzVeIImDBiyx21RvgFjhVQ5GKic01Il9aDOrkA5Q78m_v-OxA7TaOzMw1RTE",
      "q": "oG1WZreDYjMYko2dcXgpijwqYi1Z_5UsiQrjDZpGskk3g1bq4SGVZkpR-tx8Cx6Bn8W8-rOpiTJg08FUGFNjJgNF9mSBhUjaQc0IrKrdy_4wfMyHqqE7cEdSGSg-xH0TghGfCVbJuXYWoMM7hT7XJ7HSiiA92m-msvI4K4cKRxc",
      "dp": "az-0uzdtB48KW5LPINQ5rJpdRWV69ls3RYYkUf7lxSjjR5i-5eZROfTnGFJnvwZU1gaDu5t911Oiyi-gvaPiM3XSw2zHb_3ORXYoLyx5LJSIJxxtEFHgKt4IK86LmahWHwAl6kESyfiE93CUW94KJQAYwzf_0zVVHwV6eRumzIE",
      "dq": "mGBBuL6FpDg0Fr871BL2Ib6T4zyARypBaslUcA8hJyYz_CQKZFups8bTpxrVFxqatE70-Iq9dPrMzVTLs29AtVJWmXlNLHPOGsHMg3SnxqJhG6iJE6Cg_DxB1nNLawYCCYEDNbOhVu66_2dwmVbetW1JNLj7BwcVptI6V92j_XE",
      "qi": "pwGzAE02GWIp7TRburRvxC2SCLo1Oo3flPcKoYSKNguPzWe9gP-xhD9ZhNoDIRnNrgK562cB9dlSXvEGnrfSJdXTCM2m7BANyMvP0w_XkvxE0p4yY9BJtiQ-QgvZto-7PKn0PSukwE3I2fT2Hpgp7idCJE_EQnIsQCX4XD3DG48"
    }
  ]
}
```

To configure your API client you will need to generate a JWKS key set and have access to the public and private keys separately.

The public key needs to be added as the jwks in your API client configuration in the Moneyhub Admin portal.

The private key needs to be used as part of the configuration of the moneyhub api client or your openid client.

The easiest way to generate a valid jwks set is using our Moneyhub API client ([Moneyhub API client](https://github.com/moneyhub/moneyhub-api-client)).

The client has the method `createJWKS()` and there is an example of how to use it when cloning the repo under the examples folder.

# OpenId Connect

## Authorization Endpoint

`https://identity.moneyhub.co.uk/oidc/auth`

[OpenID Connect Authorization Spec](http://openid.net/specs/openid-connect-core-1_0.html#AuthorizationEndpoint)

We support the use of request objects and the claims parameter at this endpoint.

## Token Endpoint

`https://identity.moneyhub.co.uk/oidc/token`

> Example of a client_credentials grant for creating a user

```sh
curl -X POST \
  'https://identity.moneyhub.co.uk/oidc/token' \
  -H 'Authorization: Basic Base64_encode(<client_id>:<client_secret>'\
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials&scope=user%3Acreate'
```

> Example of a client_credentials grant for data access

```sh
curl -X POST \
  'https://identity.moneyhub.co.uk/oidc/token' \
  -H 'Authorization: Basic Base64_encode(<client_id>:<client_secret>'\
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials&scope=accounts%3Aread&sub=example-user-id'
```

[OpenID Connect Token Spec](http://openid.net/specs/openid-connect-core-1_0.html#TokenEndpoint)

We support the following grant types:

- `authorization_code`
- `client_credentials`
- `refresh_token`

The `authorization_code` and `refresh_token` grant types are implemented exactly as according to the specs in [RFC6749](https://tools.ietf.org/html/rfc6749) and [OIDC](http://openid.net/specs/openid-connect-core-1_0.html).

The `client_credentials` grant supports 2 use cases:

- generating a token for for creating, deleting or reading users that have been created using your oauth client credentials
  The scopes that can be requested are `user:create`, `user:read` and `user:delete`
- generating a token to access a specific user's data (e.g. accounts, transactions). The `sub` query parameter is required

## Discovery

`https://identity.moneyhub.co.uk/oidc/.well-known/openid-configuration`

[OpenID Connect Discovery Spec](http://openid.net/specs/openid-connect-discovery-1_0.html)

Our discovery document is available [here](https://identity.moneyhub.co.uk/oidc/.well-known/openid-configuration).
It will contain our up-to-date machine readable configuration
and for example will list our:

- token endpoint
- authorization endpoint
- jwks endpoint
- scopes that we support
- claims that we support
- the cryptographic algorithms we support
- the response types we support

Examples of discovery metadata from other providers are:

- [Google](https://accounts.google.com/.well-known/openid-configuration)
- [Microsoft](https://login.windows.net/contoso.onmicrosoft.com/.well-known/openid-configuration)

## Response Types

Our discovery doc will list the response types that we support. Currently these are: `code`, `code id_token` and `id_token`.

`code` is fairly straight forward and is the standard OAuth 2
authorization code flow.

`code id_token` is one of the variants of the hybrid flow and isn't always understood. At a basic level it means that we will send an `id_token` along with the authorization code when we redirect the user back to your `redirect_uri`. This id_token doesn't contain any identity information, but is rather a detached signature which cryptographically binds the authorization_code we send back with the nonce and the state that you sent to us. It prevents a certain class of code interception attacks and we encourage implementers to use it rather than the basic authorization code flow.

## Request Object

OpenID Connect defines the request object - this is a JWT that contains the standard OAuth 2.0 parameters such as: `client_id`, `scope`, `state`, etc.

We encourage implementers to use this and may require it for certain use cases.

The request object allows you to sign the request parameters and prevents tampering. This can prevent a certain class of attacks against OAuth 2.0.

More information about request objects is available [here](http://openid.net/specs/openid-connect-core-1_0.html#JWTRequests)

## JWKS Endpoints & Asymmetric Signatures

We use jwks endpoints to support the [rotation of signing keys](http://openid.net/specs/openid-connect-core-1_0.html#RotateSigKeys)

As part of registering your client software with us, we will ask you for your own jwks endpoint.

If you don't yet have one, we strongly encourage you to implement one. JWKS endpoints provide a neat method to achieve key rotation without any interruption to service or any need for bilateral communication.

They enable you to manage your keys in which ever manner you see fit and removes the need for the `client_secret`.

For more information about the benefits of this approach or advice
on implementing, please contact us.

# Bank connections

We have 4 lists of available bank connections:

- [All connections](https://identity.moneyhub.co.uk/oidc/.well-known/all-connections)
- [API connections](https://identity.moneyhub.co.uk/oidc/.well-known/api-connections)
- [Screen-scraping connections](https://identity.moneyhub.co.uk/oidc/.well-known/legacy-connections)
- [Test connections](https://identity.moneyhub.co.uk/oidc/.well-known/test-connections)

Every client you create will have access to the test connections by default. Access to the real connections via the API
will need to be requested.

Every connection will have the following properties:

- `id` - bank connection id (used to request an authorization url for a specific bank)
- `name`
- `type` - the type of bank connection (`api`, `legacy` or `test`)
- `bankRef` - reference that uniquely identities a set of connections as being part of the same institution (e.g. HSBC Open banking and HSBC credit cards). It is used to group a set of connections by the banking institution they refer to. It can alse be used to retrieve the bank icon.
- `parentRef` - this property is now deprecated. Please use `bankRef` instead
- `iconUrl` - the url of the bank icon SVG. Please be aware we don't have icons for all the connections we provide. For the missing icons you can either use your own set or use our generic bank icon found at this url: <https://identity.moneyhub.co.uk/bank-icons/default>
- `accountTypes` - an array containing the types of accounts supported by the connection (`cash`, `card`, `pension`, `mortgage`, `investment`, `loan`) and a beta boolean value flagging which accounts types for that connection are currently being developed and may not have a 100% success rate
- `userTypes` - an array of user account types supported by the bank connection (`personal` and `business`)

## GET /bank-icons/:bankRef

`https://identity.moneyhub.co.uk/bank-icons/:bankRef`

This route returns the bank icon as SVG when providing a valid bank reference listed under our available connections.

Please be aware we don't have icons for all the connections we provide, when this is the case the route returns 404 as response unless the `defaultIcon` parameter is used.

| Route parameters | Type     | Description                                                                                                      |
| ---------------- | -------- | ---------------------------------------------------------------------------------------------------------------- |
| bankRef          | `string` | Unique bank reference of the provider. When using `default` as the bank reference we return a generic bank icon. |

| Query parameters | Type      | Description                                                                                            |
| ---------------- | --------- | ------------------------------------------------------------------------------------------------------ |
| defaultIcon      | `boolean` | When value is true the route will return the default icon instead of 404 if bank icon is not available |

# Scopes

We use scopes to both describe the access the user is granting and the way in which you would like the user to identify themselves.

Below is a summary of the scopes we provide, please check our discovery document available [here](https://identity.moneyhub.co.uk/oidc/.well-known/openid-configuration) to see which particular scopes are supported by a given deployment of our identity service.

## OpenID

- `openid` - this scope is required and indicates that you are using our OpenID Connect interface. We will return an id token as described in the OpenID Connect Core spec. You can request specific claims to be present in the id token using the claims parameter described in OpenID Connect Core. For details on what claims we support, please check the [claims section](https://moneyhub.github.io/api-docs/#claims)
- `offline_access` - this scope indicates that you would like ongoing access to the user's resources, when it is present we will issue a refresh token

## Financial institutions

- `id:{bank_code}` - if you pass a specific bank code (available via the endpoints listed above) then we will bypass the bank chooser and take the user directly to the selected bank
- `id:all` - if you specify this scope we will display a list of all available connections
- `id:api` - if you specify this scope we will display a list of the available API based connections
- `id:legacy` - if you specify this scope we will display a list of the available legacy (screen scraping) connections
- `id:test` - if you specify a type of connection then we will display a list of our test connections. This scope will be enabled by default when creating a new client through our [admin portal](https://admin-portal.moneyhub.co.uk/)

The above scopes are mutually exclusive and we will return
an error of `invalid_scope` if more than one of the above is supplied.

## Data access

Most data access scopes are available to use in both [use cases](https://moneyhub.github.io/api-docs/#overview). The scopes ending in `write:all` are only available in the second use.

- `transactions:read:all` - All transactions
- `transactions:read:in` - All incoming transactions
- `transactions:read:out` - All outgoing transactions

Note - the above transactions:read scopes are mutually exclusive - if more than one is provided there will be an `invalid_scope` error.

- `transactions:write` - For all transactions that are able to be read it is possible to edit certain fields (e.g. category, notes, etc.). Please see the documentation on the transactions endpoint for details of which fields can be edited. If `transactions:write` is provided without any `transactions:read` scope there will be an `invalid_scope` error
- `transactions:write:all` - This allows full access to create transactions, edit all their properties and delete transactions. This scope is only available when issuing tokens for users that are managed by the client (only available for use case 2)
- `accounts:read` - Read access to all accounts
- `accounts_details:read` - Read access to accounts details such as full account number and sort code.
- `accounts:write` - Write access to all accounts. Please see the accounts endpoint for details of which fields can be edited.
- `accounts:write:all` - Full write access including the ability to delete accounts. This scope is only available when issuing tokens for users that are managed by the client (only available for use case 2)
- `categories:read` - Read access to a customer's categories.
- `categories:write` - Write access to a customer's custom categories.
- `spending_analysis:read` - Read access to a customer's spending analysis.
- `spending_goals:read` - Read access to a customer's spending goals.
- `spending_goals:write` - Write access to a customer's spending goals.
- `spending_goals:write:all` - Full write access to spending goals, including the ability to delete goals.
- `savings_goals:read` - Read access to a customer's saving goals.
- `savings_goals:write` - Write access to a customer's saving goals.
- `savings_goals:write:all` - Full write access to saving goals, including the ability to delete goals.

## Payments

- `payee:create` - this scope is required to create a new payee.
- `payee:read` - this scope is required to retrieve all of the payees that have been created by an API client.
- `payment` - this scope is required to initiate a payment.
- `payment:read` - this scope is required to retrieve all of the payments that have been initiated with by an API client.

## Connection lifecycle

Some of the OpenBanking APIs that we connect to require the user to re-authenticate every 90 days. In addition we have screen-scraping connections that the user will need to update if their credentials change. In order to support these flows we support the following scopes:

- `reauth`
- `refresh`

These scopes require a claims parameter to be sent that contains a `sub` value and a `mh:con_id` value. Moneyhub will then take the user through a re-authentication journey or "refresh" journey.

We advise that the above 2 scopes are used with the response_type of `id_token` rather than `code id_token`. This is because the access token issued at the end of such a flow is of no value and can only be introspected to confirm the values already present in the id_token.

The only scope that can (and must) be supplied along with either `reauth` or `refresh` is `openid`. If any other scope is provided the result will be an `invalid_scope` error.

### **Reauth**

This flow should be used to:
- Re authenticate an open banking connection once that the user's consent has expired.
- Update the login credentials on a legacy connection.

### **Refresh**

This flow is available only for legacy connections when the input of the user might be required to fetch the latest data. This is usually the case when MFA or security questions are enabled on the bank site.

This flow is not available for open banking connections as user input is never required to fetch the latest data, unless the consent has expired. If this is the case the reauth flow will need to be used to get a new consent.

## User management

- `user:create` - this scope is only supported with the client credentials grant type. It allows a relying party to create a new user profile.
- `user:read` - this scope is only supported with the client credentials grant type. It allows a relying party to access their user profiles.
- `user:delete` - this scope is only supported with the client credentials grant type. It allows a relying party to delete a user profile.

# Claims

> To add a new connection for a registered user via either openbanking or
> screen scraping the following parameters would be sent in the request object:

```json
{
  "scope": "openid id:all",
  "claims": {
    "id_token": {
      "sub": {
        "essential": true,
        "value": "5c1907c0e6b340e5c056fb2a"
      },
      "mh:con_id": {
        "essential": true
      }
    }
  }
}
```

> On completion of the connection, the connection id is returned in the id token as below:

```json
{
  "iss": "https://identity.moneyhub.com",
  "sub": "24400320",
  "aud": "s6BhdRkqt3",
  "nonce": "n-0S6_WzA2Mj",
  "exp": 1311281970,
  "iat": 1311280970,
  "mh:con_id": "the-connection-id"
}
```

> To refresh an account for a registered user via either openbanking or
> screen scraping the following parameters would be sent in the request object:

```json
{
  "scope": "openid refresh",
  "claims": {
    "id_token": {
      "sub": {
        "essential": true,
        "value": "5c1907c0e6b340e5c056fb2a"
      },
      "mh:con_id": {
        "essential": true,
        "value": "b74f1a79f0be8bdb857d82d0f041d7d2:0f1aa7c1-6379-483a-bfd8-ae0a208fb635"
      }
    }
  }
}
```

Moneyhub uses the OpenID Connect [claims parameter](http://openid.net/specs/openid-connect-core-1_0.html#ClaimsParameter) for the following purposes:

1. Specifying the connection that should be re-authorised or refreshed
2. Specifying the user profile that an account should be added to
3. Overriding the category type to categorise transactions for all accounts from this connection

The format of the claims parameter may seem odd to those unfamiliar with OpenID Connect, but it has the advantage of being a standards compliant technique of supporting the above purposes. It is supported by many OpenID Connect relying party libraries.

Our discovery document details the `claims` that we support, they currently include:

- `sub` - the subject (user id) that the authorization request should be scoped to (for adding, reauth and refresh)
- `mh:con_id` - the connection id that the authorization request should be scoped to (for reauth and refresh)
- `mh:cat_type` - (optional) override the category type that will be applied to transactions received through this connection (for adding and reauth). Valid values are `personal` and `business`

# Connection Widget

> Example loading via script tag

```html
<script
  data-clientid="your-client-id"
  data-redirecturi="your-redirect-uri"
  data-userid="the-user-id"
  data-posturi="/result"
  data-finishuri="/finish"
  data-type="test"
  src="https://bank-chooser.moneyhub.co.uk/account-connect.js"
></script>
```

> Example loading via JS API

```html
<script src="https://bank-chooser.moneyhub.co.uk/account-connect-js.js"></script>
```

```js
window.moneyhubAccountConnectWidget(document.querySelectorAll("#test")[0], {
  clientid: "your-client-id",
  redirecturi: "your-redirect-uri",
  userid: "user-id",
  posturi: "/result",
  finishuri: "/finish",
  type: "test",
  meta: {"any": "data you want associated with this session"}
  identityuri: "https://identity.moneyhub.co.uk",
})
```

We provide an account connection widget that that makes it easier to allow users to connect their accounts.

The widget can either be initialised with data attributes in a script tag - or can be injected into the DOM via a JavaScript API.

## Parameters

- _clientid_ - this is your client id for the client you want to use. It is availble from the admin portal
- _redirecturi_ - this is the uri that you want the user to be redirected to after they have succesfully connected to an account or had an error. This redirect uri must be added to your api client in the admin portal. The redirect uri also needs to host the widget and mustn't interfere with query parameters.
- _userid_ - the id of the user you want to connect accounts for. The user must be created via our API prior to the widget being loaded.
- _posturi_ - an enpoint set up to receive a JSON post each time a user either connects an account or has an error connecting an account. More details below
- _finishuri_ - a uri to redirect the user to when they click the "Finish" button
- _type_ - the type of connections to show when the users chooses a bank. Values can be "all", "api" or "test".
- _identityuri_ - this should always be "https://identity.moneyhub.co.uk" in the production environment.
- _meta_ - this is an optional property that you can set - it will be passed to the post uri.

## Post URI

> Example request to post uri when there is an error

```json
{
  "bankId": "1ffe704d39629a929c8e293880fb449a",
  "url": "https://identity-dev.moneyhub.co.uk/oidc/auth?claims=%7B%22id_token%22%3A%7B%22sub%22%3A%7B%22essential%22%3Atrue%2C%22value%22%3A%225c82710d7c2eb82b175c2c5c%22%7D%7D%7D&client_id=4d18da1b-b6b7-4275-8407-3c8bade53f9a&redirect_uri=http%3A%2F%2Flocalhost%3A3001&response_type=code&scope=openid%20id%3A1ffe704d39629a929c8e293880fb449a&state=7f231a1c3ee116a04db56438cc60b4ee",
  "created": 1559556347842,
  "userId": "5c82710d7c2eb82b175c2c5c",
  "meta": "some meta property",
  "state": "7f231a1c3ee116a04db56438cc60b4ee",
  "error": "invalid_claims",
  "modified": 1559556348809
}
```

> Example request to the post uri when an account has been succesfully connected:

```json
{
  "bankId": "1ffe704d39629a929c8e293880fb449a",
  "url": "https://identity-dev.moneyhub.co.uk/oidc/auth?claims=%7B%22id_token%22%3A%7B%22sub%22%3A%7B%22essential%22%3Atrue%2C%22value%22%3A%225ca49cda9cd8ab3640f3bb67%22%7D%7D%7D&client_id=4d18da1b-b6b7-4275-8407-3c8bade53f9a&redirect_uri=http%3A%2F%2Flocalhost%3A3001&response_type=code&scope=openid%20id%3A1ffe704d39629a929c8e293880fb449a&state=d657b3e549494c38fa7c8040763ef999",
  "created": 1559556615352,
  "userId": "5ca49cda9cd8ab3640f3bb67",
  "meta": "some meta property",
  "state": "d657b3e549494c38fa7c8040763ef999",
  "code": "bRHSHtqICup80FBfvi5jG7sejsY",
  "modified": 1559556620133
}
```

This endpoint must be set up to receive a JSON payload when the user succesfully connects or has an error connecting.

In the case of an error, there is nothing that you need to do, but it may be worth recording the error.

The important property here is `code`. This must be sent to our token endpoint in a standard OAuth 2 authorization code grant.

# User Management

To support use case 2, the following RESTful routes are available:

## POST /users

> Example request:

```sh
POST /users HTTP/1.1
Host: identity.moneyhub.co.uk
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkQ5SkFObVlmU0dfa2J0MktScFRLbzdRQ05IMl9SSy0wYTc4N3lqbTA3encifQ.eyJqdGkiOiJjcEVPMk11dVJscmtDfkdDQ3Rqa0IiLCJpc3MiOiJodHRwOi8vaWRlbnRpdHkuZGV2LjEyNy4wLjAuMS5uaXAuaW8vb2lkYyIsImlhdCI6MTUzNDQ5MzU0MSwiZXhwIjoxNTM0NDk0MTQxLCJzY29wZSI6InVzZXI6Y3JlYXRlIiwiYXVkIjoiODk4YzUyOWItYzA2Mi00ZjI2LWExMzYtZmQ4YmM0NjJkNTgzIn0.AMU266O-wgmz-6SOfSF_Bq0LQhoAgytaInwCKhT-tXQ6Z_L0I75blmRujnKALK-LG08ny_gemtDWUEmD2mjyHgO-vtmiSNMHF2T5z2GS3k4VOUbGKVjFY5kK9QfoUCR_WCpUEPd64LHe_IaR0rMAzaKcVLRhtjin9yAB-goif683ESBFQLDrnojzdcOxWtP1x_qGSNBOMqJ6RDk7H65aBCXJj5eee11EW71G1Q3C3_MyJqTYdwXbAzkE-8XLDznDqZzVmm4erFUTN3TuB5L7af2pendAWitGEeshHKRpgeHI3EQrNj98-UIyemVV9tUK76x2ojiV1ge7ZpnYeNCO0A
Content-Type: application/json
```

```json
{
  "clientUserId": "some-id"
}
```

> Example response:

```json
{
  "clientUserId": "some-id",
  "userId": "328278302947678c0fc37f54",
  "clientId": "898c529b-c062-4f26-a136-fd8bc462d583",
  "scopes": "user:create",
  "managedBy": "client"
}
```

This allows an API client to create a new "user". Once this user has been created the following operations are possible:

- starting an authorisation flow to connect a financial provider to that user
- gaining an access token for that user
- using that access token to get and create financial resources for that user

This route requires an access token from the client credentials grant with the scope of `user:create`.

It accepts a JSON body with a single parameter: `clientUserId`. This is optional but allows an API cilent to persist it's own identifier against the user.

## GET /users

This route requires an access token from the client credentials grant with the scope of `user:read`.
It returns an array of all the users associated with your api client.

| Query parameters | Type      | Description                                                                                            |
| ---------------- | --------- | ------------------------------------------------------------------------------------------------------ |
| limit            | `number`  | Set the number of records to be retrieved (Default: 100)                                               |
| offset           | `number`  | By specifying offset, you retrieve a subset of records starting with the offset value (Default: 0)     |

## GET /users/:id

This route requires an access token from the client credentials grant with the scope of `user:read`.
It returns a single user associated with your api client.

## GET /users/:id/connections

> Example request using moneyhub api client

```js
const connections = await moneyhub.getUserConnections("user-id")
```

> Example response

```json
{
  "data": [
    {
      "id": "b74f1a79f0be8bdb857d82d0f041d7d2:567da9db-7296-4dc0-8a99-7b20dea8d21f",
      "name": "Modelo Open Banking Mock",
      "type": "test",
      "connectedOn": "2019-09-27T14:29:43.687Z",
      "lastUpdated": "2019-09-27T14:30:30.284Z",
      "expiresAt": "2019-12-26T14:29:30.715Z",
      "accountIds": [
        "10c6e372-64a4-4d80-add1-ba8549d668ed"
      ],
      "status": "ok",
      "error": null,
    },
    {
      "id": "3c4637d3178c9a28ce655bfbf8e27a10:ae9cf42a-2fcb-40f1-a1ad-da0a5f1beed5",
      "name": "Aviva",
      "type": "legacy",
      "connectedOn": "2019-09-23T18:29:43.687Z",
      "lastUpdated": "2019-09-23T18:30:30.284Z",
      "expiresAt": "2019-12-22T12:29:30.715Z",
      "accountIds": [
        "ee429506-5565-4ee9-9c31-e375283c0497"
      ],
      "status": "ok",
      "error": null,
    },
    {
      "id": "b74f1a79f0be8bdb857d82d0f041d7d2:6fbebd5e-fb2a-4814-bdaf-9a8871167f43",
      "name": "Nationwide Open Banking",
      "type": "api",
      "connectedOn": "2019-09-27T14:28:47.072Z",
      "lastUpdated": "2019-09-27T14:29:34.792Z",
      "expiresAt": "2019-12-26T14:27:51.576Z",
      "accountIds": [
        "11b6f582-3013-4c71-8af3-9c2d83444c14"
      ],
      "status": "error",
      "error": "resync"
    }
  ],
  "meta": {}
}

```

This route requires an access token from the client credentials grant with the scope of `user:read`.
It gets information about all financial connections of a user.

### Connection status

- `ok` - The connection has a healthy status.
- `error` - The connection has encountered an error while syncing, the error code is specified under the error property.

### Connection errors

- `resync`: This connection hasn't been updated recently, most likely due to the requirement for the user to enter multi factor authentication. We advise to trigger a sync. If problem persists a reauth flow can be used for api connections and a refresh flow can be used for legacy connections.
- `sync_error`: There was an error syncing this connection. Please wait for us to automatically resync this connection later or trigger a sync. If problem persists a reauth flow can be used for api connections and a refresh flow can be used for legacy connections.
- `sync_partial`: There was an error syncing some of the transactions on this account. Please wait for us to automatically resync this connection later or trigger a sync.
- `mfa_required`: This connection requires multi factor authentication and needs user input. Please take the user through a refresh flow.
- `credentials_error`: This connection can no longer be updated, the user may have changed their credentials or revoked access. Please take the user through a reauth flow.

## DELETE /users/:id/connection/:connection-id

This route requires an access token from the client credentials grant with the scope of `user:delete`.
It deletes a financial connection of a user. This will revoke the grant that the user provided previously and it
will delete any data associated with it from our API. (e.g. accounts, transactions)

## DELETE /users/:id

This route requires an access token from the client credentials grant with the scope of `user:delete`.
It deletes a user and all of its financial connections that were created.

# Payments

Moneyhub access to payments uses the same OpenID Connect authorisation service as access to financial data.

There are three additional features that enable payments to be initiated:

- Support for Payee creation and management
- Custom payments scope and associated claim
- Support for Request Object endpoint

## Payee Management

The Moneyhub payments API is designed to be used to allow payments from arbitrary accounts to a single trusted account. For example a merchant or charity may want to enable their customers to pay into their bank account.

For this reason we require the receiving account to be pre-registered with us as a "payee". We allow this to be done via the administration panel or via API.

When creating payees via API the steps are as follows:

1. Get a client credentials token with the scope `payee:create`
2. Create a payee using the POST `/payees` route
3. You will receive back an `id` for the payee. This can be used in subsequent flows

## POST /payees

> Example request using moneyhub api client

```js
const tokens = await moneyhub.addPayee({
  accountNumber: "your account number",
  sortCode: "your sort code",
  name: "name of Payee",
})
```

> Example request

```sh
curl --request POST \
  --url https://identity.moneyhub.co.uk/payees \
  --header 'authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkQ5SkFObVlmU0dfa2J0MktScFRLbzdRQ (... abbreviated for brevity ...)' \
  --header 'content-type: application/json' \
  --data '{\n	"sortCode": "123456",\n	"accountNumber": "12345678",\n	"name": "Account name"\n}'
```

> Example response

```json
{
  "data": {
    "id": "e07f8dca-1a79-440a-8667-8cd02a000559",
    "clientId": "c40d7f7a-a698-4bf1-84bf-8f3798c018b2",
    "sortCode": "123456",
    "accountNumber": "12345678",
    "createdAt": "2019-05-23T07:48:53.916Z",
    "modifiedAt": "2019-05-23T07:48:53.916Z",
    "active": true,
    "name": "Account name"
  },
  "meta": {}
}

```

This route requires an access token from the client credentials grant with the scope of `payee:create`.

It creates a payee that later can be used to initiate a payment.

## GET /payees

> Example request using moneyhub api client

```js
const tokens = await moneyhub.getPayees({
  limit: "limit", // optional
  offset: "offset", // optional
})
```

> Example request

```sh
curl --request GET \
  --url https://identity.moneyhub.co.uk/payees \
  --header 'authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkQ5SkF (... abbreviated for brevity ...)'
```

> Example response

```json
{
  "data": [
    {
      "id": "e07f8dca-1a79-440a-8667-8cd02a000559",
      "clientId": "c40d7f7a-a698-4bf1-84bf-8f3798c018b2",
      "sortCode": "123456",
      "accountNumber": "12345678",
      "createdAt": "2019-05-23T07:48:53.916Z",
      "modifiedAt": "2019-05-23T07:48:53.916Z",
      "active": true,
      "name": "Account name"
    }
  ],
  "meta": {}
}

```

This route requires an access token from the client credentials grant with the scope of `payee:read`.

It returns all the payees that have been created for an specific API client.

| Query parameters | Type      | Description                                                                                            |
| ---------------- | --------- | ------------------------------------------------------------------------------------------------------ |
| limit            | `number`  | Set the number of records to be retrieved (Default: 10)                                                |
| offset           | `number`  | By specifying offset, you retrieve a subset of records starting with the offset value (Default: 0)     |

## Payments Claim

> Claim values

```json
{
  "payeeId": "id-of-the-payee",
  "amount": 150, // in pence
  "payeeRef": "reference to display on payee's statement", // Max 18 characters
  "payerRef": "reference to display on payer's statement" // Max 18 characters
}
```

> Example payments claim

```json
{
  "id_token": {
    "mh:con_id": {
      "essential": true
    },
    "mh:payment": {
      "essential": true,
      "value": {
        "payeeId": "id-of-the-payee",
        "amount": 150,
        "payeeRef": "reference to display on payee's statement",
        "payerRef": "reference to display on payer's statement"
      }
    }
  }
}
```

In order to initiate a payment via the API you need to use the `payment` scope and use the `mh:payment` claim. This claim require the values of the payeeeId, amount, payee refrence and payer reference.

This claim must be supplied using the claims parameter semantics from OpenID Connect Core. It should be nested under the `id_token` key and not the `userinfo` key.

Using the claims parameter may feel slightly convoluted, but it is a neat standards compliant way of us allowing OAuth clients to pass us arbitrary payment values.

By putting the payment payload inside a signed request object there is non-repudiable proof that the payment request was signed by your private key.

## POST /request (Request Object Endpoint)

> Example request

```sh
curl --request POST \
  --url https://identity.moneyhub.com/request \
  --header 'content-type: application/jws' \
  --data eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkdUTjlKYXJ2eFFLMGc0bHdvUTFESExOTTdhbTN1VFNGZm1jX0Q4WXE4Sk0ifQ.eyJjbGllbnRfaWQiOiJjNDBkN2Y3YS1hNjk4LTRiZjEtODRiZi04ZjM3OThjMDE4YjIiLCJzY29wZSI6InBheW1lbnQgb3BlbmlkIGlkOjFmZmU3MDRkMzk2MjlhOTI5YzhlMjkzODgwZmI0NDlhIiwic3RhdGUiOiJmb29iYXIiLCJjbGFpbXMiOnsiaWRfdG9rZW4iOnsibWg6Y29uX2lkIjp7ImVzc2VudGlhbCI6dHJ1ZX0sIm1oOnBheW1lbnQiOnsiZXNzZW50aWFsIjp0cnVlLCJ2YWx1ZSI6eyJhbW91bnQiOjEwMCwicGF5ZWVSZWYiOiJQYXllZSByZWYiLCJwYXllclJlZiI6IlBheWVyIHJlZiJ9fX19LCJleHAiOjE1NTg2MDc1NTQsInJlZGlyZWN0X3VyaSI6Imh0dHA6Ly9sb2NhbGhvc3Q6MzAwMS9hdXRoL2NhbGxiYWNrIiwicmVzcG9uc2VfdHlwZSI6ImNvZGUiLCJwcm9tcHQiOiJjb25zZW50IiwiaXNzIjoiYzQwZDdmN2EtYTY5OC00YmYxLTg0YmYtOGYzNzk4YzAxOGIyIiwiYXVkIjoiaHR0cDovL2lkZW50aXR5LmRldi4xMjcuMC4wLjEubmlwLmlvL29pZGMifQ.ELTOILtLJk-qT6GC7Hv02UfMvHgian791_Bqcr4b0CMIqsCYdeQk-5QgqHO27ZANfteaItOscrsg168_eXas093vhoGnXJsjA9T-f38IXoTil6fq7a4IgEygX2GAAP3c-wAlfW6FNEG5j9o9NhY4EkWlb1B5CGYwaQ61yLYkqBs7D_aYP0h57WeUiqtFwz_p1ieMiyDAL465a3ws2e5AfcT0SzHmaF6qfziL9msdSMgFQheJ4tWXiWum0xDNAIGDWGOV5bqSgnQiscXtbeyGvrl-bgqsaWFsTfGhmSPQrKFkzNCaOqHp0XdxiiyQaGuiPY-P9w9oS2h4Pbk-nompJg
```

> Example response

```
urn:x-mh-request:0af734c7-bc2f-4b89-ad0a-f5e0f91d5426
```

This endpoint receives a request object signed by an API client in order to create a `uri` that can be used to construct an authorization url.

In order to generate an authorization url for a payment to be initiated it is required to obtain a `request_uri` out of a request object containing the `mh:payment` claims.

The OpenId Connect core describes the use of the `request_uri` parameter when constructing an authorization url.

> A user can be redirected to our authorize url by using the `request_uri` parameter as follows:

```
https://identity.moneyhub.co.uk/oidc/auth?
 &client_id=s6BhdRkqt3
 &request_uri=urn:x-mh-request:0af734c7-bc2f-4b89-ad0a-f5e0f91d5426
 &scope=openid payment id:financial-connection-id
```

## Payments Authorization

> Creating a payment authorization url using our api client

```js
const url = await moneyhub.getPaymentAuthorizeUrl({
  bankId: "Bank id to authorise payment from",
  payeeId: "Id of payee previously added"
  amount: "Amount in pence to authorize payment"
  payeeRef: "Payee reference",
  payerRef: "Payer reference",
  state: "your state value", // optional
  nonce: "your nonce value", // optional
  claims: claimsObject, // optional
})
```

To authorise a payment the user needs to be redirected to the authorization url that contains the payments claim as explained above. The generation of the authorization url can be done with our moneyhub api client as shown in this section.

> Exchanging an authorization code for a token set using our api client

```js
const tokens = await moneyhub.exchangeCodeForTokens({
  code: "the authorization code",
  nonce: "your nonce value", // optional
  state: "your state value", // optional
  id_token: "your id token", // optional
})
```

Once the user has successfully granted Moneyhub consent to initiate the payment and authenticated at the bank we will return an authorization code to your `redirect_uri`. This must be exchanged for an access token as per standard OpenID Connect practice. If you don't exchange the auth code for an access token, the payment will never be completed even though the user has authenticated it.

> Decoded content of id token after exchanging authorization code

```json
{
  "sub": "5cda695b82d18512e415e648",
  "mh:con_id": "1fd7ca2c94a914819b2e1b6cf0abe874:b6592e9e-619f-4171-a933-6023c381bd03",
  "mh:payment": "aeb2bc6c-505e-41b7-a82a-e898a7e95438",
  "at_hash": "3MmQIA6EtEnfo319s-UZdw",
  "sid": "8be9087f-3b9f-426e-af52-2671f2ab88aa",
  "aud": "c40d7f7a-a698-4bf1-84bf-8f3798c018b2",
  "exp": 1557821587,
  "iat": 1557817987,
  "iss": "https://identity.moneyhub.co.uk/oidc"
}
```

As well as receiving an access token, you will receive an id token that will have a `mh_payment` claim. The value of this claim in the id token will be the id of the payment.

Once that you have extracted the payment id from the id token you can query the status of the payment on the folllwing endpoint: `GET /payment/:id`

## Payments Management

The following endpoints are available to get access to the payments that have been initiated by an API client.

## GET /payments

> Example request using moneyhub api client

```js
const tokens = await moneyhub.getPayments({
  limit: "limit", // optional
  offset: "offset", // optional
})
```

> Example request

```sh
curl --request GET \
  --url https://identity.moneyhub.co.uk/payments \
  --header 'authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkQ5SkF (... abbreviated for brevity ...)'
```

> Example response

```json
{
  "data": [
    {
      "id": "b4805496-154d-4592-8f67-88aebb7460e1",
      "payeeId": "258aaee5-0f1a-441c-8008-b57c2391767d",
      "payerRef": "Payer ref",
      "paymentSubmissionId": "258aaee5-0f1a-441c-8008-b57c2391767d",
      "amount": 100,
      "currency": "GBP",
      "status": "completed",
      "finalisedAt": "2020-04-22T13:52:53.380Z",
      "initiatedAt": "2020-04-22T13:50:39.607Z"
    },
    {
      "id": "00c13805-0a92-48ba-967a-b44dfcf2053d",
      "payeeId": "258aaee5-0f1a-441c-8008-b57c2391767d",
      "payerRef": "Payer ref 456",
      "paymentSubmissionId": "44e92d3c-d022-4f5a-a835-14b14ea1ed25",
      "amount": 100,
      "currency": "GBP",
      "status": "inProgress",
      "finalisedAt": "2019-09-23T14:58:51.848Z",
      "initiatedAt": "2019-09-23T14:58:51.952Z"
    }
 ],
  "meta": {
    "limit": 10,
    "offset": 0
  }
}
```

It returns all the payments that have been initiated by an API client regardless if they were authorised or not. Payments that have been authorised have the properties `exchangedAt` and `connectionId`.

This route requires an access token from the client credentials grant with the scope of `payment:read`.

| Query parameters | Type      | Description                                                                                            |
| ---------------- | --------- | ------------------------------------------------------------------------------------------------------ |
| limit            | `number`  | Set the number of records to be retrieved (Default: 10)                                                |
| offset           | `number`  | By specifying offset, you retrieve a subset of records starting with the offset value (Default: 0)     |

## GET /payments:id

> Example request using moneyhub api client

```js
const tokens = await moneyhub.getPayment("payment-id")
```

> Example request

```sh
curl --request GET \
  --url https://identity.moneyhub.co.uk/payments/payment-id \
  --header 'authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkQ5SkF (... abbreviated for brevity ...)'
```

It returns a single payment that was initiated by an API client. This route is useful to query the status of a payment as it contains a `status` field.

To call this endpoint you need an access token from the client credentials grant with the scope of `payment:read`.

# Webhooks

> Example webhook

```json
{
  "id": "abe168ce-1b2f-4c38-9c92-db5730485cb3",
  "eventType": "newTransactions",
  "userId": "5c79210bbac25ecb5e71ac40",
  "payload": {
    "accounts": [
      {
        "id": "6d0baf11-248e-4c11-9c04-97b7758b4e04",
        "transactions": [
          "d520402a-d982-43ee-b1d1-bdfd282249ea",
          "613586bf-dac9-4996-9c03-7194a7d62297"
        ]
      }
    ]
  }
}
```

This is a way to be notified in real time about events related to the api users that you have created.

You can configure webhook endpoints via the [Admin portal](https://admin-portal.moneyhub.co.uk/) when you add or edit your [API clients](/my-api-clients).

Once that you start receiving webhooks you will be able to see a list of them when you drill down to the details of your [API users](https://admin-portal.moneyhub.co.uk/api-users).

### Schema

| Name      | Type           | Description              |
| --------- | -------------- | ------------------------ |
| id        | `string`       | Unique id of the webhook |
| eventType | `string[enum]` | Event id                 |
| userId    | `string`       | User id                  |
| payload   | `object`       | Payload of the event     |

## New transactions

> Example payload

```json
{
  "accounts": [
    {
      "id": "6d0baf11-248e-4c11-9c04-97b7758b4e04",
      "transactions": [
        "d520402a-d982-43ee-b1d1-bdfd282249ea",
        "613586bf-dac9-4996-9c03-7194a7d62297"
      ]
    }
  ]
}
```

Id: `newTransactions`

Event that notifies when an account has been automatically updated and new transactions have come through.

### Event Payload

| Name           | Type            | Description                                     |
| -------------- | --------------- | ----------------------------------------------- |
| accounts       | `array[object]` | Array of accounts that contain new transactions |
| » id           | `string`        | Account Id                                      |
| » transactions | `array[string]` | Array of transactions ids                       |

<aside class="notice">
This event is not sent on the initial connection to a financial institution or when reauthorising a connection.
</aside>

## Updated transactions

Id: `updatedTransactions`

Event that notifies when an account has been automatically updated and transactions have been updated.

The fields that can be updated are the status (pending|posted), description and/or amount.

### Event Payload

| Name           | Type            | Description                                         |
| -------------- | --------------- | -----------------------------------------------     |
| accounts       | `array[object]` | Array of accounts that contain updated transactions |
| » id           | `string`        | Account Id                                          |
| » transactions | `array[string]` | Array of transactions ids                           |

<aside class="notice">
This event is not sent on the initial connection to a financial institution or when reauthorising a connection.
</aside>

## Deleted transactions

Id: `deletedTransactions`

Event that notifies when an account has been automatically updated and transactions have been marked as deleted.

This can happen when the financial institution marks a transaction as deleted or stop sending it.

### Event Payload

| Name           | Type            | Description                                         |
| -------------- | --------------- | -----------------------------------------------     |
| accounts       | `array[object]` | Array of accounts that contain deleted transactions |
| » id           | `string`        | Account Id                                          |
| » transactions | `array[string]` | Array of transactions ids                           |

<aside class="notice">
This event is not sent on the initial connection to a financial institution or when reauthorising a connection.
</aside>

## Restored transactions

Id: `restoredTransactions`

Event that notifies when an account has been automatically updated and transactions have been restored.

This event happens only when a transactions was previously marked as deleted but it has been restored.
This is useful to resolve issues when the financial institutions fix data inconsistencies sent from their API.

### Event Payload

| Name           | Type            | Description                                         |
| -------------- | --------------- | -----------------------------------------------     |
| accounts       | `array[object]` | Array of accounts that contain restored transactions |
| » id           | `string`        | Account Id                                          |
| » transactions | `array[string]` | Array of transactions ids                           |

<aside class="notice">
This event is not sent on the initial connection to a financial institution or when reauthorising a connection.
</aside>


<h1 id="moneyhub-data-api">Moneyhub Data API v2.0.0</h1>

> Scroll down for code samples, example requests and responses. Select a language for code samples from the tabs above or the mobile navigation menu.

Documentation for the Moneyhub data API. <br/>Authentication is via bearer token. <br/><br/>Swagger docs:<br/><br/> * <a href='https://api.moneyhub.co.uk/docs/'>https://api.moneyhub.co.uk/docs/</a>

Base URLs:

* <a href="https://api.moneyhub.co.uk/v2.0">https://api.moneyhub.co.uk/v2.0</a>

# Authentication

* API Key (Bearer)
    - Parameter Name: **Authorization**, in: header. 

<h1 id="moneyhub-data-api-accounts">accounts</h1>

## get__accounts

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/accounts \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/accounts HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/accounts',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/accounts', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/accounts", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /accounts`

*Retrieve all accounts for a user*

Requires **accounts:read** scope.

<h3 id="get__accounts-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|limit|query|integer|false|The total number of records to retrieve|
|offset|query|integer|false|The offset at which to start retrieving records|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "accountName": "Cash ISA",
      "currency": "GBP",
      "balance": {
        "date": "2018-08-12",
        "amount": {
          "value": -300023,
          "currency": "GBP"
        }
      },
      "details": {
        "AER": 1.3,
        "APR": 13.1,
        "sortCodeAccountNumber": "60161331926819",
        "iban": "GB2960161331926819",
        "creditLimit": 150000,
        "endDate": "2020-01-01",
        "fixedDate": "2019-01-01",
        "interestFreePeriod": 12,
        "interestType": "fixed",
        "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
        "monthlyRepayment": 60000,
        "overdraftLimit": 150000,
        "postcode": "bs1 1aa",
        "runningCost": 20000,
        "runningCostPeriod": "month",
        "term": 13,
        "yearlyAppreciation": -10
      },
      "transactionData": {
        "count": 6,
        "earliestDate": "2017-11-28",
        "lastDate": "2018-05-28"
      },
      "dateAdded": "2018-07-10T11:39:44+00:00",
      "dateModified": "2018-07-10T11:39:44+00:00",
      "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
      "providerName": "HSBC",
      "providerReference": "hsbc",
      "connectionId": "049c10ab871e8d60aa891c0ae368322d:639cf079-a585-4852-8b4d-1ebd17f4d2cb",
      "providerId": "049c10ab871e8d60aa891c0ae368322d",
      "accountReference": "3201",
      "accountType": "personal",
      "type": "cash:current",
      "performanceScore": {
        "totals": {
          "openingBalance": {
            "date": "2018-08-12",
            "amount": {
              "value": 300023,
              "currency": "GBP"
            }
          },
          "currentBalance": {
            "date": "2018-08-12",
            "amount": {
              "value": 300023,
              "currency": "GBP"
            }
          },
          "contributions": 240098,
          "withdrawals": 20067,
          "nonContributionGrowth": 340054,
          "growthRate": 35.98,
          "annualisedGrowthRate": 60.98
        },
        "months": [
          {
            "date": "2018-08",
            "openingBalance": 300023,
            "nonContributionGrowth": 1567,
            "aer": 35.98
          }
        ]
      }
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__accounts-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Accounts Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="get__accounts-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[Account](#schemaaccount)]|false|none|none|
|»» accountName|string|true|none|The name of the account|
|»» currency|string|false|none|The currency of the account|
|»» balance|object|true|none|none|
|»»» amount|object|true|none|none|
|»»»» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|»»»» currency|string|true|none|The currency of the balance taken from the account|
|»»» date|string(date)|true|none|The date of the balance|
|»» details|object|true|none|none|
|»»» AER|number|false|none|For cash and savings accounts. Interest rate expessed as a percentage 'Annual Equivalent Rate'.|
|»»» APR|number|false|none|For credit cards, mortgages and loans. Interest rate expessed as a percentage 'Annual Percentage Rate'.|
|»»» sortCodeAccountNumber|string|false|none|For cash accounts. Populated with the 6 digit Sort Code and 8 digit Account Number. It requires the `accounts_details:read` scope.|
|»»» iban|string|false|none|For cash accounts. Populated with the full IBAN number. It requires the `accounts_details:read` scope.|
|»»» creditLimit|integer|false|none|For credit cards. The agreed overdraft limit of the account in minor units of the currency.|
|»»» endDate|string(date)|false|none|For Mortgages and loans. The date at which the loan/mortgage will finish.|
|»»» fixedDate|string(date)|false|none|For Mortgages. The date at which the current fixed rate ends|
|»»» interestFreePeriod|integer|false|none|For loans. The length in months of the interest free period|
|»»» interestType|string|false|none|For mortgages. The interest type|
|»»» linkedProperty|string|false|none|For Mortgages. The id of an associated property account|
|»»» monthlyRepayment|integer|false|none|For mortgages and loans. The monthly amount due to the mortgage provider in minor units of the currency.|
|»»» overdraftLimit|number|false|none|For cash accounts. The agreed overdraft limit of the account in minor units of the currency.|
|»»» postcode|string|false|none|For properties. The postcode of the property|
|»»» runningCost|integer|false|none|For assets. The running cost in minor units of the currency.|
|»»» runningCostPeriod|string|false|none|For assets. The running cost period|
|»»» term|integer|false|none|For mortgages. The term of the mortgage in months.|
|»»» yearlyAppreciation|number|false|none|For assets. The rate of appreciation as a percentage, negative values indicate that the asset will depreciate|
|»» transactionData|object|false|none|none|
|»»» count|integer|true|none|none|
|»»» earliestDate|string(date)|true|none|none|
|»»» lastDate|string(date)|true|none|none|
|»» dateAdded|string(date-time)|true|none|The date at which the account was added.|
|»» dateModified|string(date-time)|true|none|The date at which the account was last modified|
|»» id|string|true|none|The unique identity of the account.|
|»» providerName|string|false|none|The name of the provider of the account.|
|»» providerReference|string|false|none|The unique reference name of the provider of the account.|
|»» connectionId|string(([\w-])+:([\w-])+)|false|none|The id of the connection of the account. This value is not present for accounts created manually by the user.|
|»» providerId|string(API|DEMO|([\w-])+)|false|none|The id of the provider of the account. Accounts created using the api have a value of 'API'. Accounts crated for a Test user have a value of 'DEMO'. This value is not present for accounts created manually by the user.|
|»» accountReference|string|false|none|A reference number for the account - typically the last 4 digits of the account number|
|»» accountType|string|false|none|The type of account (personal/business)|
|»» type|string|true|none|The type of account - this will determine the data available in the details field|
|»» performanceScore|object|false|none|Performance score of investment and pension accounts. Once that an account has at least 3 balances the score will be provided. Please note that this is an experimental feature.|
|»»» totals|object|true|none|none|
|»»»» openingBalance|object|false|none|none|
|»»»»» date|string(date)|false|none|none|
|»»»»» amount|object|false|none|none|
|»»»»»» value|integer|true|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»»»» currency|string|true|none|none|
|»»»»» currentBalance|object|false|none|none|
|»»»»»» date|string(date)|false|none|none|
|»»»»»» amount|object|false|none|none|
|»»»»»»» value|integer|true|none|The current balance in minor units of the currency, eg. pennies for GBP|
|»»»»»»» currency|string|true|none|none|
|»»»»»» contributions|integer|false|none|The contributions in minor units of the currency, eg. pennies for GBP|
|»»»»»» withdrawals|integer|false|none|The withdrawals in minor units of the currency, eg. pennies for GBP|
|»»»»»» nonContributionGrowth|integer|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»»»» growthRate|number|false|none|The growth rate expressed in percentage|
|»»»»»» annualisedGrowthRate|number|false|none|The annualised growth rate expressed in percentage|
|»»»»» months|[object]|true|none|none|
|»»»»»» date|string|false|none|Date in the format YYYY-MM|
|»»»»»» openingBalance|integer|false|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»»»» nonContributionGrowth|number|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»»»» aer|number|false|none|The aer expressed in percentage|
|»»»»» links|[Links](#schemalinks)|false|none|none|
|»»»»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»»»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»»»»» self|string(uri)|true|none|The url of the current resource(s)|
|»»»»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|interestType|fixed|
|interestType|variable|
|runningCostPeriod|month|
|runningCostPeriod|year|
|accountType|personal|
|accountType|business|
|type|cash:current|
|type|savings|
|type|card|
|type|investment|
|type|loan|
|type|mortgage:repayment|
|type|mortgage:interestOnly|
|type|pension|
|type|asset|
|type|properties:residential|
|type|properties:buyToLet|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## post__accounts

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/accounts \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/accounts HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "accountName": "Account name",
  "providerName": "Provider name",
  "type": "cash:current",
  "accountType": "personal",
  "balance": {
    "date": "2018-08-12",
    "amount": {
      "value": -300023
    }
  },
  "details": {
    "AER": 1.3,
    "APR": 13.1,
    "creditLimit": 150000,
    "endDate": "2020-01-01",
    "fixedDate": "2019-01-01",
    "interestFreePeriod": 12,
    "interestType": "fixed",
    "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "monthlyRepayment": 60000,
    "overdraftLimit": 150000,
    "postcode": "bs1 1aa",
    "runningCost": 20000,
    "runningCostPeriod": "month",
    "term": 13,
    "yearlyAppreciation": -10
  }
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts',
{
  method: 'POST',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/accounts',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/accounts', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/accounts", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /accounts`

*Create a single account for a user*

Requires **accounts:read** and **accounts:write:all** scopes.

> Body parameter

```json
{
  "accountName": "Account name",
  "providerName": "Provider name",
  "type": "cash:current",
  "accountType": "personal",
  "balance": {
    "date": "2018-08-12",
    "amount": {
      "value": -300023
    }
  },
  "details": {
    "AER": 1.3,
    "APR": 13.1,
    "creditLimit": 150000,
    "endDate": "2020-01-01",
    "fixedDate": "2019-01-01",
    "interestFreePeriod": 12,
    "interestType": "fixed",
    "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "monthlyRepayment": 60000,
    "overdraftLimit": 150000,
    "postcode": "bs1 1aa",
    "runningCost": 20000,
    "runningCostPeriod": "month",
    "term": 13,
    "yearlyAppreciation": -10
  }
}
```

<h3 id="post__accounts-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|body|body|[AccountPost](#schemaaccountpost)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "accountName": "Cash ISA",
    "currency": "GBP",
    "balance": {
      "date": "2018-08-12",
      "amount": {
        "value": -300023,
        "currency": "GBP"
      }
    },
    "details": {
      "AER": 1.3,
      "APR": 13.1,
      "sortCodeAccountNumber": "60161331926819",
      "iban": "GB2960161331926819",
      "creditLimit": 150000,
      "endDate": "2020-01-01",
      "fixedDate": "2019-01-01",
      "interestFreePeriod": 12,
      "interestType": "fixed",
      "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
      "monthlyRepayment": 60000,
      "overdraftLimit": 150000,
      "postcode": "bs1 1aa",
      "runningCost": 20000,
      "runningCostPeriod": "month",
      "term": 13,
      "yearlyAppreciation": -10
    },
    "transactionData": {
      "count": 6,
      "earliestDate": "2017-11-28",
      "lastDate": "2018-05-28"
    },
    "dateAdded": "2018-07-10T11:39:44+00:00",
    "dateModified": "2018-07-10T11:39:44+00:00",
    "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "providerName": "HSBC",
    "providerReference": "hsbc",
    "connectionId": "049c10ab871e8d60aa891c0ae368322d:639cf079-a585-4852-8b4d-1ebd17f4d2cb",
    "providerId": "049c10ab871e8d60aa891c0ae368322d",
    "accountReference": "3201",
    "accountType": "personal",
    "type": "cash:current",
    "performanceScore": {
      "totals": {
        "openingBalance": {
          "date": "2018-08-12",
          "amount": {
            "value": 300023,
            "currency": "GBP"
          }
        },
        "currentBalance": {
          "date": "2018-08-12",
          "amount": {
            "value": 300023,
            "currency": "GBP"
          }
        },
        "contributions": 240098,
        "withdrawals": 20067,
        "nonContributionGrowth": 340054,
        "growthRate": 35.98,
        "annualisedGrowthRate": 60.98
      },
      "months": [
        {
          "date": "2018-08",
          "openingBalance": 300023,
          "nonContributionGrowth": 1567,
          "aer": 35.98
        }
      ]
    }
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__accounts-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Account Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing query parameters - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="post__accounts-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» accountName|string|true|none|The name of the account|
|»» currency|string|false|none|The currency of the account|
|»» balance|object|true|none|none|
|»»» amount|object|true|none|none|
|»»»» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|»»»» currency|string|true|none|The currency of the balance taken from the account|
|»»» date|string(date)|true|none|The date of the balance|
|»» details|object|true|none|none|
|»»» AER|number|false|none|For cash and savings accounts. Interest rate expessed as a percentage 'Annual Equivalent Rate'.|
|»»» APR|number|false|none|For credit cards, mortgages and loans. Interest rate expessed as a percentage 'Annual Percentage Rate'.|
|»»» sortCodeAccountNumber|string|false|none|For cash accounts. Populated with the 6 digit Sort Code and 8 digit Account Number. It requires the `accounts_details:read` scope.|
|»»» iban|string|false|none|For cash accounts. Populated with the full IBAN number. It requires the `accounts_details:read` scope.|
|»»» creditLimit|integer|false|none|For credit cards. The agreed overdraft limit of the account in minor units of the currency.|
|»»» endDate|string(date)|false|none|For Mortgages and loans. The date at which the loan/mortgage will finish.|
|»»» fixedDate|string(date)|false|none|For Mortgages. The date at which the current fixed rate ends|
|»»» interestFreePeriod|integer|false|none|For loans. The length in months of the interest free period|
|»»» interestType|string|false|none|For mortgages. The interest type|
|»»» linkedProperty|string|false|none|For Mortgages. The id of an associated property account|
|»»» monthlyRepayment|integer|false|none|For mortgages and loans. The monthly amount due to the mortgage provider in minor units of the currency.|
|»»» overdraftLimit|number|false|none|For cash accounts. The agreed overdraft limit of the account in minor units of the currency.|
|»»» postcode|string|false|none|For properties. The postcode of the property|
|»»» runningCost|integer|false|none|For assets. The running cost in minor units of the currency.|
|»»» runningCostPeriod|string|false|none|For assets. The running cost period|
|»»» term|integer|false|none|For mortgages. The term of the mortgage in months.|
|»»» yearlyAppreciation|number|false|none|For assets. The rate of appreciation as a percentage, negative values indicate that the asset will depreciate|
|»» transactionData|object|false|none|none|
|»»» count|integer|true|none|none|
|»»» earliestDate|string(date)|true|none|none|
|»»» lastDate|string(date)|true|none|none|
|»» dateAdded|string(date-time)|true|none|The date at which the account was added.|
|»» dateModified|string(date-time)|true|none|The date at which the account was last modified|
|»» id|string|true|none|The unique identity of the account.|
|»» providerName|string|false|none|The name of the provider of the account.|
|»» providerReference|string|false|none|The unique reference name of the provider of the account.|
|»» connectionId|string(([\w-])+:([\w-])+)|false|none|The id of the connection of the account. This value is not present for accounts created manually by the user.|
|»» providerId|string(API|DEMO|([\w-])+)|false|none|The id of the provider of the account. Accounts created using the api have a value of 'API'. Accounts crated for a Test user have a value of 'DEMO'. This value is not present for accounts created manually by the user.|
|»» accountReference|string|false|none|A reference number for the account - typically the last 4 digits of the account number|
|»» accountType|string|false|none|The type of account (personal/business)|
|»» type|string|true|none|The type of account - this will determine the data available in the details field|
|»» performanceScore|object|false|none|Performance score of investment and pension accounts. Once that an account has at least 3 balances the score will be provided. Please note that this is an experimental feature.|
|»»» totals|object|true|none|none|
|»»»» openingBalance|object|false|none|none|
|»»»»» date|string(date)|false|none|none|
|»»»»» amount|object|false|none|none|
|»»»»»» value|integer|true|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»»»» currency|string|true|none|none|
|»»»»» currentBalance|object|false|none|none|
|»»»»»» date|string(date)|false|none|none|
|»»»»»» amount|object|false|none|none|
|»»»»»»» value|integer|true|none|The current balance in minor units of the currency, eg. pennies for GBP|
|»»»»»»» currency|string|true|none|none|
|»»»»»» contributions|integer|false|none|The contributions in minor units of the currency, eg. pennies for GBP|
|»»»»»» withdrawals|integer|false|none|The withdrawals in minor units of the currency, eg. pennies for GBP|
|»»»»»» nonContributionGrowth|integer|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»»»» growthRate|number|false|none|The growth rate expressed in percentage|
|»»»»»» annualisedGrowthRate|number|false|none|The annualised growth rate expressed in percentage|
|»»»»» months|[object]|true|none|none|
|»»»»»» date|string|false|none|Date in the format YYYY-MM|
|»»»»»» openingBalance|integer|false|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»»»» nonContributionGrowth|number|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»»»» aer|number|false|none|The aer expressed in percentage|
|»»»»» links|[Links](#schemalinks)|false|none|none|
|»»»»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»»»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»»»»» self|string(uri)|true|none|The url of the current resource(s)|
|»»»»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|interestType|fixed|
|interestType|variable|
|runningCostPeriod|month|
|runningCostPeriod|year|
|accountType|personal|
|accountType|business|
|type|cash:current|
|type|savings|
|type|card|
|type|investment|
|type|loan|
|type|mortgage:repayment|
|type|mortgage:interestOnly|
|type|pension|
|type|asset|
|type|properties:residential|
|type|properties:buyToLet|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__accounts_{accountId}

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /accounts/{accountId}`

*Retrieve a single account*

Requires **accounts:read** scope.

<h3 id="get__accounts_{accountid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|

> Example responses

> 200 Response

```json
{
  "data": {
    "accountName": "Cash ISA",
    "currency": "GBP",
    "balance": {
      "date": "2018-08-12",
      "amount": {
        "value": -300023,
        "currency": "GBP"
      }
    },
    "details": {
      "AER": 1.3,
      "APR": 13.1,
      "sortCodeAccountNumber": "60161331926819",
      "iban": "GB2960161331926819",
      "creditLimit": 150000,
      "endDate": "2020-01-01",
      "fixedDate": "2019-01-01",
      "interestFreePeriod": 12,
      "interestType": "fixed",
      "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
      "monthlyRepayment": 60000,
      "overdraftLimit": 150000,
      "postcode": "bs1 1aa",
      "runningCost": 20000,
      "runningCostPeriod": "month",
      "term": 13,
      "yearlyAppreciation": -10
    },
    "transactionData": {
      "count": 6,
      "earliestDate": "2017-11-28",
      "lastDate": "2018-05-28"
    },
    "dateAdded": "2018-07-10T11:39:44+00:00",
    "dateModified": "2018-07-10T11:39:44+00:00",
    "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "providerName": "HSBC",
    "providerReference": "hsbc",
    "connectionId": "049c10ab871e8d60aa891c0ae368322d:639cf079-a585-4852-8b4d-1ebd17f4d2cb",
    "providerId": "049c10ab871e8d60aa891c0ae368322d",
    "accountReference": "3201",
    "accountType": "personal",
    "type": "cash:current",
    "performanceScore": {
      "totals": {
        "openingBalance": {
          "date": "2018-08-12",
          "amount": {
            "value": 300023,
            "currency": "GBP"
          }
        },
        "currentBalance": {
          "date": "2018-08-12",
          "amount": {
            "value": 300023,
            "currency": "GBP"
          }
        },
        "contributions": 240098,
        "withdrawals": 20067,
        "nonContributionGrowth": 340054,
        "growthRate": 35.98,
        "annualisedGrowthRate": 60.98
      },
      "months": [
        {
          "date": "2018-08",
          "openingBalance": 300023,
          "nonContributionGrowth": 1567,
          "aer": 35.98
        }
      ]
    }
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__accounts_{accountid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Account Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="get__accounts_{accountid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» accountName|string|true|none|The name of the account|
|»» currency|string|false|none|The currency of the account|
|»» balance|object|true|none|none|
|»»» amount|object|true|none|none|
|»»»» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|»»»» currency|string|true|none|The currency of the balance taken from the account|
|»»» date|string(date)|true|none|The date of the balance|
|»» details|object|true|none|none|
|»»» AER|number|false|none|For cash and savings accounts. Interest rate expessed as a percentage 'Annual Equivalent Rate'.|
|»»» APR|number|false|none|For credit cards, mortgages and loans. Interest rate expessed as a percentage 'Annual Percentage Rate'.|
|»»» sortCodeAccountNumber|string|false|none|For cash accounts. Populated with the 6 digit Sort Code and 8 digit Account Number. It requires the `accounts_details:read` scope.|
|»»» iban|string|false|none|For cash accounts. Populated with the full IBAN number. It requires the `accounts_details:read` scope.|
|»»» creditLimit|integer|false|none|For credit cards. The agreed overdraft limit of the account in minor units of the currency.|
|»»» endDate|string(date)|false|none|For Mortgages and loans. The date at which the loan/mortgage will finish.|
|»»» fixedDate|string(date)|false|none|For Mortgages. The date at which the current fixed rate ends|
|»»» interestFreePeriod|integer|false|none|For loans. The length in months of the interest free period|
|»»» interestType|string|false|none|For mortgages. The interest type|
|»»» linkedProperty|string|false|none|For Mortgages. The id of an associated property account|
|»»» monthlyRepayment|integer|false|none|For mortgages and loans. The monthly amount due to the mortgage provider in minor units of the currency.|
|»»» overdraftLimit|number|false|none|For cash accounts. The agreed overdraft limit of the account in minor units of the currency.|
|»»» postcode|string|false|none|For properties. The postcode of the property|
|»»» runningCost|integer|false|none|For assets. The running cost in minor units of the currency.|
|»»» runningCostPeriod|string|false|none|For assets. The running cost period|
|»»» term|integer|false|none|For mortgages. The term of the mortgage in months.|
|»»» yearlyAppreciation|number|false|none|For assets. The rate of appreciation as a percentage, negative values indicate that the asset will depreciate|
|»» transactionData|object|false|none|none|
|»»» count|integer|true|none|none|
|»»» earliestDate|string(date)|true|none|none|
|»»» lastDate|string(date)|true|none|none|
|»» dateAdded|string(date-time)|true|none|The date at which the account was added.|
|»» dateModified|string(date-time)|true|none|The date at which the account was last modified|
|»» id|string|true|none|The unique identity of the account.|
|»» providerName|string|false|none|The name of the provider of the account.|
|»» providerReference|string|false|none|The unique reference name of the provider of the account.|
|»» connectionId|string(([\w-])+:([\w-])+)|false|none|The id of the connection of the account. This value is not present for accounts created manually by the user.|
|»» providerId|string(API|DEMO|([\w-])+)|false|none|The id of the provider of the account. Accounts created using the api have a value of 'API'. Accounts crated for a Test user have a value of 'DEMO'. This value is not present for accounts created manually by the user.|
|»» accountReference|string|false|none|A reference number for the account - typically the last 4 digits of the account number|
|»» accountType|string|false|none|The type of account (personal/business)|
|»» type|string|true|none|The type of account - this will determine the data available in the details field|
|»» performanceScore|object|false|none|Performance score of investment and pension accounts. Once that an account has at least 3 balances the score will be provided. Please note that this is an experimental feature.|
|»»» totals|object|true|none|none|
|»»»» openingBalance|object|false|none|none|
|»»»»» date|string(date)|false|none|none|
|»»»»» amount|object|false|none|none|
|»»»»»» value|integer|true|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»»»» currency|string|true|none|none|
|»»»»» currentBalance|object|false|none|none|
|»»»»»» date|string(date)|false|none|none|
|»»»»»» amount|object|false|none|none|
|»»»»»»» value|integer|true|none|The current balance in minor units of the currency, eg. pennies for GBP|
|»»»»»»» currency|string|true|none|none|
|»»»»»» contributions|integer|false|none|The contributions in minor units of the currency, eg. pennies for GBP|
|»»»»»» withdrawals|integer|false|none|The withdrawals in minor units of the currency, eg. pennies for GBP|
|»»»»»» nonContributionGrowth|integer|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»»»» growthRate|number|false|none|The growth rate expressed in percentage|
|»»»»»» annualisedGrowthRate|number|false|none|The annualised growth rate expressed in percentage|
|»»»»» months|[object]|true|none|none|
|»»»»»» date|string|false|none|Date in the format YYYY-MM|
|»»»»»» openingBalance|integer|false|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»»»» nonContributionGrowth|number|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»»»» aer|number|false|none|The aer expressed in percentage|
|»»»»» links|[Links](#schemalinks)|false|none|none|
|»»»»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»»»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»»»»» self|string(uri)|true|none|The url of the current resource(s)|
|»»»»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|interestType|fixed|
|interestType|variable|
|runningCostPeriod|month|
|runningCostPeriod|year|
|accountType|personal|
|accountType|business|
|type|cash:current|
|type|savings|
|type|card|
|type|investment|
|type|loan|
|type|mortgage:repayment|
|type|mortgage:interestOnly|
|type|pension|
|type|asset|
|type|properties:residential|
|type|properties:buyToLet|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## patch__accounts_{accountId}

> Code samples

```shell
# You can also use wget
curl -X PATCH https://api.moneyhub.co.uk/v2.0/accounts/{accountId} \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
PATCH https://api.moneyhub.co.uk/v2.0/accounts/{accountId} HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}',
  method: 'patch',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "accountName": "Account name",
  "providerName": "Provider name",
  "details": {
    "AER": 1.3,
    "APR": 13.1,
    "creditLimit": 150000,
    "endDate": "2020-01-01",
    "fixedDate": "2019-01-01",
    "interestFreePeriod": 12,
    "interestType": "fixed",
    "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "monthlyRepayment": 60000,
    "overdraftLimit": 150000,
    "postcode": "bs1 1aa",
    "runningCost": 20000,
    "runningCostPeriod": "month",
    "term": 13,
    "yearlyAppreciation": -10
  }
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}',
{
  method: 'PATCH',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.patch 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.patch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("PATCH");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("PATCH", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`PATCH /accounts/{accountId}`

*Update a single account*

Requires **accounts:read** and **account:write:all** scopes.

> Body parameter

```json
{
  "accountName": "Account name",
  "providerName": "Provider name",
  "details": {
    "AER": 1.3,
    "APR": 13.1,
    "creditLimit": 150000,
    "endDate": "2020-01-01",
    "fixedDate": "2019-01-01",
    "interestFreePeriod": 12,
    "interestType": "fixed",
    "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "monthlyRepayment": 60000,
    "overdraftLimit": 150000,
    "postcode": "bs1 1aa",
    "runningCost": 20000,
    "runningCostPeriod": "month",
    "term": 13,
    "yearlyAppreciation": -10
  }
}
```

<h3 id="patch__accounts_{accountid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|
|body|body|[AccountPatch](#schemaaccountpatch)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "accountName": "Cash ISA",
    "currency": "GBP",
    "balance": {
      "date": "2018-08-12",
      "amount": {
        "value": -300023,
        "currency": "GBP"
      }
    },
    "details": {
      "AER": 1.3,
      "APR": 13.1,
      "sortCodeAccountNumber": "60161331926819",
      "iban": "GB2960161331926819",
      "creditLimit": 150000,
      "endDate": "2020-01-01",
      "fixedDate": "2019-01-01",
      "interestFreePeriod": 12,
      "interestType": "fixed",
      "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
      "monthlyRepayment": 60000,
      "overdraftLimit": 150000,
      "postcode": "bs1 1aa",
      "runningCost": 20000,
      "runningCostPeriod": "month",
      "term": 13,
      "yearlyAppreciation": -10
    },
    "transactionData": {
      "count": 6,
      "earliestDate": "2017-11-28",
      "lastDate": "2018-05-28"
    },
    "dateAdded": "2018-07-10T11:39:44+00:00",
    "dateModified": "2018-07-10T11:39:44+00:00",
    "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "providerName": "HSBC",
    "providerReference": "hsbc",
    "connectionId": "049c10ab871e8d60aa891c0ae368322d:639cf079-a585-4852-8b4d-1ebd17f4d2cb",
    "providerId": "049c10ab871e8d60aa891c0ae368322d",
    "accountReference": "3201",
    "accountType": "personal",
    "type": "cash:current",
    "performanceScore": {
      "totals": {
        "openingBalance": {
          "date": "2018-08-12",
          "amount": {
            "value": 300023,
            "currency": "GBP"
          }
        },
        "currentBalance": {
          "date": "2018-08-12",
          "amount": {
            "value": 300023,
            "currency": "GBP"
          }
        },
        "contributions": 240098,
        "withdrawals": 20067,
        "nonContributionGrowth": 340054,
        "growthRate": 35.98,
        "annualisedGrowthRate": 60.98
      },
      "months": [
        {
          "date": "2018-08",
          "openingBalance": 300023,
          "nonContributionGrowth": 1567,
          "aer": 35.98
        }
      ]
    }
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="patch__accounts_{accountid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Account Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="patch__accounts_{accountid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» accountName|string|true|none|The name of the account|
|»» currency|string|false|none|The currency of the account|
|»» balance|object|true|none|none|
|»»» amount|object|true|none|none|
|»»»» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|»»»» currency|string|true|none|The currency of the balance taken from the account|
|»»» date|string(date)|true|none|The date of the balance|
|»» details|object|true|none|none|
|»»» AER|number|false|none|For cash and savings accounts. Interest rate expessed as a percentage 'Annual Equivalent Rate'.|
|»»» APR|number|false|none|For credit cards, mortgages and loans. Interest rate expessed as a percentage 'Annual Percentage Rate'.|
|»»» sortCodeAccountNumber|string|false|none|For cash accounts. Populated with the 6 digit Sort Code and 8 digit Account Number. It requires the `accounts_details:read` scope.|
|»»» iban|string|false|none|For cash accounts. Populated with the full IBAN number. It requires the `accounts_details:read` scope.|
|»»» creditLimit|integer|false|none|For credit cards. The agreed overdraft limit of the account in minor units of the currency.|
|»»» endDate|string(date)|false|none|For Mortgages and loans. The date at which the loan/mortgage will finish.|
|»»» fixedDate|string(date)|false|none|For Mortgages. The date at which the current fixed rate ends|
|»»» interestFreePeriod|integer|false|none|For loans. The length in months of the interest free period|
|»»» interestType|string|false|none|For mortgages. The interest type|
|»»» linkedProperty|string|false|none|For Mortgages. The id of an associated property account|
|»»» monthlyRepayment|integer|false|none|For mortgages and loans. The monthly amount due to the mortgage provider in minor units of the currency.|
|»»» overdraftLimit|number|false|none|For cash accounts. The agreed overdraft limit of the account in minor units of the currency.|
|»»» postcode|string|false|none|For properties. The postcode of the property|
|»»» runningCost|integer|false|none|For assets. The running cost in minor units of the currency.|
|»»» runningCostPeriod|string|false|none|For assets. The running cost period|
|»»» term|integer|false|none|For mortgages. The term of the mortgage in months.|
|»»» yearlyAppreciation|number|false|none|For assets. The rate of appreciation as a percentage, negative values indicate that the asset will depreciate|
|»» transactionData|object|false|none|none|
|»»» count|integer|true|none|none|
|»»» earliestDate|string(date)|true|none|none|
|»»» lastDate|string(date)|true|none|none|
|»» dateAdded|string(date-time)|true|none|The date at which the account was added.|
|»» dateModified|string(date-time)|true|none|The date at which the account was last modified|
|»» id|string|true|none|The unique identity of the account.|
|»» providerName|string|false|none|The name of the provider of the account.|
|»» providerReference|string|false|none|The unique reference name of the provider of the account.|
|»» connectionId|string(([\w-])+:([\w-])+)|false|none|The id of the connection of the account. This value is not present for accounts created manually by the user.|
|»» providerId|string(API|DEMO|([\w-])+)|false|none|The id of the provider of the account. Accounts created using the api have a value of 'API'. Accounts crated for a Test user have a value of 'DEMO'. This value is not present for accounts created manually by the user.|
|»» accountReference|string|false|none|A reference number for the account - typically the last 4 digits of the account number|
|»» accountType|string|false|none|The type of account (personal/business)|
|»» type|string|true|none|The type of account - this will determine the data available in the details field|
|»» performanceScore|object|false|none|Performance score of investment and pension accounts. Once that an account has at least 3 balances the score will be provided. Please note that this is an experimental feature.|
|»»» totals|object|true|none|none|
|»»»» openingBalance|object|false|none|none|
|»»»»» date|string(date)|false|none|none|
|»»»»» amount|object|false|none|none|
|»»»»»» value|integer|true|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»»»» currency|string|true|none|none|
|»»»»» currentBalance|object|false|none|none|
|»»»»»» date|string(date)|false|none|none|
|»»»»»» amount|object|false|none|none|
|»»»»»»» value|integer|true|none|The current balance in minor units of the currency, eg. pennies for GBP|
|»»»»»»» currency|string|true|none|none|
|»»»»»» contributions|integer|false|none|The contributions in minor units of the currency, eg. pennies for GBP|
|»»»»»» withdrawals|integer|false|none|The withdrawals in minor units of the currency, eg. pennies for GBP|
|»»»»»» nonContributionGrowth|integer|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»»»» growthRate|number|false|none|The growth rate expressed in percentage|
|»»»»»» annualisedGrowthRate|number|false|none|The annualised growth rate expressed in percentage|
|»»»»» months|[object]|true|none|none|
|»»»»»» date|string|false|none|Date in the format YYYY-MM|
|»»»»»» openingBalance|integer|false|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»»»» nonContributionGrowth|number|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»»»» aer|number|false|none|The aer expressed in percentage|
|»»»»» links|[Links](#schemalinks)|false|none|none|
|»»»»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»»»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»»»»» self|string(uri)|true|none|The url of the current resource(s)|
|»»»»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|interestType|fixed|
|interestType|variable|
|runningCostPeriod|month|
|runningCostPeriod|year|
|accountType|personal|
|accountType|business|
|type|cash:current|
|type|savings|
|type|card|
|type|investment|
|type|loan|
|type|mortgage:repayment|
|type|mortgage:interestOnly|
|type|pension|
|type|asset|
|type|properties:residential|
|type|properties:buyToLet|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## delete__accounts_{accountId}

> Code samples

```shell
# You can also use wget
curl -X DELETE https://api.moneyhub.co.uk/v2.0/accounts/{accountId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
DELETE https://api.moneyhub.co.uk/v2.0/accounts/{accountId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}',
  method: 'delete',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}',
{
  method: 'DELETE',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.delete 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.delete('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("DELETE");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("DELETE", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`DELETE /accounts/{accountId}`

*Delete a single account*

This endpoint can only be used to delete accounts created using the POST /accounts endpoint. Accounts created when connecting to a financial institution can only be deleted by removing the connection they belong to. Requires **accounts:write:all** scope.

<h3 id="delete__accounts_{accountid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|

> Example responses

> 401 Response

```json
{
  "code": "string",
  "message": "string",
  "correlationId": "string"
}
```

<h3 id="delete__accounts_{accountid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|204|[No Content](https://tools.ietf.org/html/rfc7231#section-6.3.5)|Succesful Response|None|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not Found|[Error](#schemaerror)|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__accounts_{accountId}_balances

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /accounts/{accountId}/balances`

*Retrieve the historical balances for an account*

Requires **accounts:read** scope.

<h3 id="get__accounts_{accountid}_balances-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "date": "2018-08-12",
      "amount": {
        "value": -300023,
        "currency": "GBP"
      }
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__accounts_{accountid}_balances-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Balances Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="get__accounts_{accountid}_balances-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[Balance](#schemabalance)]|false|none|none|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the balance taken from the account|
|»» date|string(date)|true|none|The date of the balance|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## post__accounts_{accountId}_balances

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "date": "2018-08-12",
  "amount": {
    "value": -300023
  }
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances',
{
  method: 'POST',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/balances", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /accounts/{accountId}/balances`

*Add a new balance for an account*

Requires **accounts:read** and either of **accounts:write** or **accounts:write:all** scopes.

> Body parameter

```json
{
  "date": "2018-08-12",
  "amount": {
    "value": -300023
  }
}
```

<h3 id="post__accounts_{accountid}_balances-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|
|body|body|[BalancePost](#schemabalancepost)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "date": "2018-08-12",
    "amount": {
      "value": -300023,
      "currency": "GBP"
    }
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__accounts_{accountid}_balances-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Balance Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing query parameters - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Balance Response|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="post__accounts_{accountid}_balances-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[Balance](#schemabalance)|false|none|none|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the balance taken from the account|
|»» date|string(date)|true|none|The date of the balance|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__accounts_{accountId}_holdings

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /accounts/{accountId}/holdings`

*Retrieve the holdings for an account*

Requires **accounts:read** scope.

<h3 id="get__accounts_{accountid}_holdings-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "date": "2018-07-11",
      "items": [
        {
          "codes": [
            {
              "code": "GB00B39TQT96",
              "type": "ISIN"
            }
          ],
          "description": "Dynamic Bond Fund",
          "quantity": 4548.09,
          "total": {
            "value": 90334.16,
            "currency": "GBP"
          },
          "unitPrice": {
            "value": 19.862,
            "currency": "GBP"
          }
        }
      ]
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__accounts_{accountid}_holdings-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Holdings Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="get__accounts_{accountid}_holdings-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[HoldingsValuation](#schemaholdingsvaluation)]|false|none|none|
|»» date|string(date)|true|none|Date of the valuation|
|»» items|[any]|true|none|none|
|»»» codes|[object]|true|none|none|
|»»»» code|string|false|none|none|
|»»»» type|string|false|none|none|
|»»» description|string|true|none|none|
|»»» quantity|number|true|none|none|
|»»» total|object|true|none|none|
|»»»» value|number|true|none|The value of the total in minor units of the currency, eg. pennies for GBP.|
|»»»» currency|string|true|none|The currency of the total.|
|»»» unitPrice|object|true|none|none|
|»»»» value|number|true|none|The value of the unit price in minor units of the currency, eg. pennies for GBP.|
|»»»» currency|string|true|none|The currency of the unit price.|
|»»» links|[Links](#schemalinks)|false|none|none|
|»»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»»» self|string(uri)|true|none|The url of the current resource(s)|
|»»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|type|ISIN|
|type|SEDOL|
|type|MEX|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__accounts_{accountId}_holdings_{holdingId}

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings/{holdingId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings/{holdingId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings/{holdingId}',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings/{holdingId}',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings/{holdingId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings/{holdingId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings/{holdingId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings/{holdingId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /accounts/{accountId}/holdings/{holdingId}`

*Retrieve the holding for an account with matched ISIN codes*

Requires **accounts:read** scope.

<h3 id="get__accounts_{accountid}_holdings_{holdingid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|
|holdingId|path|string|true|The Holding Id|

> Example responses

> 200 Response

```json
{
  "data": {
    "id": "6a8b01768a50b095a8c0445c1b080900f1096fd0b6e40863c6b82d63607c3bbe",
    "history": [
      {
        "total": {
          "value": 90334.16,
          "currency": "GBP"
        },
        "unitPrice": {
          "value": 19.862,
          "currency": "GBP"
        },
        "quantity": 4548.09,
        "date": "2018-07-11"
      }
    ],
    "matched": [
      {
        "isin": "GB00B39TQT96",
        "name": "Dynamic Bond Fund Acc",
        "score": 0.5,
        "priceGBP": 4548.09,
        "price": {
          "value": 90334.16,
          "currency": "GBP"
        },
        "date": "2018-07-11"
      }
    ],
    "codes": [
      {
        "code": "GB00B39TQT96",
        "type": "ISIN"
      }
    ],
    "name": "Dynamic Bond Fund",
    "quantity": 4548.09,
    "total": {
      "value": 90334.16,
      "currency": "GBP"
    },
    "unitPrice": {
      "value": 19.862,
      "currency": "GBP"
    }
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__accounts_{accountid}_holdings_{holdingid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Holding Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="get__accounts_{accountid}_holdings_{holdingid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» id|string|true|none|The id of the holding|
|»» history|[object]|true|none|none|
|»»» total|object|false|none|none|
|»»»» value|number|true|none|The value of the total in minor units of the currency, eg. pennies for GBP.|
|»»»» currency|string|true|none|The currency of the total.|
|»»» unitPrice|object|false|none|none|
|»»»» value|number|true|none|The value of the unit price in minor units of the currency, eg. pennies for GBP.|
|»»»» currency|string|true|none|The currency of the unit price.|
|»»» quantity|number|false|none|none|
|»»» date|string(date)|false|none|Date of the valuation|
|»» matched|[object]|true|none|none|
|»»» isin|string|false|none|The ISIN code of the match|
|»»» name|string|false|none|The name of the match|
|»»» score|number|false|none|none|
|»»» priceGBP|number|false|none|none|
|»»» price|object|false|none|none|
|»»»» value|number|true|none|The unit price in minor units of the currency (e.g. pence for GBP)|
|»»»» currency|string|true|none|The currency of the matched holding|
|»»» date|string(date)|false|none|Date of the valuation|
|»» codes|[object]|true|none|none|
|»»» code|string|false|none|none|
|»»» type|string|false|none|none|
|»» name|string|true|none|none|
|»» quantity|number|true|none|none|
|»» total|object|true|none|none|
|»»» value|number|true|none|The value of the total in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the total.|
|»» unitPrice|object|true|none|none|
|»»» value|number|true|none|The value of the unit price in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the unit price.|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|type|ISIN|
|type|SEDOL|
|type|MEX|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__accounts_{accountId}_holdings-with-matches

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings-with-matches \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings-with-matches HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings-with-matches',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings-with-matches',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings-with-matches',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings-with-matches', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings-with-matches");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/holdings-with-matches", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /accounts/{accountId}/holdings-with-matches`

*Retrieve the holdings for an account with matched ISIN codes*

Requires **accounts:read** scope.

<h3 id="get__accounts_{accountid}_holdings-with-matches-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "date": "2018-07-11",
      "id": "6a8b01768a50b095a8c0445c1b080900f1096fd0b6e40863c6b82d63607c3bbe",
      "matched": [
        {
          "isin": "GB00B39TQT96",
          "name": "Dynamic Bond Fund Acc",
          "score": 0.5,
          "priceGBP": 4548.09,
          "price": {
            "value": 90334.16,
            "currency": "GBP"
          },
          "date": "2018-07-11"
        }
      ],
      "codes": [
        {
          "code": "GB00B39TQT96",
          "type": "ISIN"
        }
      ],
      "name": "Dynamic Bond Fund",
      "quantity": 4548.09,
      "total": {
        "value": 90334.16,
        "currency": "GBP"
      },
      "unitPrice": {
        "value": 19.862,
        "currency": "GBP"
      }
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__accounts_{accountid}_holdings-with-matches-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Holdings Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="get__accounts_{accountid}_holdings-with-matches-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[HoldingWithMatches](#schemaholdingwithmatches)]|false|none|none|
|»» date|string(date)|false|none|Date of the valuation|
|»» id|string|true|none|The id of the holding|
|»» matched|[object]|true|none|none|
|»»» isin|string|false|none|The ISIN code of the match|
|»»» name|string|false|none|The name of the match|
|»»» score|number|false|none|none|
|»»» priceGBP|number|false|none|none|
|»»» price|object|false|none|none|
|»»»» value|number|true|none|The unit price in minor units of the currency (e.g. pence for GBP)|
|»»»» currency|string|true|none|The currency of the matched holding|
|»»» date|string(date)|false|none|Date of the valuation|
|»» codes|[object]|true|none|none|
|»»» code|string|false|none|none|
|»»» type|string|false|none|none|
|»» name|string|true|none|none|
|»» quantity|number|true|none|none|
|»» total|object|true|none|none|
|»»» value|number|true|none|The value of the total in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the total.|
|»» unitPrice|object|true|none|none|
|»»» value|number|true|none|The value of the unit price in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the unit price.|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|type|ISIN|
|type|SEDOL|
|type|MEX|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__accounts_{accountId}_counterparties

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/counterparties \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/counterparties HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/counterparties',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/counterparties',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/counterparties',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/counterparties', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/counterparties");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/counterparties", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /accounts/{accountId}/counterparties`

*Retrieve the counterparties for an account*

Requires **accounts:read** and **transactions:read:all** scope.

<h3 id="get__accounts_{accountid}_counterparties-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "id": "4bac27393bdd9777ce02453256c5577cd02275510b2227f473d03f533924f877",
      "label": "British Gas"
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__accounts_{accountid}_counterparties-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Counterparties Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="get__accounts_{accountid}_counterparties-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[Counterparty](#schemacounterparty)]|false|none|none|
|»» id|string|true|none|The unique identifier for the counterparty.|
|»» label|string|true|none|A label describing the counterparty|
|»» type|string|true|none|The type of counterpary (specific to an account, or globally recognoised accross all users)|
|»» companyName|string|false|none|The full name of the company (only for global counterparties)|
|»» logo|string|false|none|The url to the company logo (only for global counterparties)|
|»» website|string|false|none|The url to the company website (only for global counterparties)|
|»» mcc|object|false|none|none|
|»»» code|string|false|none|The merchant category code (only for global counterparties)|
|»»» name|string|false|none|The merchant category code name (only for global counterparties)|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|type|global|
|type|local|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## post__accounts_{accountId}_recurring-transactions

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/recurring-transactions \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/recurring-transactions HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/recurring-transactions',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/recurring-transactions',
{
  method: 'POST',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/recurring-transactions',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/recurring-transactions', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/recurring-transactions");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/accounts/{accountId}/recurring-transactions", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /accounts/{accountId}/recurring-transactions`

*Create an estimate of the recurring transactions for an account*

Requires **accounts:read** and **transactions:read:all** scope.

<h3 id="post__accounts_{accountid}_recurring-transactions-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|accountId|path|string(uuid)|true|The Account Id|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "counterpartyId": "4bac27393bdd9777ce02453256c5577cd02275510b2227f473d03f533924f877",
      "amount": {
        "value": -300023,
        "currency": "GBP"
      },
      "amountRange": {
        "value": 5000,
        "currency": "GBP"
      },
      "monthlyAmount": {
        "value": 5000,
        "currency": "GBP"
      },
      "predictionSource": "moneyhub",
      "monthlyAverageOnly": false,
      "dates": [
        "2019-03-07",
        "2019-04-07",
        "2019-05-07"
      ]
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__accounts_{accountid}_recurring-transactions-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Recurring Transactions Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="post__accounts_{accountid}_recurring-transactions-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[RecurringTransactionEstimate](#schemarecurringtransactionestimate)]|false|none|none|
|»» counterpartyId|string|false|none|The id of the counterparty that the estimate is for|
|»» amount|object|false|none|none|
|»»» value|integer|true|none|The average prected amount of the recurring transaction in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the predicted amount taken from the account|
|»» amountRange|object|false|none|none|
|»»» value|integer|true|none|The prected range of the recurring transaction in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the predicted range taken from the account|
|»» monthlyAmount|object|false|none|none|
|»»» value|integer|true|none|The prected monthly amount for this counterparty, regardless of how many transactions in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the monthly amount taken from the account|
|»» predictionSource|string|false|none|The source of the prediction|
|»» monthlyAverageOnly|boolean|false|none|A flag indiciating whether the predictions are based only on a monthly average or not. If the predictions are based solely on monthly averages then the dates array will be defaulted to the end of the month for the next 3 motnhs.|
|»» dates|[string]|false|none|none|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|predictionSource|moneyhub|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

<h1 id="moneyhub-data-api-transactions">transactions</h1>

## get__transactions

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/transactions \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/transactions HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/transactions',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/transactions',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/transactions',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/transactions', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/transactions");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/transactions", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /transactions`

*Retrieve all transactions for a user*

Requires any of **transactions:read:all**, **transactions:read:in**, or **transactions:read:out** scopes.

<h3 id="get__transactions-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|limit|query|integer|false|The total number of records to retrieve|
|offset|query|integer|false|The offset at which to start retrieveing records|
|startDate|query|string(date)|false|The earliest date to receive transactions from (inclusive)|
|endDate|query|string(date)|false|The latest date to receive transactions from (inclusive)|
|startDateModified|query|string(date)|false|The earliest date the transactions were modified (inclusive)|
|endDateModified|query|string(date)|false|The latest date the transactions were modified (inclusive)|
|text|query|string|false|The text to filter transactions descriptions/notes by|
|categoryId|query|string|false|The category id to filter transactions by|
|accountId|query|string|false|The account id to filter transactions by|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
      "amount": {
        "value": -2323,
        "currency": "GBP"
      },
      "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
      "categoryIdConfirmed": false,
      "date": "2018-07-10T12:00:00+00:00",
      "dateModified": "2018-07-10T11:39:46.506Z",
      "id": "c390a94f-3824-4cdf-8d02-b0c5304d9f66",
      "longDescription": "Card Purchase SAINSBURYS S/MKTS  BCC",
      "notes": "Some notes about the transaction",
      "shortDescription": "Sainsburys S/mkts",
      "counterpartyId": "30be8fa43f30fc285e4c479e9dfd6a1dec2bead8ee6cc6276b8dac152c565e9e",
      "status": "posted"
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__transactions-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Transactions Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing query parameters - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="get__transactions-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[Transaction](#schematransaction)]|false|none|none|
|»» accountId|string|false|none|The id of the account the transaction belongs to|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The amount of the transaction in minor units of the currency, eg. pennies for GBP, negative means money going out of an account, positive means money coming into an account.|
|»»» currency|string|true|none|The currency of the amount|
|»» categoryId|string|true|none|The category id. Standard categories are prefixed with 'std', custom categories are prefixed with 'cus'|
|»» categoryIdConfirmed|boolean|true|none|Flag indificating whether the user has confirmed the category id as correct|
|»» date|string(date-time)|true|none|The date that the transaction occurred. Where available this will contain an accurate time, where the time is not available it will default to midday.|
|»» dateModified|string(date-time)|true|none|The date the transaction was modified - this could be when it was added, or a category changed, or when notes were added|
|»» id|string|true|none|The unique id of the transaction|
|»» longDescription|string|true|none|The full text description of the transactions - often as it is represented on the users bank statement|
|»» notes|string|true|none|Arbitrary text that a user can add about a transaction|
|»» shortDescription|string|true|none|A cleaned up and shorter description of the transaction, this can be editied|
|»» counterpartyId|string|false|none|An identifier for the counterparty|
|»» status|string|true|none|Whether the transaction has been posted (booked) or is still a pending transaction. During the transition from pending to posted the description will normally change.|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|status|posted|
|status|pending|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## post__transactions

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/transactions \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/transactions HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/transactions',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
  "amount": {
    "value": -2300
  },
  "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
  "categoryIdConfirmed": true,
  "longDescription": "New transaction",
  "shortDescription": "transaction",
  "notes": "notes",
  "status": "posted",
  "date": "2018-07-10T12:00:00+00:00"
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/transactions',
{
  method: 'POST',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/transactions',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/transactions', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/transactions");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/transactions", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /transactions`

*Create a single transaction for a user*

Requires **transactions:read:all** and **transactions:write:all** scopes.

> Body parameter

```json
{
  "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
  "amount": {
    "value": -2300
  },
  "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
  "categoryIdConfirmed": true,
  "longDescription": "New transaction",
  "shortDescription": "transaction",
  "notes": "notes",
  "status": "posted",
  "date": "2018-07-10T12:00:00+00:00"
}
```

<h3 id="post__transactions-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|body|body|[TransactionPost](#schematransactionpost)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
    "amount": {
      "value": -2323,
      "currency": "GBP"
    },
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "categoryIdConfirmed": false,
    "date": "2018-07-10T12:00:00+00:00",
    "dateModified": "2018-07-10T11:39:46.506Z",
    "id": "c390a94f-3824-4cdf-8d02-b0c5304d9f66",
    "longDescription": "Card Purchase SAINSBURYS S/MKTS  BCC",
    "notes": "Some notes about the transaction",
    "shortDescription": "Sainsburys S/mkts",
    "counterpartyId": "30be8fa43f30fc285e4c479e9dfd6a1dec2bead8ee6cc6276b8dac152c565e9e",
    "status": "posted"
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__transactions-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Transaction Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing query parameters - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="post__transactions-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» accountId|string|false|none|The id of the account the transaction belongs to|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The amount of the transaction in minor units of the currency, eg. pennies for GBP, negative means money going out of an account, positive means money coming into an account.|
|»»» currency|string|true|none|The currency of the amount|
|»» categoryId|string|true|none|The category id. Standard categories are prefixed with 'std', custom categories are prefixed with 'cus'|
|»» categoryIdConfirmed|boolean|true|none|Flag indificating whether the user has confirmed the category id as correct|
|»» date|string(date-time)|true|none|The date that the transaction occurred. Where available this will contain an accurate time, where the time is not available it will default to midday.|
|»» dateModified|string(date-time)|true|none|The date the transaction was modified - this could be when it was added, or a category changed, or when notes were added|
|»» id|string|true|none|The unique id of the transaction|
|»» longDescription|string|true|none|The full text description of the transactions - often as it is represented on the users bank statement|
|»» notes|string|true|none|Arbitrary text that a user can add about a transaction|
|»» shortDescription|string|true|none|A cleaned up and shorter description of the transaction, this can be editied|
|»» counterpartyId|string|false|none|An identifier for the counterparty|
|»» status|string|true|none|Whether the transaction has been posted (booked) or is still a pending transaction. During the transition from pending to posted the description will normally change.|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|status|posted|
|status|pending|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__transactions_{transactionId}

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/transactions/{transactionId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/transactions/{transactionId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /transactions/{transactionId}`

*Retrieve a single transaction*

Requires **transactions:read:all** scope.

<h3 id="get__transactions_{transactionid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|transactionId|path|string(uuid)|true|The transaction id|

> Example responses

> 200 Response

```json
{
  "data": {
    "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
    "amount": {
      "value": -2323,
      "currency": "GBP"
    },
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "categoryIdConfirmed": false,
    "date": "2018-07-10T12:00:00+00:00",
    "dateModified": "2018-07-10T11:39:46.506Z",
    "id": "c390a94f-3824-4cdf-8d02-b0c5304d9f66",
    "longDescription": "Card Purchase SAINSBURYS S/MKTS  BCC",
    "notes": "Some notes about the transaction",
    "shortDescription": "Sainsburys S/mkts",
    "counterpartyId": "30be8fa43f30fc285e4c479e9dfd6a1dec2bead8ee6cc6276b8dac152c565e9e",
    "status": "posted"
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__transactions_{transactionid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Transaction Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="get__transactions_{transactionid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» accountId|string|false|none|The id of the account the transaction belongs to|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The amount of the transaction in minor units of the currency, eg. pennies for GBP, negative means money going out of an account, positive means money coming into an account.|
|»»» currency|string|true|none|The currency of the amount|
|»» categoryId|string|true|none|The category id. Standard categories are prefixed with 'std', custom categories are prefixed with 'cus'|
|»» categoryIdConfirmed|boolean|true|none|Flag indificating whether the user has confirmed the category id as correct|
|»» date|string(date-time)|true|none|The date that the transaction occurred. Where available this will contain an accurate time, where the time is not available it will default to midday.|
|»» dateModified|string(date-time)|true|none|The date the transaction was modified - this could be when it was added, or a category changed, or when notes were added|
|»» id|string|true|none|The unique id of the transaction|
|»» longDescription|string|true|none|The full text description of the transactions - often as it is represented on the users bank statement|
|»» notes|string|true|none|Arbitrary text that a user can add about a transaction|
|»» shortDescription|string|true|none|A cleaned up and shorter description of the transaction, this can be editied|
|»» counterpartyId|string|false|none|An identifier for the counterparty|
|»» status|string|true|none|Whether the transaction has been posted (booked) or is still a pending transaction. During the transition from pending to posted the description will normally change.|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|status|posted|
|status|pending|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## patch__transactions_{transactionId}

> Code samples

```shell
# You can also use wget
curl -X PATCH https://api.moneyhub.co.uk/v2.0/transactions/{transactionId} \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
PATCH https://api.moneyhub.co.uk/v2.0/transactions/{transactionId} HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}',
  method: 'patch',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
  "amount": {
    "value": -51000
  },
  "categoryId": "std:09f5c144-6d90-4228-98c6-cac1331d874b",
  "categoryIdConfirmed": true,
  "longDescription": "New long description",
  "shortDescription": "New short description",
  "notes": "New notes",
  "status": "posted",
  "date": "2018-07-10T12:00:00+00:00"
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}',
{
  method: 'PATCH',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.patch 'https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.patch('https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("PATCH");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("PATCH", "https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`PATCH /transactions/{transactionId}`

*Update a single transaction*

Requires **transactions:read:all** and either of **transactions:write** or **transactions:write:all** scopes.

> Body parameter

```json
{
  "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
  "amount": {
    "value": -51000
  },
  "categoryId": "std:09f5c144-6d90-4228-98c6-cac1331d874b",
  "categoryIdConfirmed": true,
  "longDescription": "New long description",
  "shortDescription": "New short description",
  "notes": "New notes",
  "status": "posted",
  "date": "2018-07-10T12:00:00+00:00"
}
```

<h3 id="patch__transactions_{transactionid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|transactionId|path|string(uuid)|true|The transaction id|
|body|body|[TransactionPatch](#schematransactionpatch)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
    "amount": {
      "value": -2323,
      "currency": "GBP"
    },
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "categoryIdConfirmed": false,
    "date": "2018-07-10T12:00:00+00:00",
    "dateModified": "2018-07-10T11:39:46.506Z",
    "id": "c390a94f-3824-4cdf-8d02-b0c5304d9f66",
    "longDescription": "Card Purchase SAINSBURYS S/MKTS  BCC",
    "notes": "Some notes about the transaction",
    "shortDescription": "Sainsburys S/mkts",
    "counterpartyId": "30be8fa43f30fc285e4c479e9dfd6a1dec2bead8ee6cc6276b8dac152c565e9e",
    "status": "posted"
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="patch__transactions_{transactionid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Transaction Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<h3 id="patch__transactions_{transactionid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» accountId|string|false|none|The id of the account the transaction belongs to|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The amount of the transaction in minor units of the currency, eg. pennies for GBP, negative means money going out of an account, positive means money coming into an account.|
|»»» currency|string|true|none|The currency of the amount|
|»» categoryId|string|true|none|The category id. Standard categories are prefixed with 'std', custom categories are prefixed with 'cus'|
|»» categoryIdConfirmed|boolean|true|none|Flag indificating whether the user has confirmed the category id as correct|
|»» date|string(date-time)|true|none|The date that the transaction occurred. Where available this will contain an accurate time, where the time is not available it will default to midday.|
|»» dateModified|string(date-time)|true|none|The date the transaction was modified - this could be when it was added, or a category changed, or when notes were added|
|»» id|string|true|none|The unique id of the transaction|
|»» longDescription|string|true|none|The full text description of the transactions - often as it is represented on the users bank statement|
|»» notes|string|true|none|Arbitrary text that a user can add about a transaction|
|»» shortDescription|string|true|none|A cleaned up and shorter description of the transaction, this can be editied|
|»» counterpartyId|string|false|none|An identifier for the counterparty|
|»» status|string|true|none|Whether the transaction has been posted (booked) or is still a pending transaction. During the transition from pending to posted the description will normally change.|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|status|posted|
|status|pending|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## delete__transactions_{transactionId}

> Code samples

```shell
# You can also use wget
curl -X DELETE https://api.moneyhub.co.uk/v2.0/transactions/{transactionId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
DELETE https://api.moneyhub.co.uk/v2.0/transactions/{transactionId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}',
  method: 'delete',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}',
{
  method: 'DELETE',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.delete 'https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.delete('https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("DELETE");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("DELETE", "https://api.moneyhub.co.uk/v2.0/transactions/{transactionId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`DELETE /transactions/{transactionId}`

*Delete a single transaction*

Requires **transactions:write:all** scope.

<h3 id="delete__transactions_{transactionid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|transactionId|path|string(uuid)|true|The transaction id|

> Example responses

> 401 Response

```json
{
  "code": "string",
  "message": "string",
  "correlationId": "string"
}
```

<h3 id="delete__transactions_{transactionid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|204|[No Content](https://tools.ietf.org/html/rfc7231#section-6.3.5)|Succesful Transaction Response|None|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not found|[Error](#schemaerror)|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## post__transactions-collection

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/transactions-collection \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/transactions-collection HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/transactions-collection',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '[
  {
    "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
    "amount": {
      "value": -4500
    },
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "categoryIdConfirmed": true,
    "longDescription": "Long description 1",
    "shortDescription": "description 1",
    "notes": "notes",
    "status": "posted",
    "date": "2018-07-10T12:00:00+00:00"
  },
  {
    "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
    "amount": {
      "value": 7800
    },
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "longDescription": "Long description 2",
    "notes": "notes",
    "status": "pending",
    "date": "2018-07-10T12:00:00+00:00"
  }
]';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/transactions-collection',
{
  method: 'POST',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/transactions-collection',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/transactions-collection', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/transactions-collection");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/transactions-collection", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /transactions-collection`

*Create multiple transactions for a user*

Requires **transactions:read:all** and **transactions:write:all** scopes.

> Body parameter

```json
[
  {
    "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
    "amount": {
      "value": -4500
    },
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "categoryIdConfirmed": true,
    "longDescription": "Long description 1",
    "shortDescription": "description 1",
    "notes": "notes",
    "status": "posted",
    "date": "2018-07-10T12:00:00+00:00"
  },
  {
    "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
    "amount": {
      "value": 7800
    },
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "longDescription": "Long description 2",
    "notes": "notes",
    "status": "pending",
    "date": "2018-07-10T12:00:00+00:00"
  }
]
```

<h3 id="post__transactions-collection-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|body|body|[TransactionCollectionPost](#schematransactioncollectionpost)|false|none|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "id": "c390a94f-3824-4cdf-8d02-b0c5304d9f66"
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__transactions-collection-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Transaction Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing query parameters - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="post__transactions-collection-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[object]|false|none|none|
|»» id|string(uuid)|true|none|The unique id of the transaction|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

<h1 id="moneyhub-data-api-categories">categories</h1>

## get__categories

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/categories \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/categories HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/categories',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/categories',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/categories',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/categories', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/categories");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/categories", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /categories`

*Retrieve all categories for a user*

Requires **categories:read** scope.

<h3 id="get__categories-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|limit|query|integer|false|The total number of records to retrieve|
|offset|query|integer|false|The offset at which to start retrieving records|
|type|query|string|false|The types of categories to be returned|

#### Enumerated Values

|Parameter|Value|
|---|---|
|type|personal|
|type|business|
|type|all|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "categoryId": "std:338d2636-7f88-491d-8129-255c98da1eb8",
      "name": "Days Out",
      "key": "wages",
      "group": "group:2"
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__categories-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Categories Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="get__categories-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[Category](#schemacategory)]|false|none|none|
|»» categoryId|string|true|none|The id of the category. Custom categories are prefixed with 'cus:'|
|»» name|string|false|none|The name of the category - only applicable for custom categories|
|»» key|string|false|none|A text key for standard categories|
|»» group|string|true|none|The category group to which the category belongs|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## post__categories

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/categories \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/categories HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/categories',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "group": "group:1",
  "name": "Bus travel"
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/categories',
{
  method: 'POST',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/categories',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/categories', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/categories");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/categories", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /categories`

*Add a new custom category for a user*

Requires **categories:write** scope.

> Body parameter

```json
{
  "group": "group:1",
  "name": "Bus travel"
}
```

<h3 id="post__categories-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|body|body|[CategoryPost](#schemacategorypost)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "categoryId": "std:338d2636-7f88-491d-8129-255c98da1eb8",
    "name": "Days Out",
    "key": "wages",
    "group": "group:2"
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__categories-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Category Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing query parameters - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="post__categories-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[Category](#schemacategory)|false|none|none|
|»» categoryId|string|true|none|The id of the category. Custom categories are prefixed with 'cus:'|
|»» name|string|false|none|The name of the category - only applicable for custom categories|
|»» key|string|false|none|A text key for standard categories|
|»» group|string|true|none|The category group to which the category belongs|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__categories_{categoryId}

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/categories/{categoryId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/categories/{categoryId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/categories/{categoryId}',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/categories/{categoryId}',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/categories/{categoryId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/categories/{categoryId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/categories/{categoryId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/categories/{categoryId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /categories/{categoryId}`

*Retrieve a single category*

Requires **categories:read** scope.

<h3 id="get__categories_{categoryid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|categoryId|path|string|true|The Category Id|
|type|query|string|false|The types of categories to be returned|

#### Enumerated Values

|Parameter|Value|
|---|---|
|type|personal|
|type|business|
|type|all|

> Example responses

> 200 Response

```json
{
  "data": {
    "categoryId": "std:338d2636-7f88-491d-8129-255c98da1eb8",
    "name": "Days Out",
    "key": "wages",
    "group": "group:2"
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__categories_{categoryid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Category Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not Found|[Error](#schemaerror)|

<h3 id="get__categories_{categoryid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[Category](#schemacategory)|false|none|none|
|»» categoryId|string|true|none|The id of the category. Custom categories are prefixed with 'cus:'|
|»» name|string|false|none|The name of the category - only applicable for custom categories|
|»» key|string|false|none|A text key for standard categories|
|»» group|string|true|none|The category group to which the category belongs|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__category-groups

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/category-groups \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/category-groups HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/category-groups',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/category-groups',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/category-groups',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/category-groups', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/category-groups");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/category-groups", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /category-groups`

*Retrieve all category groups for a user*

Requires **categories:read** scope.

<h3 id="get__category-groups-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|type|query|string|false|The types of categories to be returned|

#### Enumerated Values

|Parameter|Value|
|---|---|
|type|personal|
|type|business|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "id": "group-1",
      "key": "bills"
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__category-groups-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Category Groups Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="get__category-groups-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[CategoryGroup](#schemacategorygroup)]|false|none|none|
|»» id|string|true|none|The id of the category group.|
|»» key|string|true|none|A text key for the category group|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

<h1 id="moneyhub-data-api-spending-analysis">spending analysis</h1>

## post__spending-analysis

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/spending-analysis \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/spending-analysis HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/spending-analysis',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "dates": [
    {
      "name": "currentMonth",
      "from": "2018-10-01",
      "to": "2018-10-31"
    },
    {
      "name": "previousMonth",
      "from": "2018-09-01",
      "to": "2018-09-30"
    }
  ],
  "accountIds": [
    "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
  ],
  "categoryIds": [
    "std:338d2636-7f88-491d-8129-255c98da1eb8"
  ]
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/spending-analysis',
{
  method: 'POST',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/spending-analysis',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/spending-analysis', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/spending-analysis");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/spending-analysis", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /spending-analysis`

*Retrieve spending analysis by categories and accounts*

Defaults to all categories and accounts if none specified.
<br />The categories field in the response has a breakdown of the total by categories for the given periods. You can expect to also receive the breakdown for income and transfer categories.
<br />The 'total' field in the response calculates the total outgoing expenditure for the given periods. This calculation do not include income and transfers.
<br />Requires **spending_analysis:read** scope.

> Body parameter

```json
{
  "dates": [
    {
      "name": "currentMonth",
      "from": "2018-10-01",
      "to": "2018-10-31"
    },
    {
      "name": "previousMonth",
      "from": "2018-09-01",
      "to": "2018-09-30"
    }
  ],
  "accountIds": [
    "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
  ],
  "categoryIds": [
    "std:338d2636-7f88-491d-8129-255c98da1eb8"
  ]
}
```

<h3 id="post__spending-analysis-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|body|body|[SpendingAnalysisPost](#schemaspendinganalysispost)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "categories": [
      {
        "categoryId": "std:65ebdcdb-c46b-478f-bbbc-feabeb0b4342",
        "categoryGroup": "group:2",
        "currentMonth": -2000,
        "previousMonth": -1000
      },
      {
        "categoryId": "std:379c7ed2-27f3-401f-b581-f6507934f0f0",
        "categoryGroup": "group:3",
        "currentMonth": -1500,
        "previousMonth": -500
      }
    ],
    "total": {
      "currentMonth": -3500,
      "previousMonth": -1500
    }
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__spending-analysis-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Spending Analysis Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="post__spending-analysis-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» categories|[object]|false|none|none|
|»»» categoryId|string|false|none|none|
|»»» categoryGroup|string|false|none|none|
|»» total|object|false|none|none|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

<h1 id="moneyhub-data-api-spending-goals">spending goals</h1>

## get__spending-goals

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/spending-goals \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/spending-goals HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/spending-goals',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/spending-goals',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/spending-goals',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/spending-goals', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/spending-goals");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/spending-goals", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /spending-goals`

*Retrieve all spending goals for a user*

Requires **spending_goals:read** scope.

<h3 id="get__spending-goals-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|limit|query|integer|false|The total number of records to retrieve|
|offset|query|integer|false|The offset at which to start retrieveing records|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
      "dateCreated": "2018-07-11T03:51:08+00:00",
      "periodType": "monthly",
      "periodStart": "01",
      "id": "0b4e6488-6de0-420c-8f56-fee665707d57",
      "amount": {
        "value": 40000,
        "currency": "GBP"
      },
      "spending": [
        {
          "date": "2018-07",
          "spent": -35000
        }
      ]
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__spending-goals-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Spending Goals Response|Inline|

<h3 id="get__spending-goals-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[SpendingGoal](#schemaspendinggoal)]|false|none|none|
|»» categoryId|string|true|none|none|
|»» dateCreated|string(date-time)|true|none|none|
|»» periodType|string|true|none|none|
|»» periodStart|string|true|none|none|
|»» id|string|true|none|The unique id of the spending goal|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The value of the amount in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the amount.|
|»» spending|[object]|true|none|none|
|»»» date|string|true|none|none|
|»»» spent|integer|true|none|The spending analysis amount of the specified month expressed in minor units of the currency.|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|periodType|monthly|
|periodType|annual|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## post__spending-goals

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/spending-goals \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/spending-goals HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/spending-goals',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "categoryId": "std:379c7ed2-27f3-401f-b581-f6507934f0f0",
  "amount": {
    "value": 50000
  }
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/spending-goals',
{
  method: 'POST',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/spending-goals',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/spending-goals', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/spending-goals");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/spending-goals", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /spending-goals`

*Create a single spending goal for a user*

Requires **spending_goals:read** and **spending_goals:write:all** scopes.

> Body parameter

```json
{
  "categoryId": "std:379c7ed2-27f3-401f-b581-f6507934f0f0",
  "amount": {
    "value": 50000
  }
}
```

<h3 id="post__spending-goals-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|body|body|[SpendingGoalPost](#schemaspendinggoalpost)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "dateCreated": "2018-07-11T03:51:08+00:00",
    "periodType": "monthly",
    "periodStart": "01",
    "id": "0b4e6488-6de0-420c-8f56-fee665707d57",
    "amount": {
      "value": 40000,
      "currency": "GBP"
    },
    "spending": [
      {
        "date": "2018-07",
        "spent": -35000
      }
    ]
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__spending-goals-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Spending Goal Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing query parameters - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="post__spending-goals-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» categoryId|string|true|none|none|
|»» dateCreated|string(date-time)|true|none|none|
|»» periodType|string|true|none|none|
|»» periodStart|string|true|none|none|
|»» id|string|true|none|The unique id of the spending goal|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The value of the amount in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the amount.|
|»» spending|[object]|true|none|none|
|»»» date|string|true|none|none|
|»»» spent|integer|true|none|The spending analysis amount of the specified month expressed in minor units of the currency.|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|periodType|monthly|
|periodType|annual|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__spending-goals_{goalId}

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /spending-goals/{goalId}`

*Retrieve a single spending goal*

Requires **spending_goals:read** scope.

<h3 id="get__spending-goals_{goalid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|goalId|path|string(uuid)|true|The Goal Id|

> Example responses

> 200 Response

```json
{
  "data": {
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "dateCreated": "2018-07-11T03:51:08+00:00",
    "periodType": "monthly",
    "periodStart": "01",
    "id": "0b4e6488-6de0-420c-8f56-fee665707d57",
    "amount": {
      "value": 40000,
      "currency": "GBP"
    },
    "spending": [
      {
        "date": "2018-07",
        "spent": -35000
      }
    ]
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__spending-goals_{goalid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Spending Goal Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not Found|[Error](#schemaerror)|

<h3 id="get__spending-goals_{goalid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» categoryId|string|true|none|none|
|»» dateCreated|string(date-time)|true|none|none|
|»» periodType|string|true|none|none|
|»» periodStart|string|true|none|none|
|»» id|string|true|none|The unique id of the spending goal|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The value of the amount in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the amount.|
|»» spending|[object]|true|none|none|
|»»» date|string|true|none|none|
|»»» spent|integer|true|none|The spending analysis amount of the specified month expressed in minor units of the currency.|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|periodType|monthly|
|periodType|annual|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## patch__spending-goals_{goalId}

> Code samples

```shell
# You can also use wget
curl -X PATCH https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId} \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
PATCH https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId} HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}',
  method: 'patch',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "categoryId": "std:379c7ed2-27f3-401f-b581-f6507934f0f0",
  "amount": {
    "value": 300
  }
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}',
{
  method: 'PATCH',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.patch 'https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.patch('https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("PATCH");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("PATCH", "https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`PATCH /spending-goals/{goalId}`

*Update a single spending goal*

Requires **spending_goals:read spending_goals:write** scope.

> Body parameter

```json
{
  "categoryId": "std:379c7ed2-27f3-401f-b581-f6507934f0f0",
  "amount": {
    "value": 300
  }
}
```

<h3 id="patch__spending-goals_{goalid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|goalId|path|string(uuid)|true|The Goal Id|
|body|body|[SpendingGoalPatch](#schemaspendinggoalpatch)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "dateCreated": "2018-07-11T03:51:08+00:00",
    "periodType": "monthly",
    "periodStart": "01",
    "id": "0b4e6488-6de0-420c-8f56-fee665707d57",
    "amount": {
      "value": 40000,
      "currency": "GBP"
    },
    "spending": [
      {
        "date": "2018-07",
        "spent": -35000
      }
    ]
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="patch__spending-goals_{goalid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Spending Goal Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not Found|[Error](#schemaerror)|

<h3 id="patch__spending-goals_{goalid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» categoryId|string|true|none|none|
|»» dateCreated|string(date-time)|true|none|none|
|»» periodType|string|true|none|none|
|»» periodStart|string|true|none|none|
|»» id|string|true|none|The unique id of the spending goal|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The value of the amount in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the amount.|
|»» spending|[object]|true|none|none|
|»»» date|string|true|none|none|
|»»» spent|integer|true|none|The spending analysis amount of the specified month expressed in minor units of the currency.|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|periodType|monthly|
|periodType|annual|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## delete__spending-goals_{goalId}

> Code samples

```shell
# You can also use wget
curl -X DELETE https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
DELETE https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}',
  method: 'delete',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}',
{
  method: 'DELETE',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.delete 'https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.delete('https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("DELETE");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("DELETE", "https://api.moneyhub.co.uk/v2.0/spending-goals/{goalId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`DELETE /spending-goals/{goalId}`

*Delete a single spending goal*

Requires **spending_goals:write:all** scope.

<h3 id="delete__spending-goals_{goalid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|goalId|path|string(uuid)|true|The Goal Id|

> Example responses

> 401 Response

```json
{
  "code": "string",
  "message": "string",
  "correlationId": "string"
}
```

<h3 id="delete__spending-goals_{goalid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|204|[No Content](https://tools.ietf.org/html/rfc7231#section-6.3.5)|Succesful Spending Goal Response|None|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not Found|[Error](#schemaerror)|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

<h1 id="moneyhub-data-api-savings-goals">savings goals</h1>

## get__savings-goals

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/savings-goals \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/savings-goals HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/savings-goals',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/savings-goals',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/savings-goals',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/savings-goals', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/savings-goals");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/savings-goals", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /savings-goals`

*Retrieve all saving goals for a user*

Requires **savings_goals:read** scope.

<h3 id="get__savings-goals-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|limit|query|integer|false|The total number of records to retrieve|
|offset|query|integer|false|The offset at which to start retrieving records|

> Example responses

> 200 Response

```json
{
  "data": [
    {
      "id": "27c316ef-8dfa-4a4b-b0a2-4979b7db1543",
      "name": "House deposit",
      "amount": {
        "value": 500000,
        "currency": "GBP"
      },
      "dateCreated": "2018-10-11T03:51:08+00:00",
      "imageUrl": "url",
      "notes": "Notes",
      "progressPercentage": 33.3,
      "progressAmount": 500000,
      "accounts": [
        {
          "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
        }
      ]
    }
  ],
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__savings-goals-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="get__savings-goals-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[[SavingsGoals](#schemasavingsgoals)]|false|none|none|
|»» id|string|true|none|Unique id of the saving goal.|
|»» name|string|true|none|Name for the savings goal.|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The target amount in minor unit in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the amount|
|»» dateCreated|string(date-time)|true|none|The date at which the savings goal was added.|
|»» imageUrl|string|false|none|none|
|»» notes|string|false|none|Arbitrary text that a user can add about a savings goal.|
|»» progressPercentage|number|false|none|Progresss achieved towards the target amount represented in percentage.|
|»» progressAmount|integer|false|none|Progresss achieved towards the target amount by adding up the balances of the selected accounts.|
|»» accounts|[object]|true|none|Accounts that will be taken into account towards the target amount.|
|»»» id|string|true|none|Id of the account|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## post__savings-goals

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/savings-goals \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/savings-goals HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/savings-goals',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "name": "House Deposit",
  "amount": {
    "value": 1800000
  },
  "imageUrl": "Image url",
  "notes": "Notes",
  "accounts": [
    {
      "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
    }
  ]
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/savings-goals',
{
  method: 'POST',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/savings-goals',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/savings-goals', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/savings-goals");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/savings-goals", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /savings-goals`

*Create a single savings goal for a user*

Requires **savings_goals:read** and **savings_goals:write:all** scopes.

> Body parameter

```json
{
  "name": "House Deposit",
  "amount": {
    "value": 1800000
  },
  "imageUrl": "Image url",
  "notes": "Notes",
  "accounts": [
    {
      "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
    }
  ]
}
```

<h3 id="post__savings-goals-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|body|body|[SavingsGoalsPost](#schemasavingsgoalspost)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "id": "27c316ef-8dfa-4a4b-b0a2-4979b7db1543",
    "name": "House deposit",
    "amount": {
      "value": 500000,
      "currency": "GBP"
    },
    "dateCreated": "2018-10-11T03:51:08+00:00",
    "imageUrl": "url",
    "notes": "Notes",
    "progressPercentage": 33.3,
    "progressAmount": 500000,
    "accounts": [
      {
        "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
      }
    ]
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__savings-goals-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing query parameters - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="post__savings-goals-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[SavingsGoals](#schemasavingsgoals)|false|none|none|
|»» id|string|true|none|Unique id of the saving goal.|
|»» name|string|true|none|Name for the savings goal.|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The target amount in minor unit in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the amount|
|»» dateCreated|string(date-time)|true|none|The date at which the savings goal was added.|
|»» imageUrl|string|false|none|none|
|»» notes|string|false|none|Arbitrary text that a user can add about a savings goal.|
|»» progressPercentage|number|false|none|Progresss achieved towards the target amount represented in percentage.|
|»» progressAmount|integer|false|none|Progresss achieved towards the target amount by adding up the balances of the selected accounts.|
|»» accounts|[object]|true|none|Accounts that will be taken into account towards the target amount.|
|»»» id|string|true|none|Id of the account|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## get__savings-goals_{goalId}

> Code samples

```shell
# You can also use wget
curl -X GET https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
GET https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}',
  method: 'get',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}',
{
  method: 'GET',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.get 'https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.get('https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("GET");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("GET", "https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`GET /savings-goals/{goalId}`

*Retrieve a single savings goal*

Requires **savings_goals:read** scope.

<h3 id="get__savings-goals_{goalid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|goalId|path|string(uuid)|true|The Goal Id|

> Example responses

> 200 Response

```json
{
  "data": {
    "id": "27c316ef-8dfa-4a4b-b0a2-4979b7db1543",
    "name": "House deposit",
    "amount": {
      "value": 500000,
      "currency": "GBP"
    },
    "dateCreated": "2018-10-11T03:51:08+00:00",
    "imageUrl": "url",
    "notes": "Notes",
    "progressPercentage": 33.3,
    "progressAmount": 500000,
    "accounts": [
      {
        "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
      }
    ]
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="get__savings-goals_{goalid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Spending Goal Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not Found|[Error](#schemaerror)|

<h3 id="get__savings-goals_{goalid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[SavingsGoals](#schemasavingsgoals)|false|none|none|
|»» id|string|true|none|Unique id of the saving goal.|
|»» name|string|true|none|Name for the savings goal.|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The target amount in minor unit in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the amount|
|»» dateCreated|string(date-time)|true|none|The date at which the savings goal was added.|
|»» imageUrl|string|false|none|none|
|»» notes|string|false|none|Arbitrary text that a user can add about a savings goal.|
|»» progressPercentage|number|false|none|Progresss achieved towards the target amount represented in percentage.|
|»» progressAmount|integer|false|none|Progresss achieved towards the target amount by adding up the balances of the selected accounts.|
|»» accounts|[object]|true|none|Accounts that will be taken into account towards the target amount.|
|»»» id|string|true|none|Id of the account|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## patch__savings-goals_{goalId}

> Code samples

```shell
# You can also use wget
curl -X PATCH https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId} \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
PATCH https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId} HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}',
  method: 'patch',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "name": "New name",
  "amount": {
    "value": 1800000
  },
  "imageUrl": "New Image url",
  "notes": "New Notes",
  "accounts": [
    {
      "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
    }
  ]
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}',
{
  method: 'PATCH',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.patch 'https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.patch('https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("PATCH");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("PATCH", "https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`PATCH /savings-goals/{goalId}`

*Update a single savings goal*

Requires **savings_goals:read** and either **savings_goals:write** or **savings_goals:write:all** scope.

> Body parameter

```json
{
  "name": "New name",
  "amount": {
    "value": 1800000
  },
  "imageUrl": "New Image url",
  "notes": "New Notes",
  "accounts": [
    {
      "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
    }
  ]
}
```

<h3 id="patch__savings-goals_{goalid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|goalId|path|string(uuid)|true|The Goal Id|
|body|body|[SavingsGoalsPatch](#schemasavingsgoalspatch)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "id": "27c316ef-8dfa-4a4b-b0a2-4979b7db1543",
    "name": "House deposit",
    "amount": {
      "value": 500000,
      "currency": "GBP"
    },
    "dateCreated": "2018-10-11T03:51:08+00:00",
    "imageUrl": "url",
    "notes": "Notes",
    "progressPercentage": 33.3,
    "progressAmount": 500000,
    "accounts": [
      {
        "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
      }
    ]
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="patch__savings-goals_{goalid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Response|Inline|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not Found|[Error](#schemaerror)|

<h3 id="patch__savings-goals_{goalid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|[SavingsGoals](#schemasavingsgoals)|false|none|none|
|»» id|string|true|none|Unique id of the saving goal.|
|»» name|string|true|none|Name for the savings goal.|
|»» amount|object|true|none|none|
|»»» value|integer|true|none|The target amount in minor unit in minor units of the currency, eg. pennies for GBP.|
|»»» currency|string|true|none|The currency of the amount|
|»» dateCreated|string(date-time)|true|none|The date at which the savings goal was added.|
|»» imageUrl|string|false|none|none|
|»» notes|string|false|none|Arbitrary text that a user can add about a savings goal.|
|»» progressPercentage|number|false|none|Progresss achieved towards the target amount represented in percentage.|
|»» progressAmount|integer|false|none|Progresss achieved towards the target amount by adding up the balances of the selected accounts.|
|»» accounts|[object]|true|none|Accounts that will be taken into account towards the target amount.|
|»»» id|string|true|none|Id of the account|
|»» links|[Links](#schemalinks)|false|none|none|
|»»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»»» self|string(uri)|true|none|The url of the current resource(s)|
|»» meta|object|false|none|none|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

## delete__savings-goals_{goalId}

> Code samples

```shell
# You can also use wget
curl -X DELETE https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId} \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
DELETE https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId} HTTP/1.1
Host: api.moneyhub.co.uk
Accept: application/json

```

```javascript
var headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}',
  method: 'delete',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');

const headers = {
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}',
{
  method: 'DELETE',

  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.delete 'https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.delete('https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("DELETE");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("DELETE", "https://api.moneyhub.co.uk/v2.0/savings-goals/{goalId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`DELETE /savings-goals/{goalId}`

*Delete a single savings goal*

Requires **savings_goals:write:all** scope.

<h3 id="delete__savings-goals_{goalid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|goalId|path|string(uuid)|true|The Goal Id|

> Example responses

> 401 Response

```json
{
  "code": "string",
  "message": "string",
  "correlationId": "string"
}
```

<h3 id="delete__savings-goals_{goalid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|204|[No Content](https://tools.ietf.org/html/rfc7231#section-6.3.5)|Succesful Response|None|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|
|404|[Not Found](https://tools.ietf.org/html/rfc7231#section-6.5.4)|Unsuccesful Response - Resource Not Found|[Error](#schemaerror)|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

<h1 id="moneyhub-data-api-sync">sync</h1>

## post__sync_{connectionId}

> Code samples

```shell
# You can also use wget
curl -X POST https://api.moneyhub.co.uk/v2.0/sync/{connectionId} \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: bearerToken'

```

```http
POST https://api.moneyhub.co.uk/v2.0/sync/{connectionId} HTTP/1.1
Host: api.moneyhub.co.uk
Content-Type: application/json
Accept: application/json

```

```javascript
var headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

$.ajax({
  url: 'https://api.moneyhub.co.uk/v2.0/sync/{connectionId}',
  method: 'post',

  headers: headers,
  success: function(data) {
    console.log(JSON.stringify(data));
  }
})

```

```javascript--nodejs
const fetch = require('node-fetch');
const inputBody = '{
  "customerIpAddress": "104.25.212.99",
  "customerLastLoggedTime": "2017-04-05T10:43:07+00:00"
}';
const headers = {
  'Content-Type':'application/json',
  'Accept':'application/json',
  'Authorization':'bearerToken'

};

fetch('https://api.moneyhub.co.uk/v2.0/sync/{connectionId}',
{
  method: 'POST',
  body: inputBody,
  headers: headers
})
.then(function(res) {
    return res.json();
}).then(function(body) {
    console.log(body);
});

```

```ruby
require 'rest-client'
require 'json'

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'bearerToken'
}

result = RestClient.post 'https://api.moneyhub.co.uk/v2.0/sync/{connectionId}',
  params: {
  }, headers: headers

p JSON.parse(result)

```

```python
import requests
headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'bearerToken'
}

r = requests.post('https://api.moneyhub.co.uk/v2.0/sync/{connectionId}', params={

}, headers = headers)

print r.json()

```

```java
URL obj = new URL("https://api.moneyhub.co.uk/v2.0/sync/{connectionId}");
HttpURLConnection con = (HttpURLConnection) obj.openConnection();
con.setRequestMethod("POST");
int responseCode = con.getResponseCode();
BufferedReader in = new BufferedReader(
    new InputStreamReader(con.getInputStream()));
String inputLine;
StringBuffer response = new StringBuffer();
while ((inputLine = in.readLine()) != null) {
    response.append(inputLine);
}
in.close();
System.out.println(response.toString());

```

```go
package main

import (
       "bytes"
       "net/http"
)

func main() {

    headers := map[string][]string{
        "Content-Type": []string{"application/json"},
        "Accept": []string{"application/json"},
        "Authorization": []string{"bearerToken"},
        
    }

    data := bytes.NewBuffer([]byte{jsonReq})
    req, err := http.NewRequest("POST", "https://api.moneyhub.co.uk/v2.0/sync/{connectionId}", data)
    req.Header = headers

    client := &http.Client{}
    resp, err := client.Do(req)
    // ...
}

```

`POST /sync/{connectionId}`

*Sync an existing connection*

Requires **accounts:read** and either **accounts:write** or **account:write:all** scopes.

> Body parameter

```json
{
  "customerIpAddress": "104.25.212.99",
  "customerLastLoggedTime": "2017-04-05T10:43:07+00:00"
}
```

<h3 id="post__sync_{connectionid}-parameters">Parameters</h3>

|Name|In|Type|Required|Description|
|---|---|---|---|---|
|connectionId|path|string|true|The connection id|
|body|body|[SyncPost](#schemasyncpost)|false|none|

> Example responses

> 200 Response

```json
{
  "data": {
    "status": "ok"
  },
  "links": {
    "next": "http://example.com",
    "prev": "http://example.com",
    "self": "http://example.com"
  },
  "meta": {}
}
```

<h3 id="post__sync_{connectionid}-responses">Responses</h3>

|Status|Meaning|Description|Schema|
|---|---|---|---|
|200|[OK](https://tools.ietf.org/html/rfc7231#section-6.3.1)|Succesful Sync Response|Inline|
|400|[Bad Request](https://tools.ietf.org/html/rfc7231#section-6.5.1)|Unsuccessful Response - Bad request - Missing query parameters - Missing body properties|[Error](#schemaerror)|
|401|[Unauthorized](https://tools.ietf.org/html/rfc7235#section-3.1)|Unsuccesful Response - Not authorised - Missing authorization header - Invalid access Token|[Error](#schemaerror)|
|403|[Forbidden](https://tools.ietf.org/html/rfc7231#section-6.5.3)|Unsuccesful Response - Forbidden - Invalid scopes|[Error](#schemaerror)|

<h3 id="post__sync_{connectionid}-responseschema">Response Schema</h3>

Status Code **200**

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|» data|object|false|none|none|
|»» status|string|true|none|Status of the connection|
|» links|[Links](#schemalinks)|false|none|none|
|»» next|string(uri)|false|none|The url to retrieve the next page of results from|
|»» prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|»» self|string(uri)|true|none|The url of the current resource(s)|
|» meta|object|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|status|ok|
|status|error|

<aside class="warning">
To perform this operation, you must be authenticated by means of one of the following methods:
Bearer
</aside>

# Schemas

<h2 id="tocSqueryparams">QueryParams</h2>

<a id="schemaqueryparams"></a>

```json
{
  "categoryId": "string",
  "startDate": "2019-05-22",
  "endDate": "2019-05-22",
  "startDateModified": "2019-05-22",
  "endDateModified": "2019-05-22",
  "limit": 0,
  "offset": 0,
  "text": "string",
  "accountId": "stringstringstringstringstringstring",
  "type": "string"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|categoryId|string|false|none|none|
|startDate|string(date)|false|none|none|
|endDate|string(date)|false|none|none|
|startDateModified|string(date)|false|none|none|
|endDateModified|string(date)|false|none|none|
|limit|integer|false|none|none|
|offset|integer|false|none|none|
|text|string|false|none|none|
|accountId|string|false|none|none|
|type|string|false|none|none|

<h2 id="tocSaccount">Account</h2>

<a id="schemaaccount"></a>

```json
{
  "accountName": "Cash ISA",
  "currency": "GBP",
  "balance": {
    "date": "2018-08-12",
    "amount": {
      "value": -300023,
      "currency": "GBP"
    }
  },
  "details": {
    "AER": 1.3,
    "APR": 13.1,
    "sortCodeAccountNumber": "60161331926819",
    "iban": "GB2960161331926819",
    "creditLimit": 150000,
    "endDate": "2020-01-01",
    "fixedDate": "2019-01-01",
    "interestFreePeriod": 12,
    "interestType": "fixed",
    "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "monthlyRepayment": 60000,
    "overdraftLimit": 150000,
    "postcode": "bs1 1aa",
    "runningCost": 20000,
    "runningCostPeriod": "month",
    "term": 13,
    "yearlyAppreciation": -10
  },
  "transactionData": {
    "count": 6,
    "earliestDate": "2017-11-28",
    "lastDate": "2018-05-28"
  },
  "dateAdded": "2018-07-10T11:39:44+00:00",
  "dateModified": "2018-07-10T11:39:44+00:00",
  "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
  "providerName": "HSBC",
  "providerReference": "hsbc",
  "connectionId": "049c10ab871e8d60aa891c0ae368322d:639cf079-a585-4852-8b4d-1ebd17f4d2cb",
  "providerId": "049c10ab871e8d60aa891c0ae368322d",
  "accountReference": "3201",
  "accountType": "personal",
  "type": "cash:current",
  "performanceScore": {
    "totals": {
      "openingBalance": {
        "date": "2018-08-12",
        "amount": {
          "value": 300023,
          "currency": "GBP"
        }
      },
      "currentBalance": {
        "date": "2018-08-12",
        "amount": {
          "value": 300023,
          "currency": "GBP"
        }
      },
      "contributions": 240098,
      "withdrawals": 20067,
      "nonContributionGrowth": 340054,
      "growthRate": 35.98,
      "annualisedGrowthRate": 60.98
    },
    "months": [
      {
        "date": "2018-08",
        "openingBalance": 300023,
        "nonContributionGrowth": 1567,
        "aer": 35.98
      }
    ]
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|accountName|string|true|none|The name of the account|
|currency|string|false|none|The currency of the account|
|balance|object|true|none|none|
|» amount|object|true|none|none|
|»» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|»» currency|string|true|none|The currency of the balance taken from the account|
|» date|string(date)|true|none|The date of the balance|
|details|object|true|none|none|
|» AER|number|false|none|For cash and savings accounts. Interest rate expessed as a percentage 'Annual Equivalent Rate'.|
|» APR|number|false|none|For credit cards, mortgages and loans. Interest rate expessed as a percentage 'Annual Percentage Rate'.|
|» sortCodeAccountNumber|string|false|none|For cash accounts. Populated with the 6 digit Sort Code and 8 digit Account Number. It requires the `accounts_details:read` scope.|
|» iban|string|false|none|For cash accounts. Populated with the full IBAN number. It requires the `accounts_details:read` scope.|
|» creditLimit|integer|false|none|For credit cards. The agreed overdraft limit of the account in minor units of the currency.|
|» endDate|string(date)|false|none|For Mortgages and loans. The date at which the loan/mortgage will finish.|
|» fixedDate|string(date)|false|none|For Mortgages. The date at which the current fixed rate ends|
|» interestFreePeriod|integer|false|none|For loans. The length in months of the interest free period|
|» interestType|string|false|none|For mortgages. The interest type|
|» linkedProperty|string|false|none|For Mortgages. The id of an associated property account|
|» monthlyRepayment|integer|false|none|For mortgages and loans. The monthly amount due to the mortgage provider in minor units of the currency.|
|» overdraftLimit|number|false|none|For cash accounts. The agreed overdraft limit of the account in minor units of the currency.|
|» postcode|string|false|none|For properties. The postcode of the property|
|» runningCost|integer|false|none|For assets. The running cost in minor units of the currency.|
|» runningCostPeriod|string|false|none|For assets. The running cost period|
|» term|integer|false|none|For mortgages. The term of the mortgage in months.|
|» yearlyAppreciation|number|false|none|For assets. The rate of appreciation as a percentage, negative values indicate that the asset will depreciate|
|transactionData|object|false|none|none|
|» count|integer|true|none|none|
|» earliestDate|string(date)|true|none|none|
|» lastDate|string(date)|true|none|none|
|dateAdded|string(date-time)|true|none|The date at which the account was added.|
|dateModified|string(date-time)|true|none|The date at which the account was last modified|
|id|string|true|none|The unique identity of the account.|
|providerName|string|false|none|The name of the provider of the account.|
|providerReference|string|false|none|The unique reference name of the provider of the account.|
|connectionId|string(([\w-])+:([\w-])+)|false|none|The id of the connection of the account. This value is not present for accounts created manually by the user.|
|providerId|string(API|DEMO|([\w-])+)|false|none|The id of the provider of the account. Accounts created using the api have a value of 'API'. Accounts crated for a Test user have a value of 'DEMO'. This value is not present for accounts created manually by the user.|
|accountReference|string|false|none|A reference number for the account - typically the last 4 digits of the account number|
|accountType|string|false|none|The type of account (personal/business)|
|type|string|true|none|The type of account - this will determine the data available in the details field|
|performanceScore|object|false|none|Performance score of investment and pension accounts. Once that an account has at least 3 balances the score will be provided. Please note that this is an experimental feature.|
|» totals|object|true|none|none|
|»» openingBalance|object|false|none|none|
|»»» date|string(date)|false|none|none|
|»»» amount|object|false|none|none|
|»»»» value|integer|true|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»» currency|string|true|none|none|
|»»» currentBalance|object|false|none|none|
|»»»» date|string(date)|false|none|none|
|»»»» amount|object|false|none|none|
|»»»»» value|integer|true|none|The current balance in minor units of the currency, eg. pennies for GBP|
|»»»»» currency|string|true|none|none|
|»»»» contributions|integer|false|none|The contributions in minor units of the currency, eg. pennies for GBP|
|»»»» withdrawals|integer|false|none|The withdrawals in minor units of the currency, eg. pennies for GBP|
|»»»» nonContributionGrowth|integer|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»» growthRate|number|false|none|The growth rate expressed in percentage|
|»»»» annualisedGrowthRate|number|false|none|The annualised growth rate expressed in percentage|
|»»» months|[object]|true|none|none|
|»»»» date|string|false|none|Date in the format YYYY-MM|
|»»»» openingBalance|integer|false|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»»» nonContributionGrowth|number|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»»» aer|number|false|none|The aer expressed in percentage|

#### Enumerated Values

|Property|Value|
|---|---|
|interestType|fixed|
|interestType|variable|
|runningCostPeriod|month|
|runningCostPeriod|year|
|accountType|personal|
|accountType|business|
|type|cash:current|
|type|savings|
|type|card|
|type|investment|
|type|loan|
|type|mortgage:repayment|
|type|mortgage:interestOnly|
|type|pension|
|type|asset|
|type|properties:residential|
|type|properties:buyToLet|

<h2 id="tocSaccountdetails">AccountDetails</h2>

<a id="schemaaccountdetails"></a>

```json
{
  "AER": 1.3,
  "APR": 13.1,
  "sortCodeAccountNumber": "60161331926819",
  "iban": "GB2960161331926819",
  "creditLimit": 150000,
  "endDate": "2020-01-01",
  "fixedDate": "2019-01-01",
  "interestFreePeriod": 12,
  "interestType": "fixed",
  "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
  "monthlyRepayment": 60000,
  "overdraftLimit": 150000,
  "postcode": "bs1 1aa",
  "runningCost": 20000,
  "runningCostPeriod": "month",
  "term": 13,
  "yearlyAppreciation": -10
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|AER|number|false|none|For cash and savings accounts. Interest rate expessed as a percentage 'Annual Equivalent Rate'.|
|APR|number|false|none|For credit cards, mortgages and loans. Interest rate expessed as a percentage 'Annual Percentage Rate'.|
|sortCodeAccountNumber|string|false|none|For cash accounts. Populated with the 6 digit Sort Code and 8 digit Account Number. It requires the `accounts_details:read` scope.|
|iban|string|false|none|For cash accounts. Populated with the full IBAN number. It requires the `accounts_details:read` scope.|
|creditLimit|integer|false|none|For credit cards. The agreed overdraft limit of the account in minor units of the currency.|
|endDate|string(date)|false|none|For Mortgages and loans. The date at which the loan/mortgage will finish.|
|fixedDate|string(date)|false|none|For Mortgages. The date at which the current fixed rate ends|
|interestFreePeriod|integer|false|none|For loans. The length in months of the interest free period|
|interestType|string|false|none|For mortgages. The interest type|
|linkedProperty|string|false|none|For Mortgages. The id of an associated property account|
|monthlyRepayment|integer|false|none|For mortgages and loans. The monthly amount due to the mortgage provider in minor units of the currency.|
|overdraftLimit|number|false|none|For cash accounts. The agreed overdraft limit of the account in minor units of the currency.|
|postcode|string|false|none|For properties. The postcode of the property|
|runningCost|integer|false|none|For assets. The running cost in minor units of the currency.|
|runningCostPeriod|string|false|none|For assets. The running cost period|
|term|integer|false|none|For mortgages. The term of the mortgage in months.|
|yearlyAppreciation|number|false|none|For assets. The rate of appreciation as a percentage, negative values indicate that the asset will depreciate|

#### Enumerated Values

|Property|Value|
|---|---|
|interestType|fixed|
|interestType|variable|
|runningCostPeriod|month|
|runningCostPeriod|year|

<h2 id="tocSperformancescore">PerformanceScore</h2>

<a id="schemaperformancescore"></a>

```json
{
  "totals": {
    "openingBalance": {
      "date": "2018-08-12",
      "amount": {
        "value": 300023,
        "currency": "GBP"
      }
    },
    "currentBalance": {
      "date": "2018-08-12",
      "amount": {
        "value": 300023,
        "currency": "GBP"
      }
    },
    "contributions": 240098,
    "withdrawals": 20067,
    "nonContributionGrowth": 340054,
    "growthRate": 35.98,
    "annualisedGrowthRate": 60.98
  },
  "months": [
    {
      "date": "2018-08",
      "openingBalance": 300023,
      "nonContributionGrowth": 1567,
      "aer": 35.98
    }
  ]
}

```

*Performance score of investment and pension accounts. Once that an account has at least 3 balances the score will be provided. Please note that this is an experimental feature.*

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|totals|object|true|none|none|
|» openingBalance|object|false|none|none|
|»» date|string(date)|false|none|none|
|»» amount|object|false|none|none|
|»»» value|integer|true|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»» currency|string|true|none|none|
|»» currentBalance|object|false|none|none|
|»»» date|string(date)|false|none|none|
|»»» amount|object|false|none|none|
|»»»» value|integer|true|none|The current balance in minor units of the currency, eg. pennies for GBP|
|»»»» currency|string|true|none|none|
|»»» contributions|integer|false|none|The contributions in minor units of the currency, eg. pennies for GBP|
|»»» withdrawals|integer|false|none|The withdrawals in minor units of the currency, eg. pennies for GBP|
|»»» nonContributionGrowth|integer|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»» growthRate|number|false|none|The growth rate expressed in percentage|
|»»» annualisedGrowthRate|number|false|none|The annualised growth rate expressed in percentage|
|»» months|[object]|true|none|none|
|»»» date|string|false|none|Date in the format YYYY-MM|
|»»» openingBalance|integer|false|none|The opening balance in minor units of the currency, eg. pennies for GBP|
|»»» nonContributionGrowth|number|false|none|The non contribution growth in minor units of the currency, eg. pennies for GBP|
|»»» aer|number|false|none|The aer expressed in percentage|

<h2 id="tocSbalance">Balance</h2>

<a id="schemabalance"></a>

```json
{
  "date": "2018-08-12",
  "amount": {
    "value": -300023,
    "currency": "GBP"
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|amount|object|true|none|none|
|» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the balance taken from the account|
|date|string(date)|true|none|The date of the balance|

<h2 id="tocSbalancepost">BalancePost</h2>

<a id="schemabalancepost"></a>

```json
{
  "date": "2018-08-12",
  "amount": {
    "value": -300023
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|amount|object|true|none|none|
|» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|date|string(date)|true|none|The date of the balance|

<h2 id="tocSaccountpost">AccountPost</h2>

<a id="schemaaccountpost"></a>

```json
{
  "accountName": "Account name",
  "providerName": "Provider name",
  "type": "cash:current",
  "accountType": "personal",
  "balance": {
    "date": "2018-08-12",
    "amount": {
      "value": -300023
    }
  },
  "details": {
    "AER": 1.3,
    "APR": 13.1,
    "creditLimit": 150000,
    "endDate": "2020-01-01",
    "fixedDate": "2019-01-01",
    "interestFreePeriod": 12,
    "interestType": "fixed",
    "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "monthlyRepayment": 60000,
    "overdraftLimit": 150000,
    "postcode": "bs1 1aa",
    "runningCost": 20000,
    "runningCostPeriod": "month",
    "term": 13,
    "yearlyAppreciation": -10
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|accountName|string|true|none|The name of the account|
|providerName|string|true|none|The name of the provider of the account.|
|type|string|true|none|The type of account - this will determine the data available in the details field|
|accountType|string|false|none|The type of account (personal/business)|
|balance|object|true|none|none|
|» amount|object|true|none|none|
|»» value|integer|true|none|The value of the balance in minor units of the currency, eg. pennies for GBP.|
|» date|string(date)|true|none|The date of the balance|
|details|object|false|none|none|
|» AER|number|false|none|For cash and savings accounts. Interest rate expessed as a percentage 'Annual Equivalent Rate'.|
|» APR|number|false|none|For credit cards, mortgages and loans. Interest rate expessed as a percentage 'Annual Percentage Rate'.|
|» creditLimit|integer|false|none|For credit cards. The agreed overdraft limit of the account in minor units of the currency.|
|» endDate|string(date)|false|none|For Mortgages and loans. The date at which the loan/mortgage will finish.|
|» fixedDate|string(date)|false|none|For Mortgages. The date at which the current fixed rate ends|
|» interestFreePeriod|integer|false|none|For loans. The length in months of the interest free period|
|» interestType|string|false|none|For mortgages. The interest type|
|» linkedProperty|string|false|none|For Mortgages. The id of an associated property account|
|» monthlyRepayment|integer|false|none|For mortgages and loans. The monthly amount due to the mortgage provider in minor units of the currency.|
|» overdraftLimit|number|false|none|For cash accounts. The agreed overdraft limit of the account in minor units of the currency.|
|» postcode|string|false|none|For properties. The postcode of the property|
|» runningCost|integer|false|none|For assets. The running cost in minor units of the currency.|
|» runningCostPeriod|string|false|none|For assets. The running cost period|
|» term|integer|false|none|For mortgages. The term of the mortgage in months.|
|» yearlyAppreciation|number|false|none|For assets. The rate of appreciation as a percentage, negative values indicate that the asset will depreciate|

#### Enumerated Values

|Property|Value|
|---|---|
|type|cash:current|
|type|savings|
|type|card|
|type|investment|
|type|loan|
|type|mortgage:repayment|
|type|mortgage:interestOnly|
|type|pension|
|type|asset|
|type|properties:residential|
|type|properties:buyToLet|
|accountType|personal|
|accountType|business|
|interestType|fixed|
|interestType|variable|
|runningCostPeriod|month|
|runningCostPeriod|year|

<h2 id="tocSaccountpatch">AccountPatch</h2>

<a id="schemaaccountpatch"></a>

```json
{
  "accountName": "Account name",
  "providerName": "Provider name",
  "details": {
    "AER": 1.3,
    "APR": 13.1,
    "creditLimit": 150000,
    "endDate": "2020-01-01",
    "fixedDate": "2019-01-01",
    "interestFreePeriod": 12,
    "interestType": "fixed",
    "linkedProperty": "ac9bd177-d01e-449c-9f29-d3656d2edc2e",
    "monthlyRepayment": 60000,
    "overdraftLimit": 150000,
    "postcode": "bs1 1aa",
    "runningCost": 20000,
    "runningCostPeriod": "month",
    "term": 13,
    "yearlyAppreciation": -10
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|accountName|string|true|none|The name of the account|
|providerName|string|true|none|The name of the provider of the account.|
|details|object|false|none|none|
|» AER|number|false|none|For cash and savings accounts. Interest rate expessed as a percentage 'Annual Equivalent Rate'.|
|» APR|number|false|none|For credit cards, mortgages and loans. Interest rate expessed as a percentage 'Annual Percentage Rate'.|
|» creditLimit|integer|false|none|For credit cards. The agreed overdraft limit of the account in minor units of the currency.|
|» endDate|string(date)|false|none|For Mortgages and loans. The date at which the loan/mortgage will finish.|
|» fixedDate|string(date)|false|none|For Mortgages. The date at which the current fixed rate ends|
|» interestFreePeriod|integer|false|none|For loans. The length in months of the interest free period|
|» interestType|string|false|none|For mortgages. The interest type|
|» linkedProperty|string|false|none|For Mortgages. The id of an associated property account|
|» monthlyRepayment|integer|false|none|For mortgages and loans. The monthly amount due to the mortgage provider in minor units of the currency.|
|» overdraftLimit|number|false|none|For cash accounts. The agreed overdraft limit of the account in minor units of the currency.|
|» postcode|string|false|none|For properties. The postcode of the property|
|» runningCost|integer|false|none|For assets. The running cost in minor units of the currency.|
|» runningCostPeriod|string|false|none|For assets. The running cost period|
|» term|integer|false|none|For mortgages. The term of the mortgage in months.|
|» yearlyAppreciation|number|false|none|For assets. The rate of appreciation as a percentage, negative values indicate that the asset will depreciate|

#### Enumerated Values

|Property|Value|
|---|---|
|interestType|fixed|
|interestType|variable|
|runningCostPeriod|month|
|runningCostPeriod|year|

<h2 id="tocSholdingsvaluation">HoldingsValuation</h2>

<a id="schemaholdingsvaluation"></a>

```json
{
  "date": "2018-07-11",
  "items": [
    {
      "codes": [
        {
          "code": "GB00B39TQT96",
          "type": "ISIN"
        }
      ],
      "description": "Dynamic Bond Fund",
      "quantity": 4548.09,
      "total": {
        "value": 90334.16,
        "currency": "GBP"
      },
      "unitPrice": {
        "value": 19.862,
        "currency": "GBP"
      }
    }
  ]
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|date|string(date)|true|none|Date of the valuation|
|items|[any]|true|none|none|
|» codes|[object]|true|none|none|
|»» code|string|false|none|none|
|»» type|string|false|none|none|
|» description|string|true|none|none|
|» quantity|number|true|none|none|
|» total|object|true|none|none|
|»» value|number|true|none|The value of the total in minor units of the currency, eg. pennies for GBP.|
|»» currency|string|true|none|The currency of the total.|
|» unitPrice|object|true|none|none|
|»» value|number|true|none|The value of the unit price in minor units of the currency, eg. pennies for GBP.|
|»» currency|string|true|none|The currency of the unit price.|

#### Enumerated Values

|Property|Value|
|---|---|
|type|ISIN|
|type|SEDOL|
|type|MEX|

<h2 id="tocSholding">Holding</h2>

<a id="schemaholding"></a>

```json
{
  "codes": [
    {
      "code": "GB00B39TQT96",
      "type": "ISIN"
    }
  ],
  "description": "Dynamic Bond Fund",
  "quantity": 4548.09,
  "total": {
    "value": 90334.16,
    "currency": "GBP"
  },
  "unitPrice": {
    "value": 19.862,
    "currency": "GBP"
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|codes|[object]|true|none|none|
|» code|string|false|none|none|
|» type|string|false|none|none|
|description|string|true|none|none|
|quantity|number|true|none|none|
|total|object|true|none|none|
|» value|number|true|none|The value of the total in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the total.|
|unitPrice|object|true|none|none|
|» value|number|true|none|The value of the unit price in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the unit price.|

#### Enumerated Values

|Property|Value|
|---|---|
|type|ISIN|
|type|SEDOL|
|type|MEX|

<h2 id="tocSholdingwithmatches">HoldingWithMatches</h2>

<a id="schemaholdingwithmatches"></a>

```json
{
  "date": "2018-07-11",
  "id": "6a8b01768a50b095a8c0445c1b080900f1096fd0b6e40863c6b82d63607c3bbe",
  "matched": [
    {
      "isin": "GB00B39TQT96",
      "name": "Dynamic Bond Fund Acc",
      "score": 0.5,
      "priceGBP": 4548.09,
      "price": {
        "value": 90334.16,
        "currency": "GBP"
      },
      "date": "2018-07-11"
    }
  ],
  "codes": [
    {
      "code": "GB00B39TQT96",
      "type": "ISIN"
    }
  ],
  "name": "Dynamic Bond Fund",
  "quantity": 4548.09,
  "total": {
    "value": 90334.16,
    "currency": "GBP"
  },
  "unitPrice": {
    "value": 19.862,
    "currency": "GBP"
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|date|string(date)|false|none|Date of the valuation|
|id|string|true|none|The id of the holding|
|matched|[object]|true|none|none|
|» isin|string|false|none|The ISIN code of the match|
|» name|string|false|none|The name of the match|
|» score|number|false|none|none|
|» priceGBP|number|false|none|none|
|» price|object|false|none|none|
|»» value|number|true|none|The unit price in minor units of the currency (e.g. pence for GBP)|
|»» currency|string|true|none|The currency of the matched holding|
|» date|string(date)|false|none|Date of the valuation|
|codes|[object]|true|none|none|
|» code|string|false|none|none|
|» type|string|false|none|none|
|name|string|true|none|none|
|quantity|number|true|none|none|
|total|object|true|none|none|
|» value|number|true|none|The value of the total in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the total.|
|unitPrice|object|true|none|none|
|» value|number|true|none|The value of the unit price in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the unit price.|

#### Enumerated Values

|Property|Value|
|---|---|
|type|ISIN|
|type|SEDOL|
|type|MEX|

<h2 id="tocSholdingwithmatchesandhistory">HoldingWithMatchesAndHistory</h2>

<a id="schemaholdingwithmatchesandhistory"></a>

```json
{
  "id": "6a8b01768a50b095a8c0445c1b080900f1096fd0b6e40863c6b82d63607c3bbe",
  "history": [
    {
      "total": {
        "value": 90334.16,
        "currency": "GBP"
      },
      "unitPrice": {
        "value": 19.862,
        "currency": "GBP"
      },
      "quantity": 4548.09,
      "date": "2018-07-11"
    }
  ],
  "matched": [
    {
      "isin": "GB00B39TQT96",
      "name": "Dynamic Bond Fund Acc",
      "score": 0.5,
      "priceGBP": 4548.09,
      "price": {
        "value": 90334.16,
        "currency": "GBP"
      },
      "date": "2018-07-11"
    }
  ],
  "codes": [
    {
      "code": "GB00B39TQT96",
      "type": "ISIN"
    }
  ],
  "name": "Dynamic Bond Fund",
  "quantity": 4548.09,
  "total": {
    "value": 90334.16,
    "currency": "GBP"
  },
  "unitPrice": {
    "value": 19.862,
    "currency": "GBP"
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|id|string|true|none|The id of the holding|
|history|[object]|true|none|none|
|» total|object|false|none|none|
|»» value|number|true|none|The value of the total in minor units of the currency, eg. pennies for GBP.|
|»» currency|string|true|none|The currency of the total.|
|» unitPrice|object|false|none|none|
|»» value|number|true|none|The value of the unit price in minor units of the currency, eg. pennies for GBP.|
|»» currency|string|true|none|The currency of the unit price.|
|» quantity|number|false|none|none|
|» date|string(date)|false|none|Date of the valuation|
|matched|[object]|true|none|none|
|» isin|string|false|none|The ISIN code of the match|
|» name|string|false|none|The name of the match|
|» score|number|false|none|none|
|» priceGBP|number|false|none|none|
|» price|object|false|none|none|
|»» value|number|true|none|The unit price in minor units of the currency (e.g. pence for GBP)|
|»» currency|string|true|none|The currency of the matched holding|
|» date|string(date)|false|none|Date of the valuation|
|codes|[object]|true|none|none|
|» code|string|false|none|none|
|» type|string|false|none|none|
|name|string|true|none|none|
|quantity|number|true|none|none|
|total|object|true|none|none|
|» value|number|true|none|The value of the total in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the total.|
|unitPrice|object|true|none|none|
|» value|number|true|none|The value of the unit price in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the unit price.|

#### Enumerated Values

|Property|Value|
|---|---|
|type|ISIN|
|type|SEDOL|
|type|MEX|

<h2 id="tocScounterparty">Counterparty</h2>

<a id="schemacounterparty"></a>

```json
{
  "id": "4bac27393bdd9777ce02453256c5577cd02275510b2227f473d03f533924f877",
  "label": "British Gas"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|id|string|true|none|The unique identifier for the counterparty.|
|label|string|true|none|A label describing the counterparty|
|type|string|true|none|The type of counterpary (specific to an account, or globally recognoised accross all users)|
|companyName|string|false|none|The full name of the company (only for global counterparties)|
|logo|string|false|none|The url to the company logo (only for global counterparties)|
|website|string|false|none|The url to the company website (only for global counterparties)|
|mcc|object|false|none|none|
|» code|string|false|none|The merchant category code (only for global counterparties)|
|» name|string|false|none|The merchant category code name (only for global counterparties)|

#### Enumerated Values

|Property|Value|
|---|---|
|type|global|
|type|local|

<h2 id="tocSrecurringtransactionestimate">RecurringTransactionEstimate</h2>

<a id="schemarecurringtransactionestimate"></a>

```json
{
  "counterpartyId": "4bac27393bdd9777ce02453256c5577cd02275510b2227f473d03f533924f877",
  "amount": {
    "value": -300023,
    "currency": "GBP"
  },
  "amountRange": {
    "value": 5000,
    "currency": "GBP"
  },
  "monthlyAmount": {
    "value": 5000,
    "currency": "GBP"
  },
  "predictionSource": "moneyhub",
  "monthlyAverageOnly": false,
  "dates": [
    "2019-03-07",
    "2019-04-07",
    "2019-05-07"
  ]
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|counterpartyId|string|false|none|The id of the counterparty that the estimate is for|
|amount|object|false|none|none|
|» value|integer|true|none|The average prected amount of the recurring transaction in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the predicted amount taken from the account|
|amountRange|object|false|none|none|
|» value|integer|true|none|The prected range of the recurring transaction in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the predicted range taken from the account|
|monthlyAmount|object|false|none|none|
|» value|integer|true|none|The prected monthly amount for this counterparty, regardless of how many transactions in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the monthly amount taken from the account|
|predictionSource|string|false|none|The source of the prediction|
|monthlyAverageOnly|boolean|false|none|A flag indiciating whether the predictions are based only on a monthly average or not. If the predictions are based solely on monthly averages then the dates array will be defaulted to the end of the month for the next 3 motnhs.|
|dates|[string]|false|none|none|

#### Enumerated Values

|Property|Value|
|---|---|
|predictionSource|moneyhub|

<h2 id="tocScategory">Category</h2>

<a id="schemacategory"></a>

```json
{
  "categoryId": "std:338d2636-7f88-491d-8129-255c98da1eb8",
  "name": "Days Out",
  "key": "wages",
  "group": "group:2"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|categoryId|string|true|none|The id of the category. Custom categories are prefixed with 'cus:'|
|name|string|false|none|The name of the category - only applicable for custom categories|
|key|string|false|none|A text key for standard categories|
|group|string|true|none|The category group to which the category belongs|

<h2 id="tocScategorypost">CategoryPost</h2>

<a id="schemacategorypost"></a>

```json
{
  "group": "group:1",
  "name": "Bus travel"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|group|string|true|none|The id of the category group that the custom category should be part of|
|name|string|true|none|The name of the custom category|

<h2 id="tocScategorygroup">CategoryGroup</h2>

<a id="schemacategorygroup"></a>

```json
{
  "id": "group-1",
  "key": "bills"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|id|string|true|none|The id of the category group.|
|key|string|true|none|A text key for the category group|

<h2 id="tocStransactiondetails">TransactionDetails</h2>

<a id="schematransactiondetails"></a>

```json
{
  "count": 6,
  "earliestDate": "2017-11-28",
  "lastDate": "2018-05-28"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|count|integer|true|none|none|
|earliestDate|string(date)|true|none|none|
|lastDate|string(date)|true|none|none|

<h2 id="tocStransaction">Transaction</h2>

<a id="schematransaction"></a>

```json
{
  "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
  "amount": {
    "value": -2323,
    "currency": "GBP"
  },
  "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
  "categoryIdConfirmed": false,
  "date": "2018-07-10T12:00:00+00:00",
  "dateModified": "2018-07-10T11:39:46.506Z",
  "id": "c390a94f-3824-4cdf-8d02-b0c5304d9f66",
  "longDescription": "Card Purchase SAINSBURYS S/MKTS  BCC",
  "notes": "Some notes about the transaction",
  "shortDescription": "Sainsburys S/mkts",
  "counterpartyId": "30be8fa43f30fc285e4c479e9dfd6a1dec2bead8ee6cc6276b8dac152c565e9e",
  "status": "posted"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|accountId|string|false|none|The id of the account the transaction belongs to|
|amount|object|true|none|none|
|» value|integer|true|none|The amount of the transaction in minor units of the currency, eg. pennies for GBP, negative means money going out of an account, positive means money coming into an account.|
|» currency|string|true|none|The currency of the amount|
|categoryId|string|true|none|The category id. Standard categories are prefixed with 'std', custom categories are prefixed with 'cus'|
|categoryIdConfirmed|boolean|true|none|Flag indificating whether the user has confirmed the category id as correct|
|date|string(date-time)|true|none|The date that the transaction occurred. Where available this will contain an accurate time, where the time is not available it will default to midday.|
|dateModified|string(date-time)|true|none|The date the transaction was modified - this could be when it was added, or a category changed, or when notes were added|
|id|string|true|none|The unique id of the transaction|
|longDescription|string|true|none|The full text description of the transactions - often as it is represented on the users bank statement|
|notes|string|true|none|Arbitrary text that a user can add about a transaction|
|shortDescription|string|true|none|A cleaned up and shorter description of the transaction, this can be editied|
|counterpartyId|string|false|none|An identifier for the counterparty|
|status|string|true|none|Whether the transaction has been posted (booked) or is still a pending transaction. During the transition from pending to posted the description will normally change.|

#### Enumerated Values

|Property|Value|
|---|---|
|status|posted|
|status|pending|

<h2 id="tocStransactionpost">TransactionPost</h2>

<a id="schematransactionpost"></a>

```json
{
  "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
  "amount": {
    "value": -2300
  },
  "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
  "categoryIdConfirmed": true,
  "longDescription": "New transaction",
  "shortDescription": "transaction",
  "notes": "notes",
  "status": "posted",
  "date": "2018-07-10T12:00:00+00:00"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|accountId|string|true|none|The id of the account the transaction belongs to|
|amount|object|true|none|none|
|» value|integer|true|none|The amount of the transaction in minor units of the currency, eg. pennies for GBP, negative means money going out of an account, positive means money coming into an account.|
|categoryId|string|true|none|The category id. Standard categories are prefixed with 'std', custom categories are prefixed with 'cus'|
|categoryIdConfirmed|boolean|false|none|Flag indicating whether the user has confirmed the category id as correct|
|date|string(date-time)|true|none|The date that the transaction occurred. Where available this will contain an accurate time, where the time is not available it will default to midday.|
|longDescription|string|true|none|The full text description of the transactions - often as it is represented on the users bank statement|
|shortDescription|string|false|none|A cleaned up and shorter description of the transaction, this can be edited|
|notes|string|false|none|Arbitrary text that a user can add about a transaction|
|status|string|false|none|Whether the transaction has been posted (booked) or is still a pending transaction. During the transition from pending to posted the description will normally change.|

#### Enumerated Values

|Property|Value|
|---|---|
|status|posted|
|status|pending|

<h2 id="tocStransactionpatch">TransactionPatch</h2>

<a id="schematransactionpatch"></a>

```json
{
  "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
  "amount": {
    "value": -51000
  },
  "categoryId": "std:09f5c144-6d90-4228-98c6-cac1331d874b",
  "categoryIdConfirmed": true,
  "longDescription": "New long description",
  "shortDescription": "New short description",
  "notes": "New notes",
  "status": "posted",
  "date": "2018-07-10T12:00:00+00:00"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|accountId|string|false|none|Scope 'transactions.write.all' required. The id of the account the transaction belongs to|
|amount|object|false|none|none|
|» value|integer|true|none|Scope 'transactions.write.all' required. The amount of the transaction in minor units of the currency, eg. pennies for GBP, negative means money going out of an account, positive means money coming into an account.|
|categoryId|string|false|none|The category id. Standard categories are prefixed with 'std', custom categories are prefixed with 'cus'|
|categoryIdConfirmed|boolean|false|none|Flag indificating whether the user has confirmed the category id as correct|
|date|string(date-time)|false|none|Scope 'transactions.write.all' required. The date that the transaction occurred. Where available this will contain an accurate time, where the time is not available it will default to midday.|
|longDescription|string|false|none|Scope 'transactions.write.all' required. The full text description of the transactions - often as it is represented on the users bank statement|
|shortDescription|string|false|none|A cleaned up and shorter description of the transaction, this can be edited|
|notes|string|false|none|Arbitrary text that a user can add about a transaction|
|status|string|false|none|Scope 'transactions.write.all' required. Whether the transaction has been posted (booked) or is still a pending transaction. During the transition from pending to posted the description will normally change.|

#### Enumerated Values

|Property|Value|
|---|---|
|status|posted|
|status|pending|

<h2 id="tocStransactioncollectionpost">TransactionCollectionPost</h2>

<a id="schematransactioncollectionpost"></a>

```json
[
  {
    "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
    "amount": {
      "value": -4500
    },
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "categoryIdConfirmed": true,
    "longDescription": "Long description 1",
    "shortDescription": "description 1",
    "notes": "notes",
    "status": "posted",
    "date": "2018-07-10T12:00:00+00:00"
  },
  {
    "accountId": "c390a94f-2309-4cdf-8d02-b0c5304d9f66",
    "amount": {
      "value": 7800
    },
    "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
    "longDescription": "Long description 2",
    "notes": "notes",
    "status": "pending",
    "date": "2018-07-10T12:00:00+00:00"
  }
]

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|accountId|string|true|none|The id of the account the transaction belongs to|
|amount|object|true|none|none|
|» value|integer|true|none|The amount of the transaction in minor units of the currency, eg. pennies for GBP, negative means money going out of an account, positive means money coming into an account.|
|categoryId|string|true|none|The category id. Standard categories are prefixed with 'std', custom categories are prefixed with 'cus'|
|categoryIdConfirmed|boolean|false|none|Flag indicating whether the user has confirmed the category id as correct|
|date|string(date-time)|true|none|The date that the transaction occurred. Where available this will contain an accurate time, where the time is not available it will default to midday.|
|longDescription|string|true|none|The full text description of the transactions - often as it is represented on the users bank statement|
|shortDescription|string|false|none|A cleaned up and shorter description of the transaction, this can be edited|
|notes|string|false|none|Arbitrary text that a user can add about a transaction|
|status|string|false|none|Whether the transaction has been posted (booked) or is still a pending transaction. During the transition from pending to posted the description will normally change.|

#### Enumerated Values

|Property|Value|
|---|---|
|status|posted|
|status|pending|

<h2 id="tocSspendinganalysis">SpendingAnalysis</h2>

<a id="schemaspendinganalysis"></a>

```json
{
  "categories": [
    {
      "categoryId": "std:65ebdcdb-c46b-478f-bbbc-feabeb0b4342",
      "categoryGroup": "group:2",
      "currentMonth": -2000,
      "previousMonth": -1000
    },
    {
      "categoryId": "std:379c7ed2-27f3-401f-b581-f6507934f0f0",
      "categoryGroup": "group:3",
      "currentMonth": -1500,
      "previousMonth": -500
    }
  ],
  "total": {
    "currentMonth": -3500,
    "previousMonth": -1500
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|categories|[object]|false|none|none|
|» categoryId|string|false|none|none|
|» categoryGroup|string|false|none|none|
|total|object|false|none|none|

<h2 id="tocSspendinganalysispost">SpendingAnalysisPost</h2>

<a id="schemaspendinganalysispost"></a>

```json
{
  "dates": [
    {
      "name": "currentMonth",
      "from": "2018-10-01",
      "to": "2018-10-31"
    },
    {
      "name": "previousMonth",
      "from": "2018-09-01",
      "to": "2018-09-30"
    }
  ],
  "accountIds": [
    "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
  ],
  "categoryIds": [
    "std:338d2636-7f88-491d-8129-255c98da1eb8"
  ]
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|dates|[object]|true|none|List of date ranges to calculate spending analysis for. This allows retrieving spending analysis of up to three diferent date ranges in one request.|
|» name|string([a-zA-Z0-9_-]{1,50})|true|none|Descriptive name for the date range. The name will be used in the response payload to identify it.|
|» from|string(date)|true|none|Start date to perform spending analysis.|
|» to|string(date)|true|none|End date to perform spending analysis.|
|accountIds|[string]|false|none|none|
|categoryIds|[string]|false|none|none|

<h2 id="tocSspendinggoal">SpendingGoal</h2>

<a id="schemaspendinggoal"></a>

```json
{
  "categoryId": "std:4b0255f0-0309-4509-9e05-4b4e386f9b0d",
  "dateCreated": "2018-07-11T03:51:08+00:00",
  "periodType": "monthly",
  "periodStart": "01",
  "id": "0b4e6488-6de0-420c-8f56-fee665707d57",
  "amount": {
    "value": 40000,
    "currency": "GBP"
  },
  "spending": [
    {
      "date": "2018-07",
      "spent": -35000
    }
  ]
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|categoryId|string|true|none|none|
|dateCreated|string(date-time)|true|none|none|
|periodType|string|true|none|none|
|periodStart|string|true|none|none|
|id|string|true|none|The unique id of the spending goal|
|amount|object|true|none|none|
|» value|integer|true|none|The value of the amount in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the amount.|
|spending|[object]|true|none|none|
|» date|string|true|none|none|
|» spent|integer|true|none|The spending analysis amount of the specified month expressed in minor units of the currency.|

#### Enumerated Values

|Property|Value|
|---|---|
|periodType|monthly|
|periodType|annual|

<h2 id="tocSspendinggoalpost">SpendingGoalPost</h2>

<a id="schemaspendinggoalpost"></a>

```json
{
  "categoryId": "std:379c7ed2-27f3-401f-b581-f6507934f0f0",
  "amount": {
    "value": 50000
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|categoryId|string|true|none|The id of the category the spending goal should be created for|
|periodType|string|false|none|The period type of the goal, can be annual or monthly|
|periodStart|string|false|none|You can set a goal period to start on a certain date. DD when periodType is monthly, DD-MM when periodType is annual|
|amount|object|true|none|none|
|» value|integer|true|none|The amount of the spending goal in minor units of the currency, eg. pennies for GBP.|

#### Enumerated Values

|Property|Value|
|---|---|
|periodType|monthly|
|periodType|annual|

<h2 id="tocSspendinggoalpatch">SpendingGoalPatch</h2>

<a id="schemaspendinggoalpatch"></a>

```json
{
  "categoryId": "std:379c7ed2-27f3-401f-b581-f6507934f0f0",
  "amount": {
    "value": 300
  }
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|categoryId|string|false|none|The id of the category the spending goal should be created for|
|amount|object|false|none|none|
|» value|integer|true|none|The amount of the spending goal in minor units of the currency, eg. pennies for GBP.|

<h2 id="tocSsavingsgoals">SavingsGoals</h2>

<a id="schemasavingsgoals"></a>

```json
{
  "id": "27c316ef-8dfa-4a4b-b0a2-4979b7db1543",
  "name": "House deposit",
  "amount": {
    "value": 500000,
    "currency": "GBP"
  },
  "dateCreated": "2018-10-11T03:51:08+00:00",
  "imageUrl": "url",
  "notes": "Notes",
  "progressPercentage": 33.3,
  "progressAmount": 500000,
  "accounts": [
    {
      "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
    }
  ]
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|id|string|true|none|Unique id of the saving goal.|
|name|string|true|none|Name for the savings goal.|
|amount|object|true|none|none|
|» value|integer|true|none|The target amount in minor unit in minor units of the currency, eg. pennies for GBP.|
|» currency|string|true|none|The currency of the amount|
|dateCreated|string(date-time)|true|none|The date at which the savings goal was added.|
|imageUrl|string|false|none|none|
|notes|string|false|none|Arbitrary text that a user can add about a savings goal.|
|progressPercentage|number|false|none|Progresss achieved towards the target amount represented in percentage.|
|progressAmount|integer|false|none|Progresss achieved towards the target amount by adding up the balances of the selected accounts.|
|accounts|[object]|true|none|Accounts that will be taken into account towards the target amount.|
|» id|string|true|none|Id of the account|

<h2 id="tocSsavingsgoalspost">SavingsGoalsPost</h2>

<a id="schemasavingsgoalspost"></a>

```json
{
  "name": "House Deposit",
  "amount": {
    "value": 1800000
  },
  "imageUrl": "Image url",
  "notes": "Notes",
  "accounts": [
    {
      "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
    }
  ]
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|name|string|true|none|Name for the savings goal.|
|amount|object|true|none|none|
|» value|integer|true|none|The target amount in minor unit in minor units of the currency, eg. pennies for GBP.|
|» currency|string|false|none|The currency of the amount|
|imageUrl|string|false|none|none|
|notes|string|false|none|Arbitrary text that a user can add about a savings goal.|
|accounts|[object]|true|none|Accounts that will be taken into account towards the target amount.|
|» id|string|true|none|Id of the account|

<h2 id="tocSsavingsgoalspatch">SavingsGoalsPatch</h2>

<a id="schemasavingsgoalspatch"></a>

```json
{
  "name": "New name",
  "amount": {
    "value": 1800000
  },
  "imageUrl": "New Image url",
  "notes": "New Notes",
  "accounts": [
    {
      "id": "ac9bd177-d01e-449c-9f29-d3656d2edc2e"
    }
  ]
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|name|string|false|none|Name for the savings goal.|
|amount|object|false|none|none|
|» value|integer|true|none|The target amount in minor unit in minor units of the currency, eg. pennies for GBP.|
|imageUrl|string|false|none|none|
|notes|string|false|none|Arbitrary text that a user can add about a savings goal.|
|accounts|[object]|false|none|Accounts that will be taken into account towards the target amount.|
|» id|string|true|none|Id of the account|

<h2 id="tocSsyncpost">SyncPost</h2>

<a id="schemasyncpost"></a>

```json
{
  "customerIpAddress": "104.25.212.99",
  "customerLastLoggedTime": "2017-04-05T10:43:07+00:00"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|customerIpAddress|string|false|none|The customer ip address if it is currently logged in|
|customerLastLoggedTime|string|false|none|The time when the customer last logged in represened as ISO 8601 date-time format including timezone|

<h2 id="tocSlinks">Links</h2>

<a id="schemalinks"></a>

```json
{
  "next": "http://example.com",
  "prev": "http://example.com",
  "self": "http://example.com"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|next|string(uri)|false|none|The url to retrieve the next page of results from|
|prev|string(uri)|false|none|The url to retrieve the previous page of results from|
|self|string(uri)|true|none|The url of the current resource(s)|

<h2 id="tocSerror">Error</h2>

<a id="schemaerror"></a>

```json
{
  "code": "string",
  "message": "string",
  "correlationId": "string"
}

```

### Properties

|Name|Type|Required|Restrictions|Description|
|---|---|---|---|---|
|code|string|true|none|The error code|
|message|string|false|none|The error message|
|correlationId|string|false|none|Id that identifies the request and can be used to ask for more details related to the error|

