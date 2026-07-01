# DartStream Quest RPG

DartStream Quest RPG is a standalone Flutter sample that uses DartStream SaaS
as the backend for a small game-like app.

It follows the same customer-style connection flow as the DartStream sample
app:

- `DartStreamClient.signUp(...)` / `DartStreamClient.signIn(...)` exchange
  Firebase email/password credentials for a live DartStream session
- Google sign-in is also supported through the same DartStream session model
- the returned `DartStreamConnection` is kept in app state and used for every
  typed SDK call
- service reads and writes go through the SDK's auth, platform, experience,
  reactive, and persistence clients

The app is configured for the DartStream dev backend by default and expects the
Firebase web API key to be provided at build time. Optional `API_*` build
defines can override the service hosts. No API key is committed in the source
tree.

IntelliToggle is wired in as an optional OpenFeature-backed screen, matching
the sample app pattern. After sign-in you can open the dedicated IntelliToggle
screen, register the provider with OAuth2 client-credentials, and evaluate live
flags against the signed-in DartStream identity.

## What the app does

- creates or signs in a Firebase user
- lets users continue with Google and lands them in the same DartStream tenant
- boots the user into a DartStream tenant
- shows a live RPG dashboard with XP, gold, streaks, quests, and bosses
- persists quest progress to cloud save
- logs gameplay events to the reactive service

## Run it

```sh
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=FIREBASE_API_KEY=your_web_key_here
```

To enable Google sign-in, add a Google OAuth client ID as well:

```sh
flutter run -d chrome --web-port=3000 \
  --dart-define=FIREBASE_API_KEY=your_web_key_here \
  --dart-define=GOOGLE_OAUTH_CLIENT_ID=your_google_oauth_client_id.apps.googleusercontent.com
```

To build the production web bundle:

```sh
flutter build web --release \
  --dart-define=FIREBASE_API_KEY=your_web_key_here \
  --dart-define=INTELLITOGGLE_API_URL=https://dev-api.intellitoggle.com \
  --dart-define=INTELLITOGGLE_CLIENT_ID=client_... \
  --dart-define=INTELLITOGGLE_CLIENT_SECRET=secret_... \
  --dart-define=INTELLITOGGLE_TENANT_ID=tenant_...
```

To deploy to Firebase Hosting after building:

```sh
firebase deploy --only hosting
```

Required / optional build defines:

- `FIREBASE_API_KEY` required for Firebase email/password auth in the web app
- `GOOGLE_OAUTH_CLIENT_ID` optional for Google sign-in on the web build
- `API_AUTH` optional override for the auth service
- `API_PLATFORM` optional override for the platform service
- `API_EXPERIENCE` optional override for the experience service
- `API_REACTIVE` optional override for the reactive service
- `API_PERSISTENCE` optional override for the persistence service
- `API_BILLING` optional override for the billing service
- `INTELLITOGGLE_API_URL` optional override for the IntelliToggle API base URL
- `INTELLITOGGLE_CLIENT_ID` required for IntelliToggle OAuth2
- `INTELLITOGGLE_CLIENT_SECRET` required for IntelliToggle OAuth2
- `INTELLITOGGLE_TENANT_ID` required for IntelliToggle OAuth2
- `INTELLITOGGLE_API_URL` optional, defaults to `https://api.intellitoggle.com`
- `INTELLITOGGLE_BOOL_FLAG` optional flag key for the deep-dive harness
- `INTELLITOGGLE_STRING_FLAG` optional flag key for the deep-dive harness
- `INTELLITOGGLE_INT_FLAG` optional flag key for the deep-dive harness
- `INTELLITOGGLE_OBJECT_FLAG` optional flag key for the deep-dive harness
- `INTELLITOGGLE_TARGET_USER` optional targeting key for the deep-dive harness

If you do not set the service overrides, the sample uses the DartStream dev
hosts baked into `lib/config.dart`.

For a Firebase preview or live Hosting deployment, make sure the web bundle was
built with the IntelliToggle defines above. If those defines are missing, the
dedicated IntelliToggle screen will fall back to its "not configured" state and
the button will not be able to register the provider.

### IntelliToggle integration

The IntelliToggle provider uses OAuth2 client-credentials internally, so the
Flutter app never mints a token by hand. The correct setup mirrors the sample
app:

1. Create an OAuth client in the IntelliToggle dashboard and copy the
   `clientId`, `clientSecret`, and `tenantId`.
2. Add those values to your local `.env` or pass them as `--dart-define`
   values when you run Flutter.
3. If the client was created on the IntelliToggle **dev** dashboard, override
   the API URL with `https://dev-api.intellitoggle.com`. Otherwise the default
   production host is `https://api.intellitoggle.com`.
4. Launch the app with the IntelliToggle defines enabled so the dedicated
   screen can register the provider and evaluate flags.

Example run command:

```sh
flutter run -d chrome --web-port=3000 \
  --dart-define=FIREBASE_API_KEY=your_web_key_here \
  --dart-define=INTELLITOGGLE_API_URL=https://dev-api.intellitoggle.com \
  --dart-define=INTELLITOGGLE_CLIENT_ID=client_... \
  --dart-define=INTELLITOGGLE_CLIENT_SECRET=secret_... \
  --dart-define=INTELLITOGGLE_TENANT_ID=tenant_...
```

If you are using a production IntelliToggle tenant, pass the production host
explicitly with `--dart-define=INTELLITOGGLE_API_URL=https://api.intellitoggle.com`.

### IntelliToggle deep-dive

The quest repo now includes the same OpenFeature-based deep-dive harness as the
sample app:

```cmd
dart run bin\intellitoggle_deepdive.dart
```

It reads these environment variables from `.env` or your shell:

- `INTELLITOGGLE_CLIENT_ID`
- `INTELLITOGGLE_CLIENT_SECRET`
- `INTELLITOGGLE_TENANT_ID`
- `INTELLITOGGLE_API_URL` optional, defaults to `https://api.intellitoggle.com`
- `INTELLITOGGLE_BOOL_FLAG` optional, defaults to `new-dashboard`
- `INTELLITOGGLE_STRING_FLAG` optional, defaults to `hero-variant`
- `INTELLITOGGLE_INT_FLAG` optional, defaults to `max-items`
- `INTELLITOGGLE_OBJECT_FLAG` optional, defaults to `theme-config`
- `INTELLITOGGLE_TARGET_USER` optional, defaults to `deepdive-cli`

Like the sample, the harness registers the provider, verifies `READY`, evaluates
boolean/string/integer/object flags through OpenFeature, and confirms a bad
secret fails closed.

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

For a Firebase preview or live Hosting deployment, make sure the web bundle was
built with the Firebase and Google sign-in defines above. If the Google client
ID is omitted, the Google button is hidden.

The GitHub Actions deploy job also expects these secrets so the hosted build
gets the same IntelliToggle configuration as local runs. If any of them are
missing, the deployment now fails instead of publishing a bundle that only
shows the IntelliToggle "not configured" screen:

- `INTELLITOGGLE_API_URL`
- `INTELLITOGGLE_CLIENT_ID`
- `INTELLITOGGLE_CLIENT_SECRET`
- `INTELLITOGGLE_TENANT_ID`
- `FIREBASE_WEB_API_KEY`

## Project structure

- `lib/config.dart` - backend host configuration and Firebase API key lookup
- `lib/state/session.dart` - authentication and tenant state
- `lib/screens/login_screen.dart` - create-account / sign-in UI
- `lib/screens/home_screen.dart` - live RPG dashboard and backend panels
- `bin/intellitoggle_deepdive.dart` - IntelliToggle OpenFeature deep-dive

## Why this repo exists

This repo is intentionally separate from `dartstream-saas`. It behaves like an
external customer project that consumes DartStream as a backend service rather
than a repository with direct access to the platform code.
