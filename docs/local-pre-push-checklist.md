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

1. Full backend test suite (RSpec) -- if coverage is reported below 80%, document reason

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

4. Chrome Lighthouse checks (performance, accessibility, best practices, SEO)

```sh
npm run lighthouse:local
```

Optional: clean old Lighthouse reports without running new audits

```sh
npm run lighthouse:clean
```

5. Lighthouse CI-style assertions (optional)

```sh
npm run lighthouse:ci
```

Run strategy for Playwright checks:

- for thorough local validation, run only `npm run test:e2e`
- for quick accessibility-focused feedback, run only `npm run test:e2e:a11y`
- running both is mostly redundant unless you want a separate explicit accessibility pass/reporting step

Run strategy for Lighthouse checks:

- run `npm run lighthouse:local` when Rails is running locally on `http://127.0.0.1:3000`
- `npm run lighthouse:local` automatically cleans old `*.report.html` and `*.report.json` files first
- local reports are written to `tmp/lighthouse/` as `home.report.*` and `contact.report.*`
- in root-based dev containers, the script already applies Chrome `--no-sandbox` for compatibility
- run `npm run lighthouse:ci` for threshold-based warnings using `lighthouserc.json`
- Lighthouse checks are complementary to Playwright a11y tests and catch performance + SEO + best-practice issues

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