# =====================================================================
# Script 2 -- Merge the CPHS panel with the shift-share inputs (memory-safe).
#
# Builds the household-WAVE analysis base for the Design-2 estimation
# (aggregate district public-bank share x national food-inflation shift):
#   1. collapse the monthly CPHS panel to one row per household-wave, reading
#      the .dta in CHUNKS so the full 24M rows never sit in RAM at once
#      (MEAN over non-missing months for the flows, first non-missing value
#      for the wave-constant vars),
#   1b. (2026-09-29) attach the household-WAVE file written by
#      load_parquet_selected.do (Aspirational India, People of India, CMIE
#      groups, household-head variables and the any_*/n_* member aggregates),
#   2. attach the district exposure via the CPHS->PC11 crosswalk merge_key
#      (Design 2: public_share; Design 3, 2026-09-29: bank_share_sum),
#   3. attach the wave deflator (by region), the national food shift and
#      (2026-09-29) the national rice-production, Brent (USD and INR) and
#      exchange-rate shifts,
#   4. deflate the monetary flows to constant (2012=100) terms.
# The D. differencing, xtset and regressions stay in Stata.
# =====================================================================

from pathlib import Path
import numpy as np
import pandas as pd
import io                   # in-memory .dta writes to measure the sample's file size
import gc                   # free memory before writing the base (2026-09-29)

# Project folder: CHANGE THIS LINE to the project folder on your computer
# (the folder that contains data/, tables/, figures/ and code/).
BASE   = Path(r"C:\Users\HP\Documents\QMUL\Financial inclusion in India")
DATA   = BASE / "data"
TABLES = BASE / "tables"

PANEL  = DATA / "CPHS" / "selected_cphs_panel_data.dta"    # household-MONTH (flows)
WAVEF  = DATA / "CPHS" / "selected_cphs_wave_data.dta"     # household-WAVE (2026-09-29)
XW     = TABLES / "CPHS to PC11 crosswalk.xlsx"
PS     = TABLES / "public_share_cmie_2013.xlsx"
PS3    = TABLES / "bank_share_sum_cmie_2013.xlsx"   # Design-3 exposure, from Build share exposure.py (2026-09-29)
INFL   = DATA / "inflation_wave.dta"
FOOD   = DATA / "food_inflation_wave.dta"
RICE   = DATA / "rice_production_wave.dta"   # from Clean rice production.py (2026-09-29)
BRENT  = DATA / "brent_price_wave.dta"       # from Clean Brent price.py (2026-09-29)
FXW    = DATA / "exchange_rate_wave.dta"     # from Clean exchange rate.py (2026-09-29)
OUT    = DATA / "cphs_wave_merged.dta"

CHUNK  = 2_000_000          # rows per chunk; lower it if RAM is tight
KEYS   = ["hh_id", "wave_no"]
DROP   = ["month_date"]     # monthly, meaningless at the wave level
# Monetary flows measured monthly (Rs/month) -> collapse to the wave by MEAN,
# then deflate. minc_all1 = income of the household HEAD (member slot 1), a
# monthly flow (confirmed 2026-09-29 from the build). New flows added 2026-09-29.
FLOW_VARS = ["tot_inc", "tot_exp", "minc_all1",
             "inc_of_all_mems_frm_wages", "inc_of_hh_frm_pvt_trf",
             "inc_of_hh_frm_biz_profit", "inc_of_hh_frm_self_prodn",
             "inc_of_hh_frm_govt_trf", "inc_of_all_mems_frm_interest",
             "m_exp_food", "m_exp_all_emis", "m_exp_health", "m_exp_edu",
             "m_exp_remittances_sent"]
DEFLATE_VARS = list(FLOW_VARS)        # every flow is deflated -> r_<name>
WAVE_CHUNK   = 1_000_000              # rows per chunk when reading the wave file
# CMIE special codes (2026-09-29): numeric fields use -99 ("data not available")
# and -100 ("not applicable"). The test build showed -99 in ~12.5% of the
# monthly rows of EVERY money flow, so they must be set to missing BEFORE the
# wave mean (otherwise -99 is averaged in as if it were rupees). Only these
# two exact codes are recoded; other negative values are kept (none observed).
CMIE_CODES = [-99, -100]
# asset counts in the household-wave file: counts cannot be negative, so any
# negative value is a CMIE code -> missing
COUNT_VARS = ["two_wheelers_owned", "refrigerators_owned", "cattle_owned", "tractors_owned"]

def _log(m): print(f"[merge] {m}")

# --- 0. Value-label metadata (read the label section only, not the 24M rows) --
_meta = pd.io.stata.StataReader(PANEL, convert_categoricals=False)
VAL_LABELS = _meta.value_labels()                                  # {labelset: {code: label}}
_vars = getattr(_meta, "_varlist", None) or getattr(_meta, "varlist", None)
_lbls = getattr(_meta, "_lbllist", None) or getattr(_meta, "lbllist", None)
COL2LBL = {c: l for c, l in zip(_vars, _lbls) if l}                # {col: labelset}
_log(f"labelled columns: {list(COL2LBL)}")

# --- 1. Collapse the monthly panel to household-wave, reading in chunks -------
# Flows: accumulate per-group SUM and non-missing COUNT so the mean skips NaN
# exactly like a one-pass groupby.mean(). Wave-constant vars: take the first
# NON-missing value, which may land in a later chunk, so per-chunk firsts are
# concatenated and reduced once at the end (chunk order = row order).
# Categoricals are read as raw integer CODES (convert_categoricals=False) so
# their coding is identical across chunks; labels are re-attached afterwards.
sum_acc = cnt_acc = None
first_parts = []
first_vars = None
n_rows = 0
n_codes = pd.Series(0, index=FLOW_VARS, dtype="int64")         # recoded CMIE codes per flow

for chunk in pd.read_stata(PANEL, chunksize=CHUNK, convert_categoricals=False):
    n_rows += len(chunk)
    # CMIE -99 / -100 -> NaN in the money flows, before summing (2026-09-29)
    is_code = chunk[FLOW_VARS].isin(CMIE_CODES)
    n_codes += is_code.sum()
    chunk[FLOW_VARS] = chunk[FLOW_VARS].mask(is_code)
    if first_vars is None:
        first_vars = [c for c in chunk.columns if c not in KEYS + FLOW_VARS + DROP]
    g = chunk.groupby(KEYS, observed=True)
    s = g[FLOW_VARS].sum()
    c = g[FLOW_VARS].count()                              # NON-missing count per flow
    sum_acc = s if sum_acc is None else sum_acc.add(s, fill_value=0)
    cnt_acc = c if cnt_acc is None else cnt_acc.add(c, fill_value=0)
    first_parts.append(g[first_vars].first().reset_index())   # first non-NA within the chunk

_log(f"panel rows read (monthly): {n_rows:,}")
_log("CMIE codes -99/-100 set to missing in the monthly flows (rows): "
     + ", ".join(f"{v}={int(n):,}" for v, n in n_codes.items()))
wave = (pd.concat(first_parts, ignore_index=True)
          .groupby(KEYS, observed=True).first())                # first non-NA across chunks (MultiIndex)
del first_parts
means = sum_acc.div(cnt_acc.replace(0, np.nan))                  # mean over non-missing months
wave = wave.join(means).reset_index()                           # add flows, then flatten keys
# MEMORY (2026-09-29): the accumulators hold 3 x 14 float64 columns over all
# household-waves (~2 GB on the full panel) and the last chunk is still in
# RAM; none is needed after the join, so release them before the merges.
del sum_acc, cnt_acc, means, chunk, g, s, c, is_code
gc.collect()
_log(f"household-wave rows: {len(wave):,} (avg {n_rows/max(len(wave),1):.2f} months/obs)")

# Re-attach value labels: rebuild each coded column as the same categorical the
# one-pass read would have produced (code -1 = missing).
for c, l in COL2LBL.items():
    if c in wave.columns:
        cats = [VAL_LABELS[l][k] for k in sorted(VAL_LABELS[l])]   # ordered by code 0,1,...
        wave[c] = pd.Categorical.from_codes(wave[c].fillna(-1).astype("int64"), categories=cats)

# --- 1b. Attach the household-WAVE file (2026-09-29) -------------------------
# One row per hh_id x wave_no (enforced by -isid- in the Stata load). Its text
# variables were encoded to labelled numbers in Stata (codes 1..K) and its
# yes/no flags carry the "yesno" label (0/1). Read the raw CODES in chunks
# (convert_categoricals=False: identical coding in every chunk), then map each
# code to its label ONCE, as a memory-light pandas categorical. Mapping by
# code (not by position) is required because -encode- starts at 1.
_wmeta = pd.io.stata.StataReader(WAVEF, convert_categoricals=False)
W_VAL_LABELS = _wmeta.value_labels()                                 # {labelset: {code: label}}
_wv  = getattr(_wmeta, "_varlist", None) or getattr(_wmeta, "varlist", None)
_wl  = getattr(_wmeta, "_lbllist", None) or getattr(_wmeta, "lbllist", None)
W_COL2LBL = {c: l for c, l in zip(_wv, _wl) if l}                   # {col: labelset}
wv = pd.concat(pd.read_stata(WAVEF, chunksize=WAVE_CHUNK, convert_categoricals=False),
               ignore_index=True)
for c, l in W_COL2LBL.items():
    lab = W_VAL_LABELS[l]
    unlabelled = set(wv[c].dropna().unique()) - set(lab)
    if unlabelled:
        raise ValueError(f"{WAVEF.name}: {c} has codes without a label: {sorted(unlabelled)[:10]}")
    wv[c] = pd.Categorical(wv[c].map(lab), categories=[lab[k] for k in sorted(lab)])
for c in COUNT_VARS:                                         # negative counts = CMIE codes
    if c in wv.columns:
        neg = wv[c] < 0
        _log(f"  {c}: {int(neg.sum()):,} negative CMIE codes set to missing")
        wv.loc[neg, c] = np.nan
dup = int(wv.duplicated(KEYS).sum())
if dup:
    raise ValueError(f"{WAVEF.name}: {dup} duplicated (hh_id, wave_no) rows -- expected one per household-wave")
clash = [c for c in wv.columns if c in wave.columns and c not in KEYS]
if clash:
    raise ValueError(f"columns present in BOTH files, would be duplicated: {clash}")
wave = wave.merge(wv, on=KEYS, how="left", validate="one_to_one", indicator="_m_wv")
_log(f"-> household-wave file: {wave['_m_wv'].value_counts().to_dict()} "
     f"({wv.shape[1] - len(KEYS)} variables added)")
wave = wave.drop(columns="_m_wv")
del wv

# --- 2. Attach the district exposure via the crosswalk -----------------------
xw = pd.read_excel(XW, sheet_name="Crosswalk", dtype=str)

# INPUT VALIDATION ONLY (the fix itself belongs in the crosswalk builder):
# every resolved row must carry a PC11 state code. If Delhi (or any state)
# comes through as NaN, the crosswalk builder needs fixing -- do NOT patch here.
bad_sc = xw[xw["PC11 state code"].isna()]
if len(bad_sc):
    _log(f"WARNING: {len(bad_sc)} crosswalk rows have NaN 'PC11 state code' "
         f"(states: {sorted(bad_sc['CPHS state'].dropna().unique())}). "
         f"Fix this in the CROSSWALK BUILDER, not here -- those rows will not "
         f"merge to an exposure below.")

xw_keys = (xw[["CPHS state", "CPHS district", "PC11 state code", "merge_key"]]
             .rename(columns={"PC11 state code": "pc11_state_id"}))  # Stata-safe name
wave = wave.merge(xw_keys, left_on=["state", "district"],
                  right_on=["CPHS state", "CPHS district"],
                  how="left", indicator="_m_xw")
_log(f"panel -> crosswalk: {wave['_m_xw'].value_counts().to_dict()}")
miss = wave.loc[wave["_m_xw"] == "left_only", ["state", "district"]].drop_duplicates()
if len(miss):
    _log(f"  {len(miss)} (state,district) pairs with NO crosswalk row:")
    print(miss.to_string(index=False))
wave = wave.drop(columns=["CPHS state", "CPHS district", "_m_xw"])

# --- 3. Attach the aggregate public-bank share (Design-2 exposure) -----------
ps = pd.read_excel(PS, dtype={"pc11_state_id": str, "pc11_district_id": str})
wave = wave.merge(ps, left_on=["pc11_state_id", "merge_key"],
                  right_on=["pc11_state_id", "pc11_district_id"],
                  how="left", indicator="_m_ps")
_log(f"-> public_share_cmie: {wave['_m_ps'].value_counts().to_dict()}")
no_exp = wave.loc[(wave["_m_ps"] == "left_only") & wave["merge_key"].notna(),
                  ["state", "district", "merge_key"]].drop_duplicates()
if len(no_exp):
    _log(f"  {len(no_exp)} matched districts with NO exposure (no 2013 branches?):")
    print(no_exp.head(20).to_string(index=False))
wave = wave.drop(columns=["pc11_district_id", "_m_ps"])   # keep our pc11_state_id

# --- 3b. Design-3 exposure (2026-09-29): sum over banks of the ORIGINAL 2013
# bank shares s_bd in the district, bank_share_sum. With a national shifter g_t
# the Bartik instrument sum_b s_bd*g_t = bank_share_sum*g_t (built in Stata).
ps3 = pd.read_excel(PS3, dtype={"pc11_state_id": str, "pc11_district_id": str})
wave = wave.merge(ps3[["pc11_state_id", "pc11_district_id", "bank_share_sum", "n_banks"]],
                  left_on=["pc11_state_id", "merge_key"],
                  right_on=["pc11_state_id", "pc11_district_id"],
                  how="left", validate="many_to_one", indicator="_m_ps3")
_log(f"-> bank_share_sum_cmie (Design 3): {wave['_m_ps3'].value_counts().to_dict()}")
wave = wave.drop(columns=["pc11_district_id", "_m_ps3"])

# --- 4. Attach the wave deflator (by region) and the food-inflation shift -----
infl = pd.read_stata(INFL)          # wave_no, region_type, gen_index
wave = wave.merge(infl, on=["wave_no", "region_type"], how="left", indicator="_m_cpi")
_log(f"-> inflation_wave: {wave['_m_cpi'].value_counts().to_dict()}")
wave = wave.drop(columns="_m_cpi")

food = pd.read_stata(FOOD)          # wave_no, food_index_national, food_inflation_wave
wave = wave.merge(food, on="wave_no", how="left", indicator="_m_food")
_log(f"-> food_inflation_wave: {wave['_m_food'].value_counts().to_dict()}")
wave = wave.drop(columns="_m_food")

# Rice-production shifter (2026-09-29): one row per wave; rice_growth holds the
# annual growth for the 3 post-harvest waves, rice_growth_harvest only in Sep-Dec.
rice = pd.read_stata(RICE)          # wave_no, rice_prod_lakh_t, rice_growth, rice_growth_harvest
wave = wave.merge(rice, on="wave_no", how="left", validate="many_to_one", indicator="_m_rice")
_log(f"-> rice_production_wave: {wave['_m_rice'].value_counts().to_dict()}")
wave = wave.drop(columns="_m_rice")

# Brent shifter (2026-09-29): wave-average price and 4-month growth, USD and INR
brent = pd.read_stata(BRENT)        # wave_no, brent_usd_bbl, brent_inr_bbl, brent_{usd,inr}_growth_wave
wave = wave.merge(brent, on="wave_no", how="left", validate="many_to_one", indicator="_m_brent")
_log(f"-> brent_price_wave: {wave['_m_brent'].value_counts().to_dict()}")
wave = wave.drop(columns="_m_brent")

# Exchange rate (2026-09-29): wave-average INR/USD and 4-month rupee depreciation
fxw = pd.read_stata(FXW)            # wave_no, inr_per_usd, inr_depreciation_wave
wave = wave.merge(fxw, on="wave_no", how="left", validate="many_to_one", indicator="_m_fx")
_log(f"-> exchange_rate_wave: {wave['_m_fx'].value_counts().to_dict()}")
wave = wave.drop(columns="_m_fx")

# --- 5. Deflate the monetary flows to constant (2012=100) terms --------------
# real = nominal * 100 / gen_index (region-appropriate wave CPI).
for v in DEFLATE_VARS:
    wave[f"r_{v}"] = wave[v] * 100.0 / wave["gen_index"]
_log(f"deflated: {DEFLATE_VARS} -> r_*  (r_tot_inc NaN: {int(wave['r_tot_inc'].isna().sum())})")

# --- 6. Write the household-wave base for Stata ------------------------------
# TEMPORARY (2026-09-29): the alternative share measure (aggregate district
# public-bank share: public_share and its counts public_branches /
# all_branches, merged in step 3) is REMOVED from the final base for now.
# The current estimates use only the original bank shares (bank_share_sum,
# step 3b). Step 3 is kept on purpose, so this measure will be ADDED BACK to
# the base later simply by deleting the two lines below.
ALT_SHARE_VARS = ["public_share", "public_branches", "all_branches"]
wave = wave.drop(columns=[c for c in ALT_SHARE_VARS if c in wave.columns])
# MEMORY (2026-09-29): pandas -to_stata- copies the WHOLE frame and then
# builds a second full copy in Stata record format, so writing the 6.2M x ~150
# base in one call needs several extra GB (the full run stopped here with a
# MemoryError). The base is therefore written in N_PARTS consecutive row
# blocks, each small enough to write safely. The rows are already sorted by
# hh_id, wave_no (groupby keys + left merges keep that order), so a household
# may span two parts but the order is preserved. Categorical columns keep the
# same categories in every block, hence identical value labels in every part.
# The parts are appended into cphs_wave_merged.dta by
# "Append cphs_wave_merged.do" (run it in Stata right after this script).
N_PARTS   = 8                                                    # raise it if RAM is still short
PART_STEM = OUT.with_name(OUT.stem + "_part")                    # cphs_wave_merged_part1.dta, ...
for old_part in OUT.parent.glob(PART_STEM.name + "*.dta"):       # no stale parts from earlier runs
    old_part.unlink()
bounds = np.linspace(0, len(wave), N_PARTS + 1).astype(int)
for k in range(N_PARTS):
    part = wave.iloc[bounds[k]:bounds[k + 1]]
    part.to_stata(f"{PART_STEM}{k + 1}.dta", write_index=False, version=118)
    del part
    gc.collect()
    _log(f"  part {k + 1}/{N_PARTS}: rows {bounds[k] + 1:,}-{bounds[k + 1]:,} written")
_log(f"saved {len(wave):,} rows x {wave.shape[1]} cols in {N_PARTS} parts -> {PART_STEM}1..{N_PARTS}.dta")
_log("NEXT: run 'Append cphs_wave_merged.do' in Stata to build cphs_wave_merged.dta")
print("[merge] final columns:", wave.columns.tolist())


# --- 7. Panel-preserving SAMPLE of the final base (to e-mail, <= 5 MB) --------
# Draws a random subset of HOUSEHOLDS and keeps ALL of their waves, so the
# sample keeps the panel structure: xtset hh_id wave_no and D. behave exactly
# as on the full base (a row-level sample would break the household histories).
# Only households observed in >= SAMPLE_MIN_WAVES waves are eligible: a
# household seen once contributes nothing to first-differenced regressions.
# Size control: the .dta row width is measured on a pilot written to MEMORY,
# the number of households is set from it, and the written file is re-checked
# (dropping households until it fits) so the limit is guaranteed, not estimated.
# Results on this sample are for CODE DEVELOPMENT only, not for inference.
# 2026-09-29: the sample is no longer needed (the full base runs locally);
# set MAKE_SAMPLE = True to write it again.
MAKE_SAMPLE = False
if MAKE_SAMPLE:
    SAMPLE_OUT       = DATA / "cphs_wave_merged_sample.dta"
    SAMPLE_MAX_MB    = 5.0          # hard limit for the e-mailed file (decimal MB, the stricter reading)
    SAMPLE_SEED      = 20260928     # fixed seed -> same households on every run
    SAMPLE_MIN_WAVES = 2            # min. waves per household to be eligible
    LIMIT_BYTES      = int(SAMPLE_MAX_MB * 1_000_000)

    def _dta_nbytes(df):
        """Size in bytes of df written as a Stata .dta (v118), without touching disk."""
        buf = io.BytesIO()
        df.to_stata(buf, write_index=False, version=118)
        return buf.getbuffer().nbytes

    # 7a. Eligible households, in a reproducible random order.
    waves_per_hh = wave.groupby("hh_id", observed=True)["wave_no"].nunique()
    eligible = waves_per_hh[waves_per_hh >= SAMPLE_MIN_WAVES].index.to_numpy()
    rng = np.random.default_rng(SAMPLE_SEED)
    order = rng.permutation(eligible)                                 # shuffled hh_id list
    rows_per_hh = wave.groupby("hh_id", observed=True).size().reindex(order)  # rows in shuffled order
    _log(f"sample: {len(eligible):,} of {len(waves_per_hh):,} households have >= "
         f"{SAMPLE_MIN_WAVES} waves (eligible)")

    # 7b. Bytes per row from a pilot of ~20k rows of the first shuffled households
    #     (the pilot is large enough that the fixed .dta header is negligible).
    pilot_ids = order[: max(1, int(np.searchsorted(rows_per_hh.cumsum().to_numpy(), 20_000)) + 1)]
    pilot = wave[wave["hh_id"].isin(pilot_ids)]
    bytes_per_row = _dta_nbytes(pilot) / len(pilot)

    # 7c. Take whole households in shuffled order until the row budget is used
    #     (3% safety margin for longer strings / header in the final sample).
    max_rows = int(LIMIT_BYTES * 0.97 / bytes_per_row)
    n_hh = int(np.searchsorted(rows_per_hh.cumsum().to_numpy(), max_rows, side="right"))

    # 7d. Build, verify the real size, shrink by 5% of households until it fits.
    while True:
        sample = (wave[wave["hh_id"].isin(order[:n_hh])]
                    .sort_values(KEYS).reset_index(drop=True))        # panel order: hh_id, wave_no
        size = _dta_nbytes(sample)
        if size <= LIMIT_BYTES or n_hh <= 1:
            break
        n_hh = max(1, int(n_hh * 0.95))

    sample.to_stata(SAMPLE_OUT, write_index=False, version=118)
    _log(f"sample saved -> {SAMPLE_OUT}")
    _log(f"  {sample['hh_id'].nunique():,} households | {len(sample):,} household-wave rows | "
         f"waves {int(sample['wave_no'].min())}-{int(sample['wave_no'].max())} | "
         f"{sample['state'].nunique()} states, {sample['merge_key'].nunique()} districts/clusters | "
         f"{SAMPLE_OUT.stat().st_size / 1_000_000:.2f} MB (limit {SAMPLE_MAX_MB} MB)")
    _log(f"  avg waves per household: {len(sample) / sample['hh_id'].nunique():.1f} | "
         f"rows with bank_share_sum missing: {int(sample['bank_share_sum'].isna().sum()):,}")
