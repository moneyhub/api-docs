#!/usr/bin/env bash

curl -o ./source/identity-docs.md  https://identity.moneyhub.co.uk/auth-docs.md
curl -o ./source/api-gateway-docs.md  https://api.moneyhub.co.uk/docs.md
# curl -o ./source/identity-docs.md  http://identity.dev.127.0.0.1.nip.io/auth-docs.md
# curl -o ./source/api-gateway-docs.md  http://apigateway.dev.127.0.0.1.nip.io/docs.md
cat ./source/headers.md ./source/identity-docs.md ./source/api-gateway-docs.md > ./source/index.html.md
