# MITT

MITT consists of a Flutter mobile app for pet owners, a Flutter web portal for store owners and admins, and a Dart REST API backed by MySQL.

## Run locally

The local development database is `mitt_dev`. Backend connection settings are read from `backend/.env.local` and can be overridden with environment variables. For another MySQL server, copy `backend/.env.example`, set its host, schema and service credentials, then apply the migrations. Use MySQL 8 and InnoDB. Remote database connections require TLS.

From the Flutter project folder, build the web portal:

```powershell
flutter pub get
flutter build web --target lib/main_portal.dart
```

From the backend folder:

```powershell
dart pub get
dart run bin/server.dart migrate
dart run bin/server.dart
```

Open **http://127.0.0.1:8080/** for the management portal. The API is served on the same origin under `/api/v1`. Register a store-owner account there, upload a license, and sign in as an admin to review it. The initial local administrator credentials are in `backend/.data/initial-admin.txt` for this installation. Use the password-change form to replace that initial password. For a fresh installation, run `dart run bin/server.dart create-admin` with `MITT_ADMIN_PHONE` and `MITT_ADMIN_PASSWORD` set in the process environment.

To launch the pet-owner app on an Android emulator, return to the Flutter project folder and run:

```powershell
flutter run -t lib/main.dart --dart-define=MITT_API_URL=http://10.0.2.2:8080/api/v1
```

For a physical device, use a reachable backend address through `MITT_API_URL`. The local HTTP setup is for development. For deployment, serve the API and portal over HTTPS, enable secure cookies, and set `MITT_ORIGIN` to the portal origin if a reverse proxy changes the origin seen by the Dart server. Uploaded files live outside the portal's public directory. Back up the uploads directory along with MySQL.

## Architecture

- `lib/app/` contains the Flutter shell, theme, and shared widgets.
- `lib/features/` contains auth, shopper, store-owner, and admin views and their data access code.
- `lib/core/` contains the HTTP client and browser file picker.
- `backend/lib/src/http/` validates HTTP requests and maps responses.
- `backend/lib/src/modules/` enforces account, catalog, inventory, and order rules.
- `backend/lib/src/infrastructure/` manages the MySQL pool and versioned migrations.
- `backend/migrations/mysql/` contains the MySQL schema. This replaces the old PostgreSQL migration.

The API owns permissions, stock counts, prices at checkout, and transitions. Checkout saves a single-store order without deducting inventory. Confirmation locks the order and inventory rows and commits status, deductions, and stock movements together. A failed confirmation leaves every line unchanged.

## Validation and tests

From the Flutter project folder:

```powershell
flutter analyze
flutter test
```

From the backend folder:

```powershell
dart analyze
dart test
```

Backend integration tests read `backend/.env.test` when launched from `backend/` and require the separate `mitt_test` schema. They apply the migrations and use real HTTP requests and SQL assertions for preconditions and postconditions. Coverage includes pending-store restrictions, private license access, stock initialization, checkout idempotency, shortage rollback, concurrent last-unit confirmation, ownership checks, password changes, bans, and cookie-origin validation.

The Flutter live API test can also be run on a configured test device. Start a test API with `MITT_CONFIG=.env.test`, a different port, and a separate `MITT_FILE_DIR`; then pass its address as `MITT_TEST_API_URL` when running `integration_test/live_api_test.dart`.

Flutter plugin setup on Windows may require Developer Mode to create native desktop symlinks. After dependencies have resolved, `--no-pub` allows the web build and Flutter tests to reuse the existing package configuration. The web portal uses the JavaScript Flutter build.
