# =====================================================================
# Clean the Brent crude oil price into wave-level SHIFT inputs for the
# CPHS panel (Design 2: aggregate district public-bank share x national
# macro shifter), in US DOLLARS and in RUPEES.
#
# Source: U.S. Energy Information Administration, "Europe Brent Spot Price
# FOB", dollars per barrel, monthly average (same series as FRED
# MCOILBRENTEU). Transcribed to brent_monthly_eia.csv (Jan-2013 .. Aug-2026,
# 164 months; two independent extractions were identical and the latest five
# months match FRED).
#
# RUN ORDER: "Clean exchange rate.py" FIRST -- this script reads its output
# exchange_rate_monthly.dta to convert the price to rupees.
#
# Rupee price: converted MONTH BY MONTH (INR/bbl = USD/bbl x INR per USD of
# the same month) and only then averaged to the wave, so the wave price is
# the average of what India paid each month. The rupee version captures the
# oil shock India actually faces (world price x rupee depreciation); the
# dollar version is the pure world-market shock (Roxana's "Brent oil
# inflation"). Both are kept.
#
# Output brent_price_wave.dta (merge on wave_no, like food_inflation_wave):
#   brent_usd_bbl, brent_inr_bbl        wave-average price
#   brent_usd_growth_wave               4-month Brent inflation in USD, 100*dln
#   brent_inr_growth_wave               4-month Brent inflation in INR, 100*dln
# (wave-on-wave log change of the wave-average price, as for food inflation)
# =====================================================================

import numpy as np
import pandas as pd
from pathlib import Path

# Project folder: CHANGE THIS LINE to the project folder on your computer
# (the folder that contains data/, tables/, figures/ and code/).
BASE = Path(r"C:\Users\HP\Documents\QMUL\Financial inclusion in India")
DATA = BASE / "data"
BRENT_FILE = DATA / "brent_monthly_eia.csv"
FX_FILE    = DATA / "exchange_rate_monthly.dta"     # from Clean exchange rate.py

# --- 1. Read the monthly Brent price ---
br = pd.read_csv(BRENT_FILE)                         # columns: month (YYYY-MM-01), brent_usd_bbl
br["date"] = pd.to_datetime(br["month"], format="%Y-%m-%d")
br = br.sort_values("date").reset_index(drop=True)

# --- 2. Input checks (the series was transcribed from EIA) ---
assert br["date"].is_unique, "duplicated month"
gaps = (br["date"].dt.year * 12 + br["date"].dt.month).diff().dropna()
assert (gaps == 1).all(), "gap in the monthly series"
assert br["brent_usd_bbl"].notna().all() and (br["brent_usd_bbl"] > 0).all(), "missing or non-positive price"
# plausibility: oil is volatile (Apr-2020 -43%, May-2020 +60%), so only a log
# change above 0.7 (about x2 or /2 in one month) is treated as a likely typo
dln = np.log(br["brent_usd_bbl"]).diff().abs()
assert (dln.dropna() < 0.7).all(), f"implausible monthly jump in: {br.loc[dln >= 0.7, 'month'].tolist()}"

# --- 3. Helpers: monthly time keys and the CPHS 4-month wave (as in Clean inflation.py) ---
def add_time_keys(df):
    df = df.copy()
    df["year"]       = df["date"].dt.year
    df["month"]      = df["date"].dt.month
    df["ym"]         = df["year"] * 100 + df["month"]                 # YYYYMM, e.g. 201401
    df["month_date"] = (df["year"] - 1960) * 12 + (df["month"] - 1)   # Stata %tm integer
    return df

def add_wave(df):
    # CPHS four-month waves: Jan-Apr / May-Aug / Sep-Dec, 3 per year, wave 1 = 2014 Jan-Apr.
    # wave_no = (year-2014)*3 + ceil(month/4). 2013 falls on wave_no <= 0 (pre-panel),
    # kept only so the wave-1 growth is defined.
    df = df.copy()
    df["wave_no"] = ((df["year"] - 2014) * 3 + np.ceil(df["month"] / 4)).astype(int)
    return df

# --- 4. Rupee price, month by month ---
br = add_time_keys(br.drop(columns="month"))
fx = pd.read_stata(FX_FILE)[["month_date", "inr_per_usd"]]
br = br.merge(fx, on="month_date", how="left", validate="one_to_one")
missing_fx = br.loc[br["inr_per_usd"].isna(), "ym"].tolist()
assert not missing_fx, f"no exchange rate for months {missing_fx} -- rerun Clean exchange rate.py"
br["brent_inr_bbl"] = br["brent_usd_bbl"] * br["inr_per_usd"]

# --- 5. Wave averages and 4-month growth (wave on wave, 100*dln) ---
brent_w = (add_wave(br)
           .groupby("wave_no", as_index=False)
           .agg(year=("year", "min"),
                brent_usd_bbl=("brent_usd_bbl", "mean"),
                brent_inr_bbl=("brent_inr_bbl", "mean"),
                n_months=("brent_usd_bbl", "size"))
           .sort_values("wave_no").reset_index(drop=True))
for cur in ["usd", "inr"]:
    p = brent_w[f"brent_{cur}_bbl"]
    brent_w[f"brent_{cur}_growth_wave"] = 100 * (np.log(p) - np.log(p.shift(1)))
brent_w = brent_w[["wave_no", "year", "brent_usd_bbl", "brent_inr_bbl",
                   "brent_usd_growth_wave", "brent_inr_growth_wave", "n_months"]]

# --- 6. Write: csv with diagnostics, dta with the merge key + shifters only ---
brent_w.to_csv(DATA / "brent_price_wave.csv", index=False)
brent_w[["wave_no", "brent_usd_bbl", "brent_inr_bbl",
         "brent_usd_growth_wave", "brent_inr_growth_wave"]].to_stata(
    DATA / "brent_price_wave.dta", write_index=False, version=118,
    variable_labels={"wave_no":               "CPHS four-month wave (merge key with the panel)",
                     "brent_usd_bbl":         "Brent crude, USD per barrel, wave average (EIA)",
                     "brent_inr_bbl":         "Brent crude, INR per barrel, wave average (monthly USD x INR/USD)",
                     "brent_usd_growth_wave": "Brent inflation in USD, 4-month (100*dln of wave-avg price)",
                     "brent_inr_growth_wave": "Brent inflation in INR, 4-month (100*dln of wave-avg price)"})

# --- 7. Report ---
panel = brent_w[(brent_w["wave_no"] >= 1) & (brent_w["wave_no"] <= 36)]
print("WAVE  brent_price_wave.dta:", len(brent_w), "rows | waves",
      int(brent_w["wave_no"].min()), "->", int(brent_w["wave_no"].max()),
      "| n_months:", brent_w["n_months"].value_counts().to_dict(),
      "| panel waves 1-36 with growth:", int(panel["brent_usd_growth_wave"].notna().sum()), "of 36")
print("Correlation USD vs INR growth (panel waves):",
      round(panel["brent_usd_growth_wave"].corr(panel["brent_inr_growth_wave"]), 3))
print("\n[wave head]\n", brent_w.head(6).round(3).to_string(index=False))
print("\n[wave tail]\n", brent_w.tail(4).round(3).to_string(index=False))
