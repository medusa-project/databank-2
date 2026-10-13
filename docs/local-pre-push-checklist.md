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

4. npm dependency audit (including development tooling)

```sh
npm audit
```

This is a local check; `bin/ci` currently audits importmap dependencies, not npm
dependencies.

Run strategy for Playwright checks:

- for thorough local validation, run only `npm run test:e2e`
- for quick accessibility-focused feedback, run only `npm run test:e2e:a11y`
- running both is mostly redundant unless you want a separate explicit accessibility pass/reporting step

Lighthouse and Lighthouse CI were removed because their dependency chains used
`extract-zip`, which has no patched release for the symlink archive extraction
vulnerabilities (including GHSA-7pqw-9j4j-h8q3). Their removal also eliminates the
vulnerable transitive `js-yaml` and `ip-address` dependencies. Playwright and axe
accessibility checks remain available; they do not replace Lighthouse's
performance, SEO, or best-practices audits.

RubyZip is constrained to the patched 3.4+ series for
GHSA-47m2-wp7j-p9vc. When updating it, verify metric ZIP exports with:

```sh
RAILS_ENV=test bundle exec rspec spec/models/metric_spec.rb spec/jobs/metric_refresh_job_spec.rb
```

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