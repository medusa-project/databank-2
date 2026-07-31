# External Files + Download Metrics QA Checklist

Scope: manual role-based validation for the external-files and download-metrics interface changes.

## Preconditions

- Local app server is running.
- Seed or fixture data includes at least one published dataset and one draft dataset.
- At least one dataset has external files metadata:
  - external_files_link present
  - external_files_note present

## Roles

- Public (not signed in)
- Depositor
- Curator
- Admin

## External Files: Dataset Show

1. Public user opens a released dataset with external files metadata.

- Expected:
  - Files section is visible.
  - External files panel is visible.
  - Access All Files action is visible.

2. Depositor opens own dataset with external files metadata.

- Expected:
  - External files panel is visible on dataset show.
  - Access All Files action is visible when link exists.

3. Admin opens dataset edit form and updates external files note/link.

- Expected:
  - Curator/admin-only fields are visible.
  - Save succeeds.
  - Dataset show reflects updated note/link.

4. Open external files action (open_in_granite) on dataset with link.

- Expected:
  - Redirect opens external link.
  - No authorization error for allowed roles.

5. Open external files action on dataset with missing link.

- Expected:
  - User is returned to dataset show.
  - Clear alert indicates missing external files link.

## Search Facet: External Files

1. Admin opens datasets index.

- Expected:
  - External Files facet is visible.
  - Has External Files and No External Files options appear when counts are non-zero.

2. Depositor opens datasets index.

- Expected:
  - External Files facet is not shown.

3. Admin applies Has External Files filter.

- Expected:
  - Results include datasets with external files metadata.
  - Results exclude datasets without external files metadata.

4. Admin applies No External Files filter.

- Expected:
  - Results include datasets without external files metadata.
  - Results exclude datasets with external files metadata.

## Curator/Admin Metrics

1. Curator opens Curator Metrics page.

- Expected:
  - Download Metrics Summary table is visible.
  - Download Metrics Details link is visible.

2. Curator opens Download Metrics detail page.

- Expected:
  - Current Snapshot section is visible.
  - Calendar Year Totals table is visible.
  - Fiscal Year Totals table is visible.
  - JSON links are visible.

3. Depositor opens download metrics detail route directly.

- Expected:
  - Access denied and redirected to metrics dashboard.

4. Curator requests JSON breakdown endpoint.

- Expected:
  - Response is JSON.
  - Includes summary, calendar_years, fiscal_years, generated_at.

5. Validate visibility filtering in metrics output.

- Expected:
  - Totals include currently file-public datasets only.
  - Non-file-public datasets are excluded.

## Accessibility Spot Checks

1. Keyboard-only navigation on:

- Dataset show external-files panel.
- Curator Metrics page.
- Download Metrics detail page.

2. Expected:

- Focus indicator visible on all interactive controls.
- Access All Files and metrics links are reachable and have descriptive names.
- Heading order is logical and landmarks are present.

## Sign-off

- Date:
- Tester:
- Environment:
- Result: Pass / Needs follow-up
- Notes:
