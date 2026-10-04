# =====================================================================
# Recover district assignment via pincode geocoding, for any state whose
# branches SHRUG left unplaced (pc11_district_id == "000").
#
# SHRUG never resolved geography within a few territories, leaving their
# branches district-less: Delhi (95.3% of its branches) and Jammu & Kashmir
# (12.7%). The RBI file carries a pincode for most branches, and the Department
# of Posts directory gives each post office a latitude/longitude, so each
# pincode can be placed inside a PC11 district polygon by location -- more
# reliable than the directory's own district column when a pincode straddles a
# boundary.
#
# One function does the work for every affected state; each call writes one
# lookup, <state>_pincode_district_lookup.csv (long: pin_key, pin_district,
# pin_share), which branches per district.R consumes. This supersedes the
# Delhi-only script Delhi_districts_via_pincode.py.
# =====================================================================

import pandas as pd
import geopandas as gpd
from shapely.geometry import Point
from pathlib import Path

# Project folder: CHANGE THIS LINE to the project folder on your computer
# (the folder that contains data/, tables/, figures/ and code/).
BASE = Path(r"C:\Users\HP\Documents\QMUL\Financial inclusion in India")
DATA = BASE / "data"

PUBLIC = ["SBI AND ITS ASSOCIATES", "NATIONALISED BANKS", "REGIONAL RURAL BANKS"]


def clean_pin(s):
    """Normalise a pincode column to six-digit text; missing values -> <NA>.

    Same normalisation used on the R side: coercing through numeric collapses a
    float-like '110040.0' (how pandas reads an integer column that has blanks)
    back to '110040', so the join is independent of how each file was read. The
    nullable "string" dtype keeps a missing value as a real <NA> through zfill,
    so no literal '<NA>'/'00<NA>' text can leak into a merge key.
    """
    return (pd.to_numeric(s, errors="coerce")
              .astype("Int64").astype("string")
              .str.zfill(6))


# =====================================================================
# Load the shared inputs ONCE; the per-state function slices them.
# =====================================================================

# All-India post office directory (Department of Posts)
po_all = pd.read_csv(DATA / "pincode.csv", dtype=str)

# PC11 district polygons, homogenised id format
districts_all = gpd.read_file(DATA / "shrug-pc11dist-poly-shp" / "district.shp")
districts_all = districts_all.rename(columns={"pc11_s_id": "pc11_state_id",
                                              "pc11_d_id": "pc11_district_id",
                                              "d_name":    "district_name"})
districts_all["pc11_state_id"]    = districts_all["pc11_state_id"].astype(str).str.zfill(2)
districts_all["pc11_district_id"] = districts_all["pc11_district_id"].astype(str).str.zfill(3)

# Full RBI branch directory (SHRUG v2.1), with a clean pincode key and open date
rbi_all = pd.read_csv(DATA / "SHRUG RBI" / "data" / "rbi_directory_shrid.csv",
                      dtype={"pc11_state_id": str, "pc11_district_id": str},
                      low_memory=False)
rbi_all["pc11_state_id"]    = rbi_all["pc11_state_id"].str.zfill(2)
rbi_all["pc11_district_id"] = rbi_all["pc11_district_id"].str.zfill(3)
rbi_all["pin_key"]          = clean_pin(rbi_all["rbi_pincode"])
rbi_all["dt"]               = pd.to_datetime(rbi_all["rbi_date_of_open"], errors="coerce")


# =====================================================================
# One state's recovery: build + write the lookup, then report recovery
# (on its 2013 public 000 branches) and validation (against the branches
# SHRUG DID place).
# =====================================================================

def recover_state(name, state_code, state_regex, bbox, out_name):
    print(f"\n================  {name}  (PC11 state {state_code})  ================")
    lat_lo, lat_hi, lon_lo, lon_hi = bbox

    # --- 1. Post offices in this state with usable coordinates ---
    po = po_all[po_all["StateName"].str.upper()
                      .str.contains(state_regex, na=False, regex=True)].copy()
    po["lat"] = pd.to_numeric(po["Latitude"],  errors="coerce")
    po["lon"] = pd.to_numeric(po["Longitude"], errors="coerce")
    # The bbox only drops gross coordinate errors (swapped/zero/out-of-state);
    # the spatial join below is what actually assigns a district.
    po = po[po["lat"].between(lat_lo, lat_hi) & po["lon"].between(lon_lo, lon_hi)]
    print(f"post offices with usable coordinates: {len(po)}")
    if po.empty:
        print("  !! no post offices matched -- check state_regex / bbox")
        return None
    po_gdf = gpd.GeoDataFrame(
        po, geometry=[Point(xy) for xy in zip(po["lon"], po["lat"])], crs="EPSG:4326")

    # --- 2. PC11 district polygons for this state ---
    # Drop non-districts: a valid PC11 district id starts at 001. The J&K
    # shapefile carries a spurious "000" polygon (no name) for unsurveyed /
    # non-administered area (POK / Aksai Chin); a post office falling inside it
    # must NOT be labelled district "000", which would seed a fake district in
    # the shares and depress the validation. Delhi has no such polygon, so this
    # is a no-op there.
    poly_all = districts_all[districts_all["pc11_state_id"] == state_code]
    poly = poly_all[poly_all["pc11_district_id"] != "000"].to_crs("EPSG:4326")
    n_dropped = len(poly_all) - len(poly)
    print(f"PC11 districts in the shapefile: {poly['pc11_district_id'].nunique()}"
          f"  (dropped {n_dropped} non-district '000' polygon(s))")
    # Roster, so any remaining stray/duplicate polygon is visible at a glance
    for _, row in (poly[["pc11_district_id", "district_name"]]
                   .drop_duplicates().sort_values("pc11_district_id").iterrows()):
        print(f"    {row['pc11_district_id']}  {row['district_name']}")

    # --- 3. Spatial join: which district does each post office sit in? ---
    joined = gpd.sjoin(po_gdf, poly[["pc11_district_id", "district_name", "geometry"]],
                       how="left", predicate="within")

    # --- 4. Long lookup: within-pincode share of post offices per district ---
    pin_dist = (joined.dropna(subset=["pc11_district_id"])
                      .groupby(["Pincode", "pc11_district_id"]).size()
                      .reset_index(name="n_po"))
    if pin_dist.empty:
        print("  !! no post office fell inside a district polygon -- check the shapefile/bbox")
        return None
    totals = pin_dist.groupby("Pincode")["n_po"].transform("sum")
    pin_dist["pin_share"] = pin_dist["n_po"] / totals
    pin_dist["pin_key"]   = clean_pin(pin_dist["Pincode"])
    pin_dist = (pin_dist.dropna(subset=["pin_key"])
                        .rename(columns={"pc11_district_id": "pin_district"}))

    # Write the long lookup (what the R script reads)
    out = (pin_dist[["pin_key", "pin_district", "pin_share"]]
                   .sort_values(["pin_key", "pin_share"], ascending=[True, False]))
    out.to_csv(DATA / out_name, index=False)
    print(f"wrote {len(out)} rows ({out['pin_key'].nunique()} pincodes) -> {out_name}")

    # Modal lookup (one row per pincode) for the reports below
    modal = (pin_dist.sort_values("n_po", ascending=False).drop_duplicates("pin_key")
                     [["pin_key", "pin_district", "pin_share"]]
                     .rename(columns={"pin_share": "pin_confidence"}))
    print(f"  unanimous pincodes: {(modal['pin_confidence'] == 1).sum()} of {len(modal)}")

    # --- 5. Recovery: this state's 2013 public-sector 000 branches ---
    sample = rbi_all[(rbi_all["pc11_state_id"] == state_code) &
                     (rbi_all["pc11_district_id"].isin(["000", "0"])) &
                     (rbi_all["dt"] <= "2013-12-31") &
                     (rbi_all["rbi_bank_group"].isin(PUBLIC)) &
                     (rbi_all["rbi_branch_office"] == "Branch")].copy()
    sample = sample.merge(modal[["pin_key", "pin_district"]], on="pin_key", how="left")
    n, rec = len(sample), int(sample["pin_district"].notna().sum())
    if n:
        print(f"2013 public 000 branches: {n} | recovered: {rec} ({100*rec/n:.1f}%)")
    else:
        print("2013 public 000 branches: 0 (nothing to recover here)")

    # --- 6. Validation: reproduce SHRUG's own code where it did place a branch ---
    control = rbi_all[(rbi_all["pc11_state_id"] == state_code) &
                      (~rbi_all["pc11_district_id"].isin(["000", "0"]))].copy()
    control = control.merge(modal[["pin_key", "pin_district", "pin_confidence"]],
                            on="pin_key", how="left")
    testable = control[control["pin_district"].notna()]
    if len(testable):
        agree = testable["pin_district"] == testable["pc11_district_id"]
        print(f"validation: {int(agree.sum())}/{len(testable)} agree with SHRUG "
              f"({100*agree.mean():.1f}%)")
        print(testable.assign(correct=agree)
                      .groupby(testable["pin_confidence"] == 1)["correct"]
                      .agg(n="size", accuracy="mean"))
    else:
        print("validation: no SHRUG-placed branch shares a pincode with the lookup")

    return out


# =====================================================================
# One config row per affected state. Add a state by adding a call here.
# bbox is (lat_lo, lat_hi, lon_lo, lon_hi) -- a generous box, not a tight fit.
# =====================================================================

recover_state("Delhi", "07", "DELHI",
              bbox=(28.3, 28.95, 76.7, 77.5),
              out_name="delhi_pincode_district_lookup.csv")

# J&K is large and remote: Ladakh (Leh, Kargil) is part of PC11 2011 state 01,
# and recent postal data may label it "Ladakh", so the regex catches all three.
recover_state("Jammu & Kashmir", "01", "JAMMU|KASHMIR|LADAKH",
              bbox=(32.0, 37.2, 73.5, 80.5),
              out_name="jk_pincode_district_lookup.csv")