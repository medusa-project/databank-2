# Demo-First Capistrano Deploy Runbook

Use this flow to deploy one environment at a time, starting with demo.

## 1) Verify local deploy prerequisites

1. Confirm Capistrano tasks are available:

```sh
bundle exec cap -T
```

2. Confirm the target host is reachable via SSH key:

```sh
ssh -i ~/.ssh/medusa-2023.pem databank@databank-demo-rocky.library.illinois.edu "hostname"
```

## 2) Prepare secrets and linked files on demo host

Capistrano expects these linked files for demo:

- `config/credentials/demo.key`
- `nginx.conf.erb`

Create `~/shared/config/credentials/demo.key` on the demo host with the correct credentials key. Ensure `~/shared/nginx.conf.erb` exists if your host setup requires it.

## 3) Run deploy checks before first deploy

1. Capistrano checks:

```sh
bundle exec cap demo deploy:check
```

2. Preflight host checks (svc hooks + shared dirs):

```sh
bundle exec cap demo deploy:preflight
```

3. Runtime config contract checks (local):

```sh
RAILS_ENV=demo bundle exec rake config:contract_report
RAILS_ENV=demo bundle exec rake config:contract
```

For production deploy prep, run the same checks with `RAILS_ENV=production`.

The preflight task validates required executable hooks:

- `~/svc_hooks/shutdown`
- `~/svc_hooks/boot`

During deploy, Capistrano runs `deploy:config_contract` automatically before `assets:precompile`.

See [Deploy config contract](deploy-config-contract.md) for the full deploy configuration contract and source-of-truth guidance.

## 4) Deploy demo

```sh
bundle exec cap demo deploy
```

## 5) Post-deploy validation on demo

1. Confirm app process and restart behavior via your host service tooling.
2. Verify web access and key app flows.
3. Run smoke tests against demo.

After demo is stable, repeat the same process for production using `production` stage commands.
