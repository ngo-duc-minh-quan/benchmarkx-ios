# AGENTS.md

## Expo

Read the exact versioned docs at https://docs.expo.dev/versions/v56.0.0/ before writing any Expo code.

---

## Git Flow

This project follows Atlassian Gitflow. Full rules: `git-flow.md`.

### Branch Structure

| Branch | Purpose | From | Merge to |
|--------|---------|------|----------|
| `main` | Released code only | — | — |
| `develop` | Integration branch | — | — |
| `feature/#<issue>_<desc>` | Features / tasks | `develop` | `develop` |
| `bugfix/#<issue>_<desc>` | Dev-time bug fixes | `develop` | `develop` |
| `release/<version>` | Version cut | `develop` | `main` + `develop` |
| `hotfix/<version>_<desc>` | Urgent prod fix | `main` | `main` + `develop` |

**Branch naming:**
- Lowercase, hyphens between words, underscore to separate segments
- Always include issue ID: `feature/#123_add-gpu-benchmark`
- Forbidden: `temp`, `test`, `wip`, `new-branch`, accented Vietnamese characters

### Commit Format

```
<type>: <short description>
```

| Type | Use when |
|------|----------|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code restructure, no behavior change |
| `docs` | Documentation only |
| `test` | Tests only |
| `chore` | Build, config, dependencies |

**Before every commit:**
- Self-review the diff as a reviewer would
- Remove all: dead code, debug logs (`console.log`), stale comments
- One commit = one clear purpose; never mix unrelated changes
- Never use: `wip`, `update`, `fix bug`, `change something`

### Pull Request

**Title:** `[#<issue>] <short description>`

**Description must include:**
1. Issue/task reference
2. Goal — what changed and why
3. Screenshot evidence (UI changes require before/after)
4. Risk/impact notes (what could break, what others must do after merge)
5. Post-merge steps (migrations, env vars, config changes)

**Merge checklist:**
- [ ] Branch type correct (`feature/`, `bugfix/`, etc.)
- [ ] Commit messages are descriptive (Conventional Commits)
- [ ] PR description complete (all 5 sections above)
- [ ] Local build passes, main flow tested
- [ ] No side effects on other branches
- [ ] Version / changelog updated if needed
- [ ] Merge target is correct (`develop` or `main`)
- [ ] All reviewer + bot comments resolved
- [ ] At least 1 reviewer approved

**Merge strategy:** Prefer `squash merge` for `feature/*` branches.

### Version Tags

- `v0.1.1_stg` — Testflight / staging environment
- `v1.0.0_prod` — AppStore / production release

### Agent Rules (What Agent Must NOT Do)

- **Never** commit directly to `main` or `develop`
- **Never** open a `feature/*` branch from `main`
- **Never** add new features to `release/*` or `hotfix/*`
- **Never** force push to shared branches (`main`, `develop`, `release/*`)
- **Never** self-resolve another person's review comments
- **Never** merge a PR without build passing and minimum test confirmed
- **Never** combine multiple unrelated tasks into one commit or one PR
