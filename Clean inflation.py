# =====================================================================
# Clean the RBI CPI file (Handbook Table No. 19) into deflator/shift inputs
# for the CPHS panel.
#
# Source workbook has 5 sheets across 3 base periods; only the sheet
# "CPI - 2012=100 (All India)" is used because it alone spans the whole
# CPHS panel (2013-01 to 2025-12, monthly, no gaps) -- no base-splicing
# needed. Per Sushanta: keep the General Index and the Consumer Food
# Price Index. The survey is a 4-month wave, so the script writes only
# WAVE-level outputs (the monthly series are not used downstream):
#   * inflation_wave.dta      -- General Index, Rural & Urban, wave-average CPI.
#                                Deflates the CPHS flows (merge on wave_no + region_type).
#   * food_inflation_wave.dta -- Consumer Food Price Index, Combined / All-India:
#                                wave-average index + its 4-month growth (national
#                                food inflation), to feed the instrument's shift.
# =====================================================================

import numpy as np
import pandas as pd
from pathlib import Path

# Project folder: CHANGE THIS LINE to the project folder on your computer
# (the folder that contains data/, tables/, figures/ and code/).
BASE = Path(r"C:\Users\HP\Documents\QMUL\Financial inclusion in India")
DATA = BASE / "data"
CPI_FILE = DATA / "Consumer Price Index" / "RBIB Table No. 19 _ Consumer Price Index (Base 2010=100).xlsx"

SHEET = "CPI - 2012=100 (All India)"   # the only sheet that covers the panel
# Exact commodity labels to keep (verified against the sheet)
KEEP = {"A) General Index": "gen_index", "B) Consumer Food Price Index": "cfpi_index"}

# --- 1. Read the sheet raw (multi-row title/header block on top) ---
raw = pd.read_excel(CPI_FILE, sheet_name=SHEET, header=None, engine="openpyxl")

# Fixed column layout of this table:
#   1 Month ("DEC-2014"), 2 Commodity, 3 Provisional/Final,
#   4 Rural Index, 5 Rural Inflation, 6 Urban Index, 7 Urban Inflation,
#   8 Combined Index, 9 Combined Inflation.
# Data starts two rows below the "Commodity Description" header (row index 5).
long = raw.iloc[7:, [1, 2, 3, 4, 6, 8, 9]].copy()
long.columns = ["month", "commodity", "status", "rural_idx", "urban_idx", "combined_idx", "combined_infl"]
long = long[long["month"].notna()]

# --- 2. Keep only the two indices we need ---
long["commodity"] = long["commodity"].astype(str).str.strip()
long = long[long["commodity"].isin(KEEP)]

# --- 3. Parse the month and make the index columns numeric ---
long["date"] = pd.to_datetime(long["month"], format="%b-%Y", errors="coerce")
for c in ["rural_idx", "urban_idx", "combined_idx", "combined_infl"]:
    # "-" and any stray text become NaN
    long[c] = pd.to_numeric(long[c], errors="coerce")

# --- 4. Resolve Provisional vs Final: prefer Final, fall back to Provisional ---
# Each (month, commodity) appears twice; rank Final ahead of Provisional and
# keep the first, so all geographies come from the same chosen vintage.
long["rank"] = long["status"].astype(str).str.strip().map({"Final": 0, "Provisional": 1})
long = (long.sort_values(["commodity", "date", "rank"])
             .drop_duplicates(["commodity", "date"], keep="first"))

# --- 5. Helpers: monthly time keys and the CPHS 4-month wave ---
def add_time_keys(df):
    df = df.copy()
    df["year"]       = df["date"].dt.year
    df["month"]      = df["date"].dt.month
    df["ym"]         = df["year"] * 100 + df["month"]                 # YYYYMM, e.g. 201401
    df["month_date"] = (df["year"] - 1960) * 12 + (df["month"] - 1)   # Stata %tm integer
    return df

def add_wave(df):
    # CPHS four-month waves: Jan-Apr / May-Aug / Sep-Dec, 3 per year, wave 1 = 2014 Jan-Apr.
    # wave_no = (year-2014)*3 + ceil(month/4); verified against the panel's wave_no.
    # (2013 falls on wave_no <= 0 -- pre-panel, kept only so wave-1 growth is defined.)
    df = df.copy()
    df["wave_no"] = ((df["year"] - 2014) * 3 + np.ceil(df["month"] / 4)).astype(int)
    return df

# --- 6a. Build the monthly General Index, Rural & Urban (input to 6c) ---
gen = long[long["commodity"] == "A) General Index"]
defl = gen.melt(id_vars=["date"], value_vars=["rural_idx", "urban_idx"],
                var_name="region_type", value_name="gen_index")
defl["region_type"] = defl["region_type"].map({"rural_idx": "RURAL", "urban_idx": "URBAN"})
defl = add_time_keys(defl).sort_values(["date", "region_type"]).reset_index(drop=True)
defl = defl[["month_date", "year", "month", "ym", "region_type", "gen_index", "date"]]

# --- 6c. Wave-level deflator: CPI averaged over the 4 months of each wave ---
# Roxana: the survey runs every 4 months, so deflate wave-level flows with the
# wave-average CPI (period average is the national-accounts convention for flows).
# Merge key on the panel side is wave_no + region_type. Only keys + gen_index go
# into the .dta so the merge adds no colliding columns; the .csv keeps diagnostics.
defl_w = (add_wave(defl)
          .groupby(["wave_no", "region_type"], as_index=False)
          .agg(year=("year", "min"),
               gen_index=("gen_index", "mean"),
               n_months=("gen_index", "size")))
defl_w = defl_w[["wave_no", "year", "region_type", "gen_index", "n_months"]]

defl_w.to_csv(DATA / "inflation_wave.csv", index=False)
defl_w[["wave_no", "region_type", "gen_index"]].to_stata(
    DATA / "inflation_wave.dta", write_index=False, version=118,
    variable_labels={"wave_no":     "CPHS four-month wave (merge key with the panel)",
                     "region_type": "Rural / Urban (matches the CPHS panel)",
                     "gen_index":   "CPI General Index (2012=100), wave average, by region",
                     "n_months":    "months averaged into the wave (4, or fewer at the edges)"})

# --- 6b. Build the monthly Combined food CPI (input to 6d) ---
cfpi = long[long["commodity"] == "B) Consumer Food Price Index"]
shift = cfpi[["date", "combined_idx", "combined_infl"]].rename(
    columns={"combined_idx": "food_index_national", "combined_infl": "food_inflation_national"})
shift = add_time_keys(shift).sort_values("date").reset_index(drop=True)
shift = shift[["month_date", "year", "month", "ym",
               "food_index_national", "food_inflation_national", "date"]]

# --- 6d. Wave-level food inflation: index averaged per wave, then 4-month growth ---
# Wave-over-wave log growth of the wave-average food index = 4-month national food
# inflation, dimensionally matched to the outcome's wave-level change (D.).
food_w = (add_wave(shift)
          .groupby("wave_no", as_index=False)
          .agg(year=("year", "min"),
               food_index_national=("food_index_national", "mean"),
               n_months=("food_index_national", "size"))
          .sort_values("wave_no").reset_index(drop=True))
food_w["food_inflation_wave"] = 100 * (np.log(food_w["food_index_national"])
                                       - np.log(food_w["food_index_national"].shift(1)))
food_w = food_w[["wave_no", "year", "food_index_national", "food_inflation_wave", "n_months"]]

food_w.to_csv(DATA / "food_inflation_wave.csv", index=False)
food_w[["wave_no", "food_index_national", "food_inflation_wave"]].to_stata(
    DATA / "food_inflation_wave.dta", write_index=False, version=118,
    variable_labels={"wave_no":              "CPHS four-month wave",
                     "food_index_national":  "Food CPI, Combined/All-India (2012=100), wave average",
                     "food_inflation_wave":  "National food inflation, 4-month (100*dln of wave-avg index)",
                     "n_months":             "months averaged into the wave"})

# --- 7. Report ---
print("WAVE  inflation_wave.dta      :", len(defl_w), "rows |",
      "waves", int(defl_w["wave_no"].min()), "->", int(defl_w["wave_no"].max()),
      "| n_months:", defl_w["n_months"].value_counts().to_dict())
print("WAVE  food_inflation_wave.dta :", len(food_w), "rows |",
      "growth missing:", int(food_w["food_inflation_wave"].isna().sum()))
print("\n[deflator head]\n", defl.head(3).to_string(index=False))
print("\n[wave deflator head]\n", defl_w.head(4).to_string(index=False))
print("\n[wave food head]\n", food_w.head(4).to_string(index=False))