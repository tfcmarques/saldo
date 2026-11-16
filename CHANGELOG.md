# Changelog

What changed in each version of Saldo. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/): a new feature bumps the middle number, a fix
bumps the last one.

## [Unreleased]

## [1.1.0] - 2026-11-16

### Added

- Ambient and Glass themes (Settings, Theme). Glass needs macOS 26.
- Spare change settings: a default savings account to round up into and a multiplier.
- New entry: Add another (⌘Return), and a New category item in the category picker.
- Clicking a row in the Ledger or Recent activity opens it. Clicking an account card on the
  Dashboard opens the Ledger filtered to that account.
- The app version shows in Settings, About.

### Changed

- Touch ID is asked for inside the lock and welcome screens instead of a system popup,
  with a Use Password button.
- Transfers show as one row ("Everyday to Rainy day") when every account is in view, and
  spare change shows on its expense.
- New categories get an icon guessed from their name and a colour of their own. New
  accounts start with their type's icon.
- New transfers start from the accounts of the last one, and the pickers show balances.
- Cancel asks before discarding an amount or description you typed.
- The Dashboard puts key figures beside net worth when there is room, and its chart range
  fits your history until you pick one.

## [1.0.0] - 2026-11-08

First release: accounts, ledger, scheduled payments, spare change, debts, monthly bills,
dashboard, encrypted database with Touch ID unlock, backups and CSV export.

[Unreleased]: https://github.com/tfcmarques/saldo/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/tfcmarques/saldo/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/tfcmarques/saldo/releases/tag/v1.0.0
