# Moneyhub API Documentation

The docs use Slate under the hood. You might want to learn more about editing [Slate markdown](https://github.com/lord/slate/wiki/Markdown-Syntax).

### Prerequisites

You're going to need:

 - **Linux or macOS** — Windows may work, but is unsupported.
 - **Ruby, version 2.3.1 or newer**
 - **Bundler** — If Ruby is already installed, but the `bundle` command doesn't work, just run `gem install bundler` in a terminal.

### Getting Set Up

1. Clone this repository
2. Run install command `bundle install`
3. Run server `bundle exec middleman server` or `npm run start`

You can now see the docs at http://localhost:4567.

### Editing locally

You can run `./get-latest-docs.sh` or `npm run rebuild` when working locally with the docs to see the changes before deploying the docs.

You can change the script to point to your local version of identity service and api gateway, otherwise it will point to prod.

### Publishing docs

In order to publish the docs you need to run `./deploy.sh` or `npm run deploy`.

This will take the docs from the Identity service and API gateway in prod and publish it to https://moneyhub.github.io/api-docs.
