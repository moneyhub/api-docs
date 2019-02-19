#!/usr/bin/env bash

curl -o ./source/identity-docs.md  http://identity.dev.127.0.0.1.nip.io/docs.md
curl -o ./source/api-gateway-docs.md  http://apigateway.dev.127.0.0.1.nip.io/docs.md
cat ./source/identity-docs.md ./source/api-gateway-docs.md > ./source/index.html.md

git add .
git commit -m "Update docs"
git push
