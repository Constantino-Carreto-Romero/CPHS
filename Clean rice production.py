# =====================================================================
# Clean the RBI rice production series into a wave-level SHIFT input for
# the CPHS panel (Design 2: aggregate district public-bank share x
# national macro shifter).
#
# Source: RBI Handbook of Statistics on the Indian Economy, "Agricultural
# production of foodgrains" (DBIE, dbie.rbihub.in/handbook/agricultural-
# production-foodgrains; Ministry of Agriculture & Farmers Welfare), shared
# by Sushanta. Transcribed from the DBIE table (no download button) into
# rice_production_rbi_handbook.csv: one row per AGRICULTURAL year (July-June),
# 2009-10 to 2025-26, in LAKH TONNES (1 lakh = 100,000). 2025-26 is likely an
# advance estimate and may be revised.
#
# Mapping the annual series to the CPHS 4-month waves (Jan-Apr / May-Aug /
# Sep-Dec): about 85% of Indian rice is kharif, harvested Oct-Dec, so the
# production of agricultural year Y/Y+1 is assigned to the three waves that
# FOLLOW that harvest:  Sep-Dec Y, Jan-Apr Y+1, May-Aug Y+1  (12 months).
# Each wave therefore belongs to exactly one agricultural year.
#
# Output rice_production_wave.dta (merge on wave_no, like food_inflation_wave):
#   rice_prod_lakh_t     production of the harvest year the wave belongs to
#   rice_growth          100*dln(production) vs the previous agricultural
#                        year, HELD for the 3 waves of the harvest year
#                        (persistent-shock version; baseline)
#   rice_growth_harvest  the same growth only in the harvest wave (Sep-Dec)
#                        and 0 in the other two (new-shock-per-wave version,
#                        closer to a wave-on-wave first-difference design)
# Which version to use is a design choice to confirm with Roxana.
# =====================================================================

import numpy as np
import pandas as pd
from pathlib import Path

# Project folder: CHANGE THIS LINE to the project folder on your computer
# (the folder that contains data/, tables/, figures/ and code/).
BASE = Path(r"C:\Users\HP\Documents\QMUL\Financial inclusion in India")
DATA = BASE / "data"
RICE_FILE = DATA / "rice_production_rbi_handbook.csv"

# --- 1. Read the transcribed table ---
raw = pd.read_csv(RICE_FILE)
raw = raw.sort_values("year_start").reset_index(drop=True)

# --- 2. Input checks (the table was transcribed by hand from DBIE) ---
# (a) one row per agricultural year, consecutive years, label consistent
assert raw["year_start"].is_unique, "duplicated agricultural year"
assert (raw["year_start"].diff().dropna() == 1).all(), "gap in the agricultural years"
lab = raw["year_start"].astype(str) + "-" + (raw["year_start"] + 1).astype(str).str[-2:]
assert (lab == raw["agri_year"]).all(), "agri_year label does not match year_start"
# (b) accounting identity of the source table: rice + wheat + coarse cereals =
# total cereals. A mistyped digit would break it; the source rounds older years
# to whole lakh tonnes, so a gap below 1 lakh tonne is rounding.
gap = (raw[["rice_lakh_t", "wheat_lakh_t", "coarse_cereals_lakh_t"]].sum(axis=1)
       - raw["total_cereals_lakh_t"]).abs()
assert (gap < 1).all(), f"identity broken (typo?) in: {raw.loc[gap >= 1, 'agri_year'].tolist()}"

# --- 3. Annual growth: 100 * dln(rice production) vs the previous agri year ---
ann = raw[["agri_year", "year_start", "rice_lakh_t"]].rename(columns={"rice_lakh_t": "rice_prod_lakh_t"})
ann["rice_growth"] = 100 * (np.log(ann["rice_prod_lakh_t"]) - np.log(ann["rice_prod_lakh_t"].shift(1)))

# --- 4. Expand each agricultural year to its 3 post-harvest waves ---
# wave_no = (year-2014)*3 + ceil(month/4), as in Clean inflation.py. For
# agricultural year Y/Y+1 (k = Y - 2014):
#   Sep-Dec Y    -> 3k + 3   (harvest wave)
#   Jan-Apr Y+1  -> 3k + 4
#   May-Aug Y+1  -> 3k + 5
# Waves <= 0 are pre-panel (kept, like the food file, so nothing is lost at the edges).
rows = []
for _, r in ann.iterrows():
    k = int(r["year_start"]) - 2014
    for j, wave_no in enumerate([3 * k + 3, 3 * k + 4, 3 * k + 5]):
        rows.append({"wave_no": wave_no,
                     "agri_year": r["agri_year"],
                     "wave_in_harvest_year": j + 1,                 # 1 = harvest wave (Sep-Dec)
                     "rice_prod_lakh_t": r["rice_prod_lakh_t"],
                     "rice_growth": r["rice_growth"],
                     # growth only in the harvest wave; 0 afterwards (NaN stays NaN)
                     "rice_growth_harvest": r["rice_growth"] if j == 0 else
                                            (0.0 if pd.notna(r["rice_growth"]) else np.nan)})
rice_w = pd.DataFrame(rows).sort_values("wave_no").reset_index(drop=True)
assert rice_w["wave_no"].is_unique, "a wave was assigned to two agricultural years"

# calendar months of each wave, for the diagnostic csv only
yr = 2014 + (rice_w["wave_no"] - 1) // 3
rice_w["wave_months"] = (rice_w["wave_no"] - 1) % 3
rice_w["wave_months"] = (rice_w["wave_months"].map({0: "Jan-Apr ", 1: "May-Aug ", 2: "Sep-Dec "})
                         + yr.astype(str))

# --- 5. Write: csv with diagnostics, dta with the merge key + shifters only ---
rice_w.to_csv(DATA / "rice_production_wave.csv", index=False)
rice_w[["wave_no", "rice_prod_lakh_t", "rice_growth", "rice_growth_harvest"]].to_stata(
    DATA / "rice_production_wave.dta", write_index=False, version=118,
    variable_labels={"wave_no":             "CPHS four-month wave (merge key with the panel)",
                     "rice_prod_lakh_t":    "Rice production, All-India, lakh tonnes (harvest year of the wave)",
                     "rice_growth":         "Rice production growth, 100*dln annual, held 3 waves",
                     "rice_growth_harvest": "Rice production growth, 100*dln annual, harvest wave only"})

# --- 6. Report ---
panel = rice_w[(rice_w["wave_no"] >= 1) & (rice_w["wave_no"] <= 36)]
print("rice_production_wave.dta:", len(rice_w), "rows | waves",
      int(rice_w["wave_no"].min()), "->", int(rice_w["wave_no"].max()),
      "| panel waves 1-36 covered:", len(panel), "of 36",
      "| growth missing in panel waves:", int(panel["rice_growth"].isna().sum()))
print("\n[annual growth]\n", ann.to_string(index=False))
print("\n[first panel waves]\n",
      panel.head(7)[["wave_no", "wave_months", "agri_year", "wave_in_harvest_year",
                     "rice_prod_lakh_t", "rice_growth", "rice_growth_harvest"]].to_string(index=False))
