# Releasing

Idealize uses a simple tag-based release system. No CI/CD — just git tags that the install script reads from.

## Channels

| Channel | Tag | Install command | Purpose |
|---------|-----|-----------------|---------|
| **stable** | `latest` | `curl -fsSL idealize.diananerd.com/install \| bash` | Default. What users get. |
| **beta** | `beta` | `curl -fsSL idealize.diananerd.com/install?channel=beta \| bash` | Public testing before promoting to stable. |

Both `latest` and `beta` are **movable** tags — they get force-pushed to new commits as needed.

## Version tags

Each stable release also gets an **immutable** version tag: `v0.2.0`, `v0.3.0`, etc. These never move. They exist for reference and rollback.

## Workflow

### Day-to-day development

Work on `main`. Commit and push freely — users won't see changes until you tag them.

```bash
git add . && git commit -m "feat: whatever" && git push
```

### Publish a beta

When you want public testing:

```bash
git tag -f beta
git push origin beta --force
```

Users on the beta channel get the update next time they install. Existing installs are unaffected (there's no auto-update).

### Promote beta to stable

After validating the beta:

```bash
# Move latest to current commit
git tag -f latest
git push origin latest --force

# Stamp an immutable version tag
git tag v0.3.0
git push origin v0.3.0
```

Update `VERSION` in `bin/idealyze` before tagging if the version number changed.

### Hotfix a stable release

If you need to patch stable without including everything on main:

```bash
# Branch from the current latest
git checkout -b hotfix/fix-name latest

# Fix, commit, test
git commit -m "fix: the thing"

# Tag and push
git tag -f latest
git push origin hotfix/fix-name latest --force

# Stamp version
git tag v0.2.1
git push origin v0.2.1

# Merge back to main
git checkout main
git merge hotfix/fix-name
git push
```

### Rollback stable

If a bad release gets tagged as `latest`:

```bash
# Point latest back to the previous good version
git tag -f latest v0.2.0
git push origin latest --force
```

## How the install script uses tags

The install script (`install.sh`) sets `BASE_URL` based on the channel:

```
https://raw.githubusercontent.com/diananerd/idealize/${CHANNEL}/...
```

Where `${CHANNEL}` is `latest` (default) or `beta` (if `--beta` flag passed). GitHub serves file contents at that tag's commit.

## Checklist for a release

1. All changes committed and pushed to `main`
2. `idealyze doctor` passes
3. E2E test: uninstall, install from GitHub, run all commands
4. Update `VERSION` in `bin/idealyze` if needed
5. Tag beta: `git tag -f beta && git push origin beta --force`
6. Test beta channel install
7. Tag stable: `git tag -f latest && git push origin latest --force`
8. Stamp version: `git tag v0.X.0 && git push origin v0.X.0`
