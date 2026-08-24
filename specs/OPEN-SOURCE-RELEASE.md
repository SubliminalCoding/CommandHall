# Deferred source-release procedure

CommandHall's current release plan is commercial-only. This document is retained as a dormant safety checklist in case the owner later makes a separate, explicit decision to publish source. It must not be used for a customer release.

## Owner decisions

Before export:

- select an OSI-approved license and add its canonical text as `LICENSE`;
- confirm the public GitHub owner and repository name;
- confirm whether signed binaries will be free downloads from GitHub Releases;
- complete a trademark review for CommandHall in the intended markets.

## Create the public source tree

1. Make the private working tree internally consistent and run `scripts/ci.sh`.
2. Create a new empty directory outside this repository.
3. Run `scripts/export-public-source.sh DESTINATION`.
4. Inspect every exported file and run the tests again from the exported directory.
5. Confirm that research images, quote banks, private operational files, the commercial license, build products, and local evidence are absent.
6. Initialize a new Git repository in the exported directory with the intended public author name and email.
7. Create the public GitHub repository from that clean initial commit. Do not change the visibility of the private development repository.

The clean-history approach prevents old research artifacts, private hostnames, and local-only commit metadata from becoming reachable through Git history.

## GitHub settings

After creating the public repository:

- make `main` the default branch;
- require the macOS CI check before merging;
- block force pushes and branch deletion on `main`;
- restrict Actions to the workflows required by this repository;
- enable Dependabot alerts and secret scanning;
- enable private vulnerability reporting;
- keep release secrets in the protected `release` environment;
- require a reviewer for the `release` environment if a second trusted reviewer is available.

## First release

1. Set `VERSION`.
2. Run `scripts/ci.sh` in the clean public checkout.
3. Run `scripts/acceptance.sh` on the signing machine.
4. Confirm the signing and notarization secrets described in [RELEASE-OPERATIONS.md](RELEASE-OPERATIONS.md).
5. Tag exactly `v$(<VERSION)`.
6. Watch the release workflow through completion.
7. Download the published archive on another Mac, verify its checksum and signature, launch it, and run a basic provider session.

Do not announce the release until the source checkout, release archive, checksum, signature, notarization ticket, and smoke launch have all been verified.
