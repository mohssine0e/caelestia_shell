# Known issues

This is the current list of confirmed issues deferred while the setup is in development. Keep each entry's status, evidence, and completion check up to date. Older investigation notes are in [`audits/`](audits/).

## P1 — Lock can be released without authentication

**Status:** Confirmed on 2026-11-27; deferred at the user's request.

**Scope:** A local process with access to the current user's Quickshell IPC can release the lock. No remote path has been demonstrated.

**Evidence:** [`modules/lock/Lock.qml`](modules/lock/Lock.qml) exposes public shortcut and IPC unlock handlers. [`modules/lock/LockSurface.qml`](modules/lock/LockSurface.qml) handles their unlock signal by clearing the locked state. In a controlled live check, the lock state changed from `true` to `false` through the public handler without a successful PAM authentication.

**Fix when ready:** Remove the public unlock shortcut and IPC handler. Keep unlock available only through the authenticated path in [`modules/lock/Pam.qml`](modules/lock/Pam.qml).

**Done when:** The public handler and shortcut are gone; successful password authentication still unlocks; an unauthenticated local request cannot unlock in a controlled test.

See also the [earlier security audit](audits/2026-11-12-setup/09-privacy-and-security.md).

## Recording future issues

Add a dated entry with a priority, status, affected files, observed behavior, and a concrete completion check. Mark an issue resolved only after verifying its fix.
