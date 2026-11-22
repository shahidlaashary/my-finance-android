# New Assets System v2

This feature is being built as a parallel implementation. The legacy Assets
System remains intact and is not used as the v2 persistence layer.

## Isolation boundary

- Models live in `lib/features/new_assets_v2/models`.
- Services live in `lib/features/new_assets_v2/services`.
- SQLite tables are namespaced `new_asset_v2_*`.
- Legacy `assets` and `asset_attachments` tables are not read or written.
- The v2 asset's `wallet_id` is nullable by design. Loan-funded purchases
  require a party, not a matching-currency wallet.
- Repayment wallet selection belongs to the repayment action, not asset creation.

## Delivery stages

1. Independent domain model and persistence tables.
2. Add/list/details UI and attachments.
3. Loan creation/linkage and repayment flow, with atomic wallet debit and
   linked loan, wallet transaction, and asset event records.
4. Sale flow, consolidated-balance integration, totals and reports.
5. Enable v2 as the primary Assets experience after verification.

No routing switch is made in this foundation stage.
