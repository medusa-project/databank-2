/**
 * Playwright global setup — seeds the test database with fixture data before
 * any spec runs.  Runs in RAILS_ENV=test via the already-started test server.
 *
 * Imports:
 *  1. Mini dataset bundle (2 released datasets for show/version page tests)
 *  2. Guides bundle (sections/items/subitems for public guides + CMS tests)
 */

const { execSync } = require("child_process");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const RAILS_ENV = "RAILS_ENV=test";
const RAKE = `${RAILS_ENV} bundle exec rake`;

function rake(task, env = {}) {
  const envStr = Object.entries(env)
    .map(([k, v]) => `${k}=${v}`)
    .join(" ");
  const cmd = `${envStr} ${RAKE} ${task}`.trim();
  console.log(`[global-setup] ${cmd}`);
  execSync(cmd, { cwd: ROOT, stdio: "inherit" });
}

function railsRunner(script) {
  const escaped = script.replace(/'/g, "'\\''");
  const cmd = `${RAILS_ENV} bundle exec rails runner '${escaped}'`;
  console.log("[global-setup] normalize guide rich text");
  execSync(cmd, { cwd: ROOT, stdio: "inherit" });
}

module.exports = async function globalSetup() {
  const datasetBundleDir = path.join(ROOT, "playwright", "fixtures", "datasets_mini_bundle");
  rake("migration:bundle:import", {
    BUNDLE: path.join(datasetBundleDir, "legacy_datasets.ndjson"),
    CHECKSUM: path.join(datasetBundleDir, "legacy_datasets.ndjson.sha256"),
    MANIFEST: path.join(datasetBundleDir, "manifest.json"),
    OVERWRITE: "true",
  });

  const guidesBundleDir = path.join(ROOT, "working", "guides_20260525T135940Z");
  rake("migration:guides:import_from_dir", {
    DIR: guidesBundleDir,
    REPLACE_ALL: "true",
  });

  railsRunner(`
    records = ActionText::RichText.where(record_type: ["Guide::Section", "Guide::Item", "Guide::Subitem"], name: "body")
    records.find_each do |rt|
      sanitized = Migration::GuidesHtmlSanitizer.sanitize_html(rt.body.to_s)
      next if sanitized == rt.body.to_s

      rt.update!(body: sanitized)
    end
  `);
};
