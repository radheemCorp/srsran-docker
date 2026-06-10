# 20260417 — srsRAN docker build fails on apt (mirror sync), updated Dockerfile reverted

- **Date:** 2026-04-17
- **Area:** build / infra
- **Status:** Explained (transient apt mirror error, not a Dockerfile bug)
- **Components:** srsRAN_Project/docker (5gc + gnb images)

> Source: `tracks/srsran-prj-dockerfile-diff/` (Dockerfile.old, Dockerfile.updated,
> rsrran-docker-build-failing.md).

## Summary
- The updated Dockerfile build failed, so it was reverted to the old one.
- The actual failure was **not** a Dockerfile defect — it was a **transient Ubuntu
  archive mirror sync** error during `apt-get update`, which fails the `apt install`
  layer with exit code 100.
- Reverting "fixed" it only incidentally (a later build hit a healthy mirror); the
  updated Dockerfile is not necessarily broken.

## Context / setup
- `cd srsRAN_Project/docker && docker compose -f docker-compose.yml build` building the
  `5gc` (ubuntu:22.04) and `gnb` (ubuntu:24.04) images.

## Investigation / what was determined
- The `5gc base 2/8` layer failed:
  ```
  RUN DEBIAN_FRONTEND=noninteractive apt-get update \
   && apt install -y software-properties-common && rm -rf /var/lib/apt/lists/*
  ```
  ```
  Err:15 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 Packages
    File has unexpected size (4263778 != 4263737). Mirror sync in progress? [IP: 91.189.92.22]
  E: Failed to fetch .../jammy-updates/main/binary-amd64/Packages.gz  File has unexpected size ...
  E: Some index files failed to download. They have been ignored, or old ones used instead.
  target 5gc: failed to solve: ... exit code: 100
  ```
- The error message itself names the cause: *"Mirror sync in progress?"* — the
  archive.ubuntu.com mirror was mid-sync, serving an index whose size didn't match its
  Release hashes. The fetch took 4m36s at ~151 kB/s (slow mirror), consistent with that.

## Root cause
- **Transient apt mirror inconsistency** (`archive.ubuntu.com` mid-sync), not the
  updated Dockerfile. Any `apt-get update` against that mirror at that moment would fail.

## Resolution / workaround
- Immediate: reverted to `Dockerfile.old` and the build succeeded later (healthy mirror).
- Better fixes for the transient class:
  - Retry the build (the simplest fix — the mirror resyncs).
  - Pin/point apt at a reliable mirror, or add `-o Acquire::Retries=3` to `apt-get update`.
  - Don't conclude the new Dockerfile is broken from this log — re-test it once the
    mirror is healthy before discarding the update.

## Lessons / gotchas
- `apt-get update` "File has unexpected size … Mirror sync in progress?" → infrastructure
  flake, not your Dockerfile. Retry before reverting code.
- A slow fetch (here 4.5 min) is a hint the chosen mirror is struggling.

## References
- `tracks/srsran-prj-dockerfile-diff/{Dockerfile.old,Dockerfile.updated,rsrran-docker-build-failing.md}`.
