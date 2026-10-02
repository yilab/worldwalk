#!/usr/bin/env bash
set -e

echo "Deploying worldwalk website to Cloudflare Workers..."
npx wrangler deploy
