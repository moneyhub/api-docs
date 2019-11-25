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
5. Response type set to be `code id_token`
6. Grant types to be authorization_code, refresh_token, client_credentials and implicit
7. Redirect uris are required to be https://

This settings will require the following changes in the auth flow if the authentication that was used previously was `client_secret_basic`:

1. Allowing an `implicit` grant type in the settings requires:
   - A nonce to be added to the request object when generating an authorization url ([OpenId Nonce](https://openid.net/specs/openid-connect-core-1_0.html#NonceNotes))
   - The same nonce value needs to be used when exchanging the authorization code for the token set at the end of the authorization process.
2. Having a response type of `code id_token` will cause the following changes:

- You will receive the code and id token encoded in the fragment part of your registered callback instead of receiving it as query params. This is a security enhancement as this way it reduces the likelihood of the id token to be leaked during transport.
- The id_token will need to be used when exchanging the authorization code for the token set at the end of the authorization process.

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
      "id": "b74f1a79f0be8bdb857d82d0f041d7d2:6fbebd5e-fb2a-4814-bdaf-9a8871167f43",
      "name": "Nationwide Open Banking",
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

- `resync`: "This connection hasn't been updated recently, most likely due to the requirement for the user to enter multi factor authentication. We advise getting the user to refresh manually.",
- `sync_error`: "There was an error syncing this connection, we will try to resync later.",
- `sync_partial`: "There was an error syncing some of the transactions on this account, we will try to resync later",
- `mfa_required`: "This connection requires multi factor authentication and must be refreshed manually",
- `credentials_error`: "This connection can no longer be updated, the user may have changed their credentials or revoked access. Please take the user through a refresh flow where they can "

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

It returns all the payments that have been initiated by an API client regardless if they were authorised or not. Payments that have been authorised have the properties `exchangedAt` and `connectionId`.

This route requires an access token from the client credentials grant with the scope of `payment:read`.

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
