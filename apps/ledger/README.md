# Ledger

A personal expense tracker, built entirely in the flx DSL. This is the
flagship app — the thing that decides whether the framework is real.

```bash
make run          # from the repo root
```

## What it does

Accounts, categories and transactions, with monthly budgets and a PIN lock.
Data lives on the device; there is no backend.

| Screen                  | Route                  |
| ----------------------- | ---------------------- |
| Dashboard               | `/`                    |
| Transaction history     | `/transactions`        |
| New transaction         | `/transactions/new`    |
| Edit transaction        | `/transactions/:id`    |
| Accounts                | `/accounts`            |
| Account detail          | `/accounts/:id`        |
| Categories and budgets  | `/categories`          |
| Settings                | `/settings`            |
| Lock                    | `/lock`                |

## Layers

```
lib/domain/    Money, models, Period — plain Dart, no Flutter
lib/data/      Storage, repository, security, ViewModels
lib/pages/     *.flx screens (source of truth) + generated *.dart
lib/main.dart  Object graph and app root
```

`Money` is an integer number of cents. Doubles are never used for money —
`0.1 + 0.2 != 0.3` is a rounding bug waiting to appear in a balance.

`LedgerRepository` holds an in-memory cache so reads are synchronous and the
UI never awaits, and is a `Notifier` so a write on one screen refreshes the
ViewModels behind every other one.

`Storage` is an interface with two implementations: `PrefsStorage` for the
app, `MemoryStorage` for tests. Swapping in sqflite, drift or a network
backend is one more subclass and one line in `main.dart`.

## What it forced the framework to grow

Every one of these came from a screen that could not be written otherwise:

| Need                              | Added to flx                              |
| --------------------------------- | ----------------------------------------- |
| App bars and screen chrome        | `Screen` / `Panel` container widgets, and `children:` blocks in the DSL |
| Long transaction lists            | `LazyColumn` / `LazyRow` / `LazyGrid` and builder blocks — `{ tx in ... }` |
| `onChanged`, `onSelected`         | Parameterised callbacks — `{ value -> ... }` |
| Live form validation              | `useTextField`, which rebuilds on every keystroke |
| Forms                             | `Field`, `Picker`, `Segmented`, `DateField`, `Toggle` |
| Cross-screen invalidation         | `Notifier`, the non-UI half of `ViewModel` |
| `/transactions/new` vs `/:id`     | Route ordering by specificity in flxc     |

It also surfaced three genuine bugs, all now covered by tests: `onEndReached`
loading every page in a single flick, modifier arguments silently colliding
with a widget's own parameters, and seeded history dated into the future.

## Tests

108 tests: `money_test` (domain arithmetic and parsing), `repository_test`
(persistence, pagination, budgets), `view_models_test` (validation, lock,
filters), and `app_test`, which drives the generated screens end to end over
`MemoryStorage`.

```bash
cd apps/ledger && flutter test
```

## Not done

- No backend, so no sync and no multi-device.
- The PIN guards a local ledger; it is a salted SHA-256 digest, not a
  keychain-backed secret, and a four-digit space is small.
- No charts, recurring transactions, CSV import/export, or multi-currency.
- `shared_preferences` is fine at this size but is not a database; a few
  thousand transactions is the point to move to sqflite or drift.
