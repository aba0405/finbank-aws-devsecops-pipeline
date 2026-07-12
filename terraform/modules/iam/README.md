# IAM policies

Two sets of policies live here, intentionally:

- **Root files (`phase*.json`)**: the incremental, phase-scoped policies created
  as the project was built. Each was added to unblock a specific step, discovered
  by hitting a real permission wall and reading the error. Kept as a record of
  the least-privilege discovery process.

- **`consolidated/`**: the three function-scoped policies actually attached to the
  build user today (`finbank-infra-core`, `finbank-containers`, `finbank-pipeline`).
  The incremental policies were merged into these after hitting the IAM limit of
  10 managed policies per user. Each consolidated policy is under the 6 KB size cap.

The consolidated set is what's live; the phase files document how we got there.
