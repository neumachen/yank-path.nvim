# Releasing yank-path.nvim

This project uses tag-driven releases. Pushing a tag matching `v*` to the
`main` branch triggers `.github/workflows/release.yml`, which runs
`gh release create --generate-notes` against the tag.

## Prerequisites

- All CI checks green on `main` for the commit you are about to tag.
- Working tree clean (`git status` reports nothing).
- Local `main` matches `origin/main`.
- `gh` CLI authenticated for the release job's `GITHUB_TOKEN` to work
  inside the workflow runner (no local auth needed for the manual tag
  push; the workflow uses the ephemeral token GitHub provides).

## Versioning

`yank-path.nvim` follows [Semantic Versioning](https://semver.org/):

- **MAJOR** for breaking changes to the public Lua API or `:YankPath` UX.
- **MINOR** for additive features (new built-in strategies, new config
  options, new picker backends).
- **PATCH** for bug fixes and internal refactors that do not change
  observable behavior.

Pre-`1.0.0`, minor bumps may carry breaking changes; pin to a specific tag
or commit if you depend on a stable surface during the `0.x` series.

## Cutting a release

1. **Verify CI is green** on the commit you intend to tag:

   ```bash
   git fetch origin
   git checkout main
   git pull --ff-only
   gh run list --branch main --limit 5
   ```

   All recent runs of the `CI` workflow must show `success`.

2. **Choose the version**:

   ```bash
   # Inspect the previous tag, if any.
   git tag -l --sort=-v:refname | head -5
   ```

   Decide the next version per semver. The first release is `v0.1.0`.

3. **Create an annotated tag**:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   ```

   Annotated tags carry a tagger, date, and message; `gh release create`
   uses them to generate richer notes.

4. **Push the tag**:

   ```bash
   git push origin vX.Y.Z
   ```

   This triggers `.github/workflows/release.yml`. The workflow:

   - checks out the tagged commit,
   - runs `gh release create "$GITHUB_REF_NAME" --title "$GITHUB_REF_NAME" --generate-notes`,
   - publishes a release with notes auto-generated from the merged PRs and
     commits since the previous tag.

5. **Verify the release**:

   ```bash
   gh release view vX.Y.Z
   ```

   Confirm the title, notes, and tarball look correct.

## If the release workflow fails

Re-running it from the Actions tab is safe — `gh release create` is
idempotent against an already-published tag (it errors out without
modifying anything). If the release was partially created, delete it
manually and re-run:

```bash
gh release delete vX.Y.Z --yes
git push --delete origin vX.Y.Z   # only if you also need to redo the tag
```

Then re-tag and re-push.

## Yanking a bad release

A published release that ships a regression can be marked as a draft via:

```bash
gh release edit vX.Y.Z --draft
```

Followed by a patch release (`vX.Y.(Z+1)`) with the fix. Avoid force-pushing
or deleting tags that users may already be pinning.
