# Illinois Data Bank integration with Shibboleth

reference: [University of Illinois Shibboleth](https://answers.illinois.edu/illinois/47660)

Production/demo use `omniauth-shibboleth` with header request mode from
`config/shibboleth.yml`. Development/test use OmniAuth `developer`.

The login flow matches legacy databank behavior:

- `/login` redirects to `/Shibboleth.sso/Login?...` outside development/test.
- `/auth/:provider/callback` accepts `shibboleth` and `developer` providers.
- `developer` callback is blocked outside development/test.

## Implementation overview

Shibboleth integration in databank-2 is implemented by:

- `omniauth-shibboleth` provider setup in `config/initializers/omniauth.rb`
- environment-specific Shibboleth mapping in `config/shibboleth.yml`
- login/callback handling in `SessionsController`
- user creation/update and role mapping in `User.from_omniauth`

At app boot, the initializer loads environment options from `config/shibboleth.yml` and sets:

- production/demo: OmniAuth provider `:shibboleth`
- development/test: OmniAuth provider `:developer`
- request methods: `GET` and `POST`
- app-level host used by `/login` redirect target (`Databank2::Application.shibboleth_host`)

## Required configuration

The file `config/shibboleth.yml` is the source of truth for Shibboleth provider mapping.

Expected keys per environment:

- `host`: externally reachable app host used in Shibboleth callback target
- `uid_field`: unique identity field used as OmniAuth UID (`eppn`)
- `request_type`: set to `header`
- `info_fields.name`: mapped from `displayName`
- `info_fields.email`: mapped from `mail`
- `extra_fields`: list of raw attributes forwarded to the app

Current Illinois Data Bank mapping includes these `extra_fields`:

- `eppn`
- `unscoped-affiliation`
- `uid`
- `sn`
- `nickname`
- `mail`
- `givenName`
- `displayName`
- `iTrustAffiliation`
- `uiucEduStudentLevelCode`

The two role-related attributes (`iTrustAffiliation` and `uiucEduStudentLevelCode`) are required for legacy-compatible default role assignment.

## Role mapping behavior (legacy parity)

For `shibboleth` provider logins, `User.user_role` derives role from Shibboleth attributes:

- if `iTrustAffiliation` includes `staff` -> `depositor`
- if `iTrustAffiliation` includes `student` and `uiucEduStudentLevelCode == "1U"` -> `no_deposit`
- if `iTrustAffiliation` includes `student` and level is not `1U` -> `depositor`
- all other/missing/error states -> `no_deposit`

After login, users with `no_deposit` who do not have an entry in `ManagedDepositException` are allowed to authenticate but are shown the not-eligible-to-deposit notice.

## Request flow

### 1) Start login

- Route: `GET /login`
- In production/demo:
	- stores referrer in session (`login_return_referer`)
	- redirects to `/Shibboleth.sso/Login?target=https://<host>/auth/shibboleth/callback`
- In development/test:
	- does not force external Shibboleth redirect

### 2) Callback

- Route: `POST /auth/:provider/callback`
- Allowed providers: `shibboleth`, `developer`
- `developer` is rejected outside development/test
- Missing/invalid auth payload redirects to root with failure notice

### 3) Session establish

- `User.from_omniauth(auth)` creates or updates local user
- `session[:user_id]` is set on success
- redirect target preference:
	- `session[:login_return_uri]`
	- then `session[:login_return_referer]`
	- then root

## Development and test usage

Development and test environments use OmniAuth `developer` with fields:

- `email`
- `name`
- `role`

Common local login path for request specs and manual testing:

- `POST /auth/developer/callback`

Example request-spec payload:

```ruby
post "/auth/developer/callback", params: {
	name: "Net Id",
	email: "netid@example.edu",
	role: "depositor"
}
```

## Operational troubleshooting

- Symptom: redirected to root with authentication failure notice.
	- Confirm callback route is receiving `omniauth.auth` payload.
	- Confirm provider is `shibboleth` or `developer`.
	- Confirm `developer` provider is only used in development/test.
- Symptom: user unexpectedly gets `no_deposit` role.
	- Verify IdP releases `iTrustAffiliation` and `uiucEduStudentLevelCode`.
	- Check value format (`iTrustAffiliation` must be semicolon-delimited).
- Symptom: Shibboleth redirect target is wrong host.
	- Verify `host` in `config/shibboleth.yml` for active environment.
- Symptom: login succeeds but user still cannot deposit.
	- Verify `ManagedDepositException` entry for the user email when policy override is intended.

## Security and deployment notes

- `config/shibboleth.yml` is environment configuration, not credential material.
- Trust boundary is the front-end web server / Shibboleth SP that populates headers.
- Keep production/demo `host` aligned with externally reachable canonical domain so callback URLs remain valid.

