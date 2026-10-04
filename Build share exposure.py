# =====================================================================
# Build the Design-3 district exposure from the ORIGINAL bank shares.
#
# Design 3 (Roxana's instruction, 2026-09-29): interact the original 2013
# bank-level shares s_bd with the NATIONAL shifters g_t (food inflation,
# rice production, Brent, ...). The shift-share (Bartik) instrument is the
# sum over banks of share x shift:
#       z_dt = sum_b s_bd * g_t
# Because a national shifter is the same for every bank, this equals
#       z_dt = (sum_b s_bd) * g_t = bank_share_sum_d * g_t
# so the instrument only needs ONE number per district: bank_share_sum_d.
# This script builds it; Merge_CHPS_and_shares.py attaches it to the panel and the
# estimation do-file multiplies it by each shifter.
#
# Input  (from branches per district.R, Delhi in CMIE clusters):
#   tables/shares_cmie.xlsx             pc11_state_id, pc11_district_id,
#                                       rbi_bank_grp, branches, share_2013
#     share_2013 = s_bd = bank b's 2013 branches in district d / bank b's
#     2013 branches in the STATE (within-state denominator; public banks:
#     SBI group, nationalised banks, RRBs). Sums to 1 over districts within
#     each bank-state.
#   tables/public_share_cmie_2013.xlsx  used only as the list of districts
#     that had branches in 2013 (universe of the exposure).
# Output:
#   tables/bank_share_sum_cmie_2013.xlsx / .csv   pc11_state_id,
#     pc11_district_id, bank_share_sum, n_banks
#   A district with branches but no public-bank branch gets 0.
# =====================================================================

from pathlib import Path
import numpy as np
import pandas as pd

# Project folder: CHANGE THIS LINE to the project folder on your computer
# (the folder that contains data/, tables/, figures/ and code/).
BASE   = Path(r"C:\Users\HP\Documents\QMUL\Financial inclusion in India")
TABLES = BASE / "tables"
SHARES = TABLES / "shares_cmie.xlsx"
PS     = TABLES / "public_share_cmie_2013.xlsx"
OUT    = TABLES / "bank_share_sum_cmie_2013.xlsx"

def _log(m): print(f"[exposure] {m}")

# --- 1. Read the original bank shares ---
sh = pd.read_excel(SHARES, dtype={"pc11_state_id": str, "pc11_district_id": str})
need = {"pc11_state_id", "pc11_district_id", "rbi_bank_grp", "share_2013"}
missing_cols = need - set(sh.columns)
assert not missing_cols, f"shares_cmie.xlsx lacks columns {missing_cols}"
# same key formatting as in Merge_CHPS_and_shares.py (Excel can strip leading zeros);
# Delhi clusters (DL_NNW / DL_NE / DL_SSW) are text and stay as they are
sh["pc11_state_id"] = sh["pc11_state_id"].str.strip().str.zfill(2)
sh["pc11_district_id"] = sh["pc11_district_id"].str.strip()
is_code = sh["pc11_district_id"].str.isdigit()
sh.loc[is_code, "pc11_district_id"] = sh.loc[is_code, "pc11_district_id"].str.zfill(3)

# --- 2. Input checks ---
assert sh["share_2013"].between(0, 1).all(), "a share_2013 outside [0, 1]"
dup = sh.duplicated(["pc11_state_id", "pc11_district_id", "rbi_bank_grp"]).sum()
assert dup == 0, f"{dup} duplicated district x bank rows"
# within-state denominator: shares must sum to 1 over districts in each bank-state
tot = sh.groupby(["pc11_state_id", "rbi_bank_grp"])["share_2013"].sum()
bad = tot[(tot - 1).abs() > 1e-6]
assert bad.empty, f"shares do not sum to 1 within bank-state:\n{bad.head(10)}"
_log(f"shares_cmie: {len(sh):,} district x bank rows | {sh['rbi_bank_grp'].nunique()} banks | "
     f"{sh[['pc11_state_id','pc11_district_id']].drop_duplicates().shape[0]} districts | "
     f"sums to 1 in all {len(tot)} bank-states")

# --- 3. Design-3 exposure: sum over banks of s_bd, per district ---
expo = (sh.groupby(["pc11_state_id", "pc11_district_id"], as_index=False)
          .agg(bank_share_sum=("share_2013", "sum"),
               n_banks=("rbi_bank_grp", "nunique")))

# --- 4. Universe = districts with any branch in 2013 (public_share file);
#        districts with branches but no public bank get exposure 0 ---
ps = pd.read_excel(PS, dtype={"pc11_state_id": str, "pc11_district_id": str})
univ = ps[["pc11_state_id", "pc11_district_id"]].drop_duplicates()
expo = univ.merge(expo, on=["pc11_state_id", "pc11_district_id"], how="outer", indicator=True)
only_sh = expo[expo["_merge"] == "right_only"]
if len(only_sh):
    _log(f"WARNING: {len(only_sh)} districts in shares_cmie but not in public_share_cmie "
         f"(kept): {only_sh[['pc11_state_id','pc11_district_id']].values.tolist()[:10]}")
n_zero = int((expo["_merge"] == "left_only").sum())
expo["bank_share_sum"] = expo["bank_share_sum"].fillna(0.0)
expo["n_banks"] = expo["n_banks"].fillna(0).astype(int)
expo = expo.drop(columns="_merge").sort_values(["pc11_state_id", "pc11_district_id"]).reset_index(drop=True)
_log(f"districts: {len(expo)} | with no public-bank branch (exposure 0): {n_zero}")

# --- 5. Write ---
expo.to_excel(OUT, index=False)
expo.to_csv(OUT.with_suffix(".csv"), index=False)
d = expo["bank_share_sum"]
_log(f"bank_share_sum: min {d.min():.3f} | p25 {d.quantile(.25):.3f} | median {d.median():.3f} | "
     f"p75 {d.quantile(.75):.3f} | max {d.max():.3f} | mean {d.mean():.3f}")
_log(f"Delhi clusters: {expo[expo['pc11_state_id'] == '07'][['pc11_district_id','bank_share_sum']].values.tolist()}")
_log(f"saved -> {OUT}")
