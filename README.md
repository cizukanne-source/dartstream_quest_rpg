# DartStream Quest RPG

DartStream Quest RPG is a standalone Flutter sample that uses DartStream SaaS
as the backend for a small game-like app.

It uses `dartstream_client` end-to-end:

- Firebase email/password auth and DartStream session onboarding
- live reads from profile, feature flags, inventory, and cloud-save services
- writes back to cloud save and the reactive event log

The app includes a built-in Firebase Web API key for the sample project, so it
starts without extra `--dart-define` flags. You can still override it at build
time if needed.

## What the app does

- creates or signs in a Firebase user
- boots the user into a DartStream tenant
- shows a live RPG dashboard with XP, gold, streaks, quests, and bosses
- persists quest progress to cloud save
- logs gameplay events to the reactive service

## Run it

```sh
flutter pub get
flutter run -d chrome --web-port=3000
```

To build the production web bundle:

```sh
flutter build web --release
```

To deploy to Firebase Hosting after building:

```sh
firebase deploy --only hosting
```

Optional backend overrides:

- `API_AUTH`
- `API_PLATFORM`
- `API_EXPERIENCE`
- `API_REACTIVE`
- `API_PERSISTENCE`
- `API_BILLING`

If you do not set those variables, the sample uses the default public DartStream
hosts baked into `lib/config.dart`.

## OAuth2 / machine-to-machine

The Flutter sample app itself still uses the public Firebase user flow. Keep the
OAuth2 client secret on the backend side only.

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
- optional `API_BILLING` if your token endpoint is not the default

Example:

```env
OAUTH2_CLIENT_ID=client_...
OAUTH2_CLIENT_SECRET=secret_...
API_BILLING=https://dev-apibilling.dartstream.io
```

What the harness does:

- exchanges `client_id` + `client_secret` for a DartStream Bearer token
- decodes the JWT claims so you can confirm tenant/scope are present
- probes a few DartStream service endpoints with Bearer-only requests

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
