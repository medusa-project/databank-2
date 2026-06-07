# Local Pre-Push Checklist

Use this checklist before pushing a branch. It is ordered from fastest checks to slower checks.

## 1) CI parity checks (required)

These checks map directly to GitHub Actions and should pass before you push.

1. Ruby lint

```sh
bin/rubocop -f github
```

2. Rails security scan

```sh
bin/brakeman --no-pager
```

3. Gem vulnerability audit

```sh
bin/bundler-audit
```

4. JavaScript dependency audit

```sh
bin/importmap audit
```

Tip: run all CI parity checks via one command:

```sh
bin/ci
```

## 2) Local-only quality checks (recommended)

These are not currently required by GitHub Actions, but they are strongly recommended before opening or updating a PR.

1. Full backend test suite (RSpec)

```sh
bundle exec rspec
```

2. End-to-end browser tests (Playwright)

```sh
npm run test:e2e
```

3. Accessibility scan (axe + Playwright)

```sh
npm run test:e2e:a11y
```

Run strategy for Playwright checks:

- for thorough local validation, run only `npm run test:e2e`
- for quick accessibility-focused feedback, run only `npm run test:e2e:a11y`
- running both is mostly redundant unless you want a separate explicit accessibility pass/reporting step

## 3) Situational checks

Run when dependency files changed:

1. `bundle install`
2. `npm install`
3. Confirm `Gemfile.lock` and `package-lock.json` are updated intentionally.

Run when GitHub Actions or branch rules changed:

1. Verify `.github/workflows/ci.yml` parses cleanly.
2. Verify branch protection still requires PRs and required checks on `main`.

## 4) Final sanity checks

1. Confirm branch and staged changes

```sh
git status --short
git branch --show-current
```

2. Review the diff.
3. Confirm the branch target is correct.
4. Push only if the local checks above are clean.