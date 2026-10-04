# =====================================================================
# Clean the INR/USD exchange rate for the CPHS panel.
#
# Source: FRED series EXINUS (Board of Governors of the Federal Reserve
# System, release G.5), "Indian Rupees to One U.S. Dollar", monthly,
# AVERAGE of daily noon buying rates in New York, not seasonally adjusted.
# Transcribed to inr_usd_monthly_fred.csv (Jan-2013 .. Aug-2026, 164 months;
# two independent extractions were identical and the latest value matches
# the FRED series page).
#
# Why a separate script: the exchange rate is an input of its own, used
#   (a) by "Clean Brent price.py" to express the Brent price in RUPEES
#       month by month (INR price = USD price x INR/USD) before averaging
#       to the wave -- the oil shock India actually faces includes rupee
#       depreciation; and
#   (b) possibly as a control / shifter in its own right (rupee depreciation).
#
# Outputs (in DATA, like Clean inflation.py):
#   * exchange_rate_monthly.csv / .dta -- one row per month: month_date
#     (Stata %tm integer), year, month, ym, inr_per_usd. Read by the Brent script.
#   * exchange_rate_wave.csv / .dta    -- one row per CPHS wave: wave_no,
#     inr_per_usd (wave average) and inr_depreciation_wave (100*dln of the
#     wave-average rate, wave on wave; > 0 = rupee depreciation).
#     Merge key with the panel: wave_no.
# =====================================================================

import numpy as np
import pandas as pd
from pathlib import Path

# Project folder: CHANGE THIS LINE to the project folder on your computer
# (the folder that contains data/, tables/, figures/ and code/).
BASE = Path(r"C:\Users\HP\Documents\QMUL\Financial inclusion in India")
DATA = BASE / "data"
FX_FILE = DATA / "inr_usd_monthly_fred.csv"

# --- 1. Read the monthly series ---
fx = pd.read_csv(FX_FILE)                            # columns: month (YYYY-MM-01), inr_per_usd
fx["date"] = pd.to_datetime(fx["month"], format="%Y-%m-%d")
fx = fx.sort_values("date").reset_index(drop=True)

# --- 2. Input checks (the series was transcribed from FRED) ---
assert fx["date"].is_unique, "duplicated month"
# consecutive months, no gaps
gaps = (fx["date"].dt.year * 12 + fx["date"].dt.month).diff().dropna()
assert (gaps == 1).all(), "gap in the monthly series"
assert fx["inr_per_usd"].notna().all() and (fx["inr_per_usd"] > 0).all(), "missing or non-positive rate"
# plausibility: the rupee moves gradually; a month-on-month change above 10%
# would point to a typo (the largest in 2013-2026 is 6.2%, June 2013 taper tantrum)
mom = fx["inr_per_usd"].pct_change().abs() * 100
assert (mom.dropna() < 10).all(), f"implausible monthly jump in: {fx.loc[mom >= 10, 'month'].tolist()}"

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

# --- 4. Monthly output (input of the Brent script) ---
fx_m = add_time_keys(fx.drop(columns="month"))
fx_m = fx_m[["month_date", "year", "month", "ym", "inr_per_usd", "date"]]
fx_m.drop(columns="date").to_csv(DATA / "exchange_rate_monthly.csv", index=False)
fx_m[["month_date", "year", "month", "ym", "inr_per_usd"]].to_stata(
    DATA / "exchange_rate_monthly.dta", write_index=False, version=118,
    variable_labels={"month_date":  "Calendar month (Stata %tm integer)",
                     "year":        "Year",
                     "month":       "Month (1-12)",
                     "ym":          "Year-month YYYYMM",
                     "inr_per_usd": "INR per USD, monthly average of daily rates (FRED EXINUS)"})

# --- 5. Wave output: average over the months of each wave, then 4-month change ---
# Period average, as for the CPI (the rate of a 4-month wave is its mean);
# depreciation = wave-on-wave log change of the wave-average rate.
fx_w = (add_wave(fx_m)
        .groupby("wave_no", as_index=False)
        .agg(year=("year", "min"),
             inr_per_usd=("inr_per_usd", "mean"),
             n_months=("inr_per_usd", "size"))
        .sort_values("wave_no").reset_index(drop=True))
fx_w["inr_depreciation_wave"] = 100 * (np.log(fx_w["inr_per_usd"]) - np.log(fx_w["inr_per_usd"].shift(1)))
fx_w = fx_w[["wave_no", "year", "inr_per_usd", "inr_depreciation_wave", "n_months"]]

fx_w.to_csv(DATA / "exchange_rate_wave.csv", index=False)
fx_w[["wave_no", "inr_per_usd", "inr_depreciation_wave"]].to_stata(
    DATA / "exchange_rate_wave.dta", write_index=False, version=118,
    variable_labels={"wave_no":               "CPHS four-month wave (merge key with the panel)",
                     "inr_per_usd":           "INR per USD, wave average (FRED EXINUS)",
                     "inr_depreciation_wave": "Rupee depreciation, 4-month (100*dln of wave-avg rate)"})

# --- 6. Report ---
panel = fx_w[(fx_w["wave_no"] >= 1) & (fx_w["wave_no"] <= 36)]
print("MONTH exchange_rate_monthly.dta:", len(fx_m), "rows |",
      fx_m["date"].min().strftime("%Y-%m"), "->", fx_m["date"].max().strftime("%Y-%m"))
print("WAVE  exchange_rate_wave.dta   :", len(fx_w), "rows | waves",
      int(fx_w["wave_no"].min()), "->", int(fx_w["wave_no"].max()),
      "| n_months:", fx_w["n_months"].value_counts().to_dict(),
      "| panel waves 1-36 with depreciation:", int(panel["inr_depreciation_wave"].notna().sum()), "of 36")
print("\n[wave head]\n", fx_w.head(5).to_string(index=False))
print("\n[wave tail]\n", fx_w.tail(4).to_string(index=False))
