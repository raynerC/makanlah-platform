# infra/bootstrap

The chicken-and-egg layer: everything the rest of the repo's automation depends on, applied
**once, locally, by a human admin** — the only Terraform in this repo not applied by CI.

Creates:

- **S3 state bucket** (`makanlah-tfstate-<account-id>`): versioned, SSE-encrypted, all public
  access blocked, TLS-only bucket policy, 90-day expiry of noncurrent state versions. Uses
  S3-native locking (`use_lockfile`) — no DynamoDB lock table needed.
- **GitHub OIDC provider** for `token.actions.githubusercontent.com`.
- **`makanlah-ci-readonly-plan`**: assumable from any ref of the repo; `ReadOnlyAccess` plus
  write access to `*.tflock` state-lock objects only.
- **`makanlah-ci-deploy`**: assumable only from `main`, `v*` tags, or gated GitHub
  environments; `PowerUserAccess` plus IAM scoped to `makanlah-*` resources, with an explicit
  deny on the CI roles themselves.

## Usage

```sh
terraform init
terraform plan
terraform apply
```

First apply bootstraps with local state, then state is migrated into the bucket it just
created (`terraform init -migrate-state` after uncommenting the backend block — already done
for this repo). Destroying this stack is intentionally hard (`prevent_destroy` on the bucket).
