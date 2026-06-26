# DartStream Quest RPG

DartStream Quest RPG is a standalone Flutter sample that uses DartStream SaaS
as the backend for a small game-like app.

It uses `dartstream_client` end-to-end:

- Firebase email/password auth and DartStream session onboarding
- live reads from profile, feature flags, inventory, and cloud-save services
- writes back to cloud save and the reactive event log

The app is configured for the DartStream dev backend by default and expects the
Firebase web API key to be provided at build time. No API key is committed in
the source tree.

## What the app does

- creates or signs in a Firebase user
- boots the user into a DartStream tenant
- shows a live RPG dashboard with XP, gold, streaks, quests, and bosses
- persists quest progress to cloud save
- logs gameplay events to the reactive service

## Run it

```sh
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=FIREBASE_API_KEY=your_web_key_here
```

To build the production web bundle:

```sh
flutter build web --release --dart-define=FIREBASE_API_KEY=your_web_key_here
```

To deploy to Firebase Hosting after building:

```sh
firebase deploy --only hosting
```

Required / optional build defines:

- `FIREBASE_API_KEY` required for Firebase email/password auth in the web app
- `API_AUTH` optional override for the auth service
- `API_PLATFORM` optional override for the platform service
- `API_EXPERIENCE` optional override for the experience service
- `API_REACTIVE` optional override for the reactive service
- `API_PERSISTENCE` optional override for the persistence service
- `API_BILLING` optional override for the billing service

If you do not set the service overrides, the sample uses the DartStream dev
hosts baked into `lib/config.dart`.

## OAuth2 / machine-to-machine

The Flutter sample app itself uses the Firebase user session flow. The OAuth2
client-credentials grant is used by the separate deep-dive harness to mint a
DartStream bearer token for service checks.

For a local machine-to-machine check, add these values to [`.env`](.env) and run
the deep-dive harness:

```cmd
dart run bin\oauth2_deepdive.dart
```

The harness automatically reads `.env` from the project root if the variables are
not already present in your `cmd` session. It expects:

- `OAUTH2_CLIENT_ID`
- `OAUTH2_CLIENT_SECRET`
- optional `OAUTH2_SCOPE`
- optional `OAUTH2_ISSUER` to pin the token issuer claim if you want an exact match
- optional `API_BILLING` if your token endpoint is not the default

Example:

```env
OAUTH2_CLIENT_ID=client_...
OAUTH2_CLIENT_SECRET=secret_...
API_BILLING=https://dev-apibilling.dartstream.io
```

What the harness does:

- exchanges `client_id` + `client_secret` for a DartStream Bearer token
- validates the JWT header uses `RS256`
- checks the token is not expired and is valid for the current time window
- decodes the JWT claims so you can confirm tenant/scope are present
- probes a few DartStream service endpoints with Bearer-only requests
- exits with a non-zero code if any verification step fails

## OAuth2 verification checklist

Run this when you want to confirm the OAuth2 client is still healthy:

1. Set `OAUTH2_CLIENT_ID` and `OAUTH2_CLIENT_SECRET` in `.env` or your shell.
2. Optionally set `OAUTH2_ISSUER` if you want the token issuer to match exactly.
3. Run `dart run bin\oauth2_deepdive.dart`.
4. Confirm the output shows `PASS` for token checks and all endpoint probes.
5. If any probe returns `401` or `403`, treat the client as unhealthy and recheck the client registration / issuer allowlist.

## Firebase Hosting

This repo includes Firebase Hosting config for the Flutter web output:

- [`firebase.json`](firebase.json) serves `build/web`
- [`.firebaserc`](.firebaserc) points the repo at the Firebase project that owns the Hosting site
- `firebase.json` targets the Hosting site `sample-app-chukwuemeka-izukanne`
- GitHub Actions creates preview URLs for branch pushes and pull requests, and deploys `main` to the live site

For GitHub Actions deployment, add these secrets:

- `FIREBASE_SERVICE_ACCOUNT_AORTEM_SAMPLE_APPS`

Then the deploy workflow can publish the web bundle to the hosting site and
create preview URLs automatically for feature branches / pull requests.

## Project structure

- `lib/config.dart` - backend host configuration and Firebase API key lookup
- `lib/state/session.dart` - authentication and tenant state
- `lib/screens/login_screen.dart` - create-account / sign-in UI
- `lib/screens/home_screen.dart` - live RPG dashboard and backend panels

## Why this repo exists

This repo is intentionally separate from `dartstream-saas`. It behaves like an
external customer project that consumes DartStream as a backend service rather
than a repository with direct access to the platform code.
