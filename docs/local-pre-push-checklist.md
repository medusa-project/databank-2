# Local Pre-Push Checklist

Run this before pushing any branch to GitHub.

## Always run

1. `bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error`
2. `bundle exec rubocop`
3. `bundle exec rspec`
4. `bin/importmap audit`
5. `git status --short`

## Run when UI, navigation, or browser behavior changed

1. `npm run test:e2e`
2. `npm run test:e2e:a11y`

## Run when dependency files changed

1. `bundle install`
2. `npm install`
3. Confirm `Gemfile.lock` and `package-lock.json` are updated intentionally.

## Run when GitHub Actions or branch rules changed

1. Verify `.github/workflows/ci.yml` parses cleanly.
2. Verify branch protection still requires PRs and required checks on `main`.

## Final check before push

1. Review the diff.
2. Confirm the branch target is correct.
3. Push only if the local checks above are clean.