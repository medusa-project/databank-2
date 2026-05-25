/**
 * Known fixture keys seeded by playwright/global-setup.js.
 * Import these in specs instead of hardcoding IDs.
 */

/** Released datasets imported from playwright/fixtures/datasets_mini_bundle */
const DATASETS = {
  /** Phylogenetic Analysis of the NRPS AmbE Condensation Domains */
  RELEASED_A: "IDB-4602893",
  /** New York City Taxi Trip Data (2010-2013) */
  RELEASED_B: "IDB-9610843",
};

/** Guides bundle imported from working/guides_20260525T135940Z */
const GUIDES = {
  /** All sections/items/subitems from the sample guides bundle are present */
  SEEDED: true,
};

module.exports = { DATASETS, GUIDES };
