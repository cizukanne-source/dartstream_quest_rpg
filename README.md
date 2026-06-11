# DartStream Quest RPG

DartStream Quest RPG is a standalone Flutter sample that uses DartStream SaaS
as the backend for a small game-like app.

It follows the same integration pattern as the reference apps:

- `dartstream_client` for Firebase email/password auth and DartStream session
  onboarding
- DartStream bootstrap using the Firebase `idToken`
- live reads from profile, feature flags, inventory, and cloud-save services
- writes back to cloud save and the reactive event log

## What the app does

- creates or signs in a Firebase user
- boots the user into a DartStream tenant
- shows a live RPG dashboard with XP, gold, streaks, quests, and bosses
- persists quest progress to cloud save
- logs gameplay events to the reactive service

## Run it

```sh
flutter pub get
flutter run -d chrome --web-port=3000 \
  --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_WEB_KEY
```

Optional backend overrides:

- `API_AUTH`
- `API_PLATFORM`
- `API_EXPERIENCE`
- `API_REACTIVE`
- `API_PERSISTENCE`

If you do not set those variables, the sample uses the default DartStream dev
hosts baked into `lib/config.dart`.

## Project structure

- `lib/config.dart` - backend host configuration and Firebase API key lookup
- `lib/api/firebase_auth.dart` - `dartstream_client` auth bridge
- `lib/api/dartstream.dart` - typed DartStream backend client
- `lib/state/session.dart` - authentication and tenant state
- `lib/screens/login_screen.dart` - create-account / sign-in UI
- `lib/screens/home_screen.dart` - live RPG dashboard and backend panels

## Why this repo exists

This repo is intentionally separate from `dartstream-saas`. It behaves like an
external customer project that consumes DartStream as a backend service rather
than a repository with direct access to the platform code.
