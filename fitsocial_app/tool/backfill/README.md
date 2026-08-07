# Author attribution backfill (live project)

Repairs posts and comments written before author names were resolved from the
stored profile. Those records carry the placeholder `FitSocial Member` (or the
older `FitSocial User`) and have no author avatar.

Both fields are **denormalised at write time** — copied onto the post/comment
document so the feed renders without an extra read per card. That means fixing
the write path does not repair existing documents; only this script does.

> **This writes to the live `fitsocialv2` project.** Unlike `tool/seed`, which
> only ever talks to the local emulator, this needs real credentials and makes
> real changes. It runs in dry-run mode unless you pass `--apply`.

## What it changes

For each post and comment, it looks up the author's current profile and:

- Replaces `authorName` **only** when the stored value is empty, a placeholder,
  or an email address. A real name is never overwritten.
- Adds `authorAvatarUrl` **only** when the field is missing and the author has
  a profile photo.

It never deletes anything and never touches a document whose author has no
profile.

## Credentials

1. Firebase Console → **Project settings** → **Service accounts** →
   **Generate new private key**.
2. Save the JSON **outside the repository** — it is a real secret that grants
   full admin access to the project, and it bypasses your security rules.
3. Point the SDK at it:

   ```powershell
   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\outside\repo\serviceAccountKey.json"
   ```

## Run it

From `fitsocial_app/tool/backfill`:

```sh
npm install
```

Dry run first — prints every change it would make, writes nothing:

```sh
npm run backfill
```

Once the output looks right:

```sh
npm run backfill -- --apply
```

## Afterwards

Delete the service account key, or store it somewhere safe. Anyone holding it
can read and write your entire Firestore and Storage, ignoring the rules in
`firestore.rules` and `storage.rules`.
