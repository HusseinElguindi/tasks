# Deploying the sync server (SPEC §10, S4)

**Not run yet.** Every command below creates or changes Cloudflare resources, or signs in to Cloudflare.
Nothing here has been run; it waits for the user's go-ahead.

What gets created, all on the Workers Free plan (SQLite-backed Durable Objects are included):

- one Worker, `tasks`, served at `https://tasks.<your-subdomain>.workers.dev` (no custom domain);
- one Durable Object namespace for `UserLog`, through the `v1` migration (`new_sqlite_classes`);
- one secret, `API_TOKEN`;
- Workers Logs for the Worker (`observability.enabled` in `wrangler.jsonc`), so errors show up in the dashboard.
  A personal app stays far inside the free allowance. Delete that line to opt out.

All commands run from `server/`, with `pnpm install` done.

## 1. Sign in

```sh
npx wrangler login      # opens a browser for OAuth
npx wrangler whoami     # confirm the account
```

If the account has never used `workers.dev`, the first deploy asks to register a subdomain.

## 2. Make the token

Keep the file outside the repo. It's the only copy of the token besides the Keychain.

```sh
umask 077
printf 'API_TOKEN=%s\n' "$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')" > ~/.tasks-sync.env
```

## 3. Deploy

`wrangler.jsonc` declares `API_TOKEN` as a required secret, so the first deploy has to carry it:

```sh
npx wrangler deploy --secrets-file ~/.tasks-sync.env
```

This uploads the Worker, applies the `v1` migration and sets the secret in one step. Note the
`https://tasks.<subdomain>.workers.dev` URL it prints.

## 4. Smoke test

```sh
URL=https://tasks.<subdomain>.workers.dev/v1/sync
TOKEN=$(sed -n 's/^API_TOKEN=//p' ~/.tasks-sync.env)

# A pull from 0 on the empty log
curl -s -X POST "$URL" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"from":0,"base":null,"ops":[]}'
# → {"entries":[],"head":0,"more":false}

# Compression: Content-Encoding follows Accept-Encoding
curl --compressed -s -D - -o /dev/null -X POST "$URL" -H "Authorization: Bearer $TOKEN" \
  -d '{"from":0,"base":null,"ops":[]}'
# → Content-Encoding: gzip   (macOS curl offers deflate, gzip)
curl -s -D - -o /dev/null -X POST "$URL" -H "Authorization: Bearer $TOKEN" -H 'Accept-Encoding: br' \
  -d '{"from":0,"base":null,"ops":[]}'
# → Content-Encoding: br

# Auth and routing
curl -s -X POST "$URL" -d '{}'    # → 401 bad_token
curl -s "$URL"                    # → 405 method_not_allowed
```

SPEC §10 suggests `curl --compressed -sI`. `-I` sends `HEAD`, which gets a `405` (with `Content-Encoding`
still set), so the `POST` form above is the meaningful check.

Then enter the base URL (`https://tasks.<subdomain>.workers.dev`) and the token in the macOS app's sync settings.

## Later

| Task | Command | Note |
|------|---------|------|
| Redeploy after a code change | `npx wrangler deploy` | The secret and the log are kept. |
| Rotate the token | `npx wrangler secret put API_TOKEN` | Each Mac then shows "Check sync token" until it gets the new one. |
| Roll back the code | `npx wrangler rollback` | Storage is untouched. |
| Tail logs | `npx wrangler tail` | |
| Delete everything | `npx wrangler delete` | Destroys the server log. It doesn't destroy data: on the resulting 409, each Mac re-pushes every op it has (SPEC §5) and rebuilds the log. To really start over, also delete each Mac's Application Support data before it syncs. |
