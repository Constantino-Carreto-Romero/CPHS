########################################################
# Create maps of the shares of public-sector bank branches, 2013
########################################################

rm(list = ls())

# packages used by this script: any that is missing is installed once
pkgs <- c("haven", "dplyr", "readr", "sf", "ggplot2", "stringr", "openxlsx")
for (p in pkgs) {
  if (!requireNamespace(p, quietly = TRUE)) install.packages(p)
}

library(haven)
library(dplyr)
library(readr)
library(sf)
library(ggplot2)
library(stringr)
library(openxlsx)

#directories

# Project folder: CHANGE THIS LINE to the project folder on your computer
# (the folder that contains data/, tables/, figures/ and code/).
proj = "C:/Users/HP/Documents/QMUL/Financial inclusion in India"
data = paste0(proj, "/data")
figures = paste0(proj, "/figures")
tables = paste0(proj, "/tables")
# output folders are created if they do not exist yet (write.xlsx and ggsave
# stop with an error when the folder is missing)
dir.create(figures, showWarnings = FALSE)
dir.create(tables, showWarnings = FALSE)

##################################################################
# Load branches data
#################################################################

rbi <- read_csv(
  paste0(data,"/SHRUG RBI/data/rbi_directory_shrid.csv"),
  col_types = cols(
    shrid2           = col_character(),
    pc11_state_id    = col_character(),
    pc11_district_id = col_character(),
    pc11_village_id  = col_character(),
    pc11_town_id     = col_character(),
    rbi_pincode      = col_character(),
    rbi_license_no   = col_character(),
    rbi_date_of_open = col_date(),
    rbi_license_date = col_date(),
    .default         = col_guess()
  )
)

# Check number of districts
# NOTE: this was pasting pc11_district_id to itself, which does not
# identify a district uniquely (district codes repeat across states).
# State + district together is the correct unique key.
length(unique(paste0(rbi$pc11_state_id, "-", rbi$pc11_district_id)))  # expect ~640


##################################################################
# DIAGNOSTIC: branches with no valid district code
##################################################################

# "000" is not a valid PC11 district code (real codes start at 001).
# Check how the missing values actually arrive in the CSV.
cat("NA:  ", sum(is.na(rbi$pc11_district_id)), "\n")
cat("'000':", sum(rbi$pc11_district_id == "000", na.rm = TRUE), "\n")
cat("'0':  ", sum(rbi$pc11_district_id == "0",   na.rm = TRUE), "\n")

# Which states carry the zero-coded branches, across ALL bank groups
rbi %>%
  filter(pc11_district_id %in% c("000", "0")) %>%
  count(pc11_state_id, sort = TRUE)

# Is it concentrated in public banks, or systematic across all of them?
rbi %>%
  filter(pc11_district_id %in% c("000", "0")) %>%
  count(rbi_bank_group, sort = TRUE)

# Share of each state's branches that lack a district
rbi %>%
  group_by(pc11_state_id) %>%
  summarise(total = n(),
            nodist = sum(pc11_district_id %in% c("000", "0")),
            pct = 100 * nodist / total) %>%
  filter(nodist > 0) %>%
  arrange(desc(pct))

# Mumbai: does Maharashtra (state 27) show the same pattern?
rbi %>%
  filter(pc11_state_id == "27") %>%
  count(pc11_district_id, sort = TRUE) %>%
  head(10)


# Mumbai: Maharashtra shows no zero-coded branches, so "Mumbai" is a NAMING
# problem, not a missing-data one. PC11 splits the city into two districts
# (Mumbai Suburban and Mumbai City) while CPHS reports a single "Mumbai".
# Identify which codes are present and how large each is, to decide whether
# CPHS "Mumbai" should map to one of them or to both combined.
rbi %>%
  filter(pc11_state_id == "27") %>%
  count(pc11_district_id, sort = TRUE) %>%
  head(10)

# Does 518 exist at all in the raw directory, before any filtering?
rbi %>%
  filter(pc11_state_id == "27") %>%
  count(pc11_district_id) %>%
  filter(pc11_district_id %in% c("518", "519"))

####################################################

# Keep only: observations with a known district, branches (not administrative
# offices), opened on or before December 31, 2013, and belonging to public banks

t1 <- table(rbi$rbi_bank_group)
write.xlsx(t1, paste0(tables, "/types of banks.xlsx"))
t2 <- table(rbi$rbi_branch_office)
write.xlsx(t2, paste0(tables, "/branch or office.xlsx"))

public_groups <- c("SBI AND ITS ASSOCIATES", "NATIONALISED BANKS", "REGIONAL RURAL BANKS")

rbi_2013_pub <- rbi %>%
  filter(!is.na(pc11_district_id),
         rbi_date_of_open <= as.Date("2013-12-31"),
         rbi_bank_group %in% public_groups,
         rbi_branch_office == "Branch")   # exclude administrative offices (~4% of records)

# Mumbai: PC11 splits the city into Mumbai City (519) and Mumbai Suburban (518),
# but CPHS reports a single "Mumbai" and the CPHS->PC11 crosswalk sends it to
# 519 (SHRUG already assigns essentially all of Mumbai to 519: 2,776 branches vs
# a single one in 518). Fold that lone 518 branch into 519 so Mumbai is one unit
# that matches the crosswalk -- direction matters: recoding toward 518 instead
# would leave the shares labelled 518 while CPHS looks for 519, breaking the join.
rbi_2013_pub <- rbi_2013_pub %>%
  mutate(pc11_district_id = if_else(pc11_state_id == "27" & pc11_district_id == "518",
                                    "519", pc11_district_id))

# Recode SBI and its associates (Patiala, Travancore, Hyderabad, Mysore,
# Bikaner & Jaipur) into a single "SBI GROUP" entity BEFORE computing shares.
# This matters for the state-level denominator below: if left as separate
# banks, each associate gets its own denominator, and later summing their
# shares would mix magnitudes that are not comparable. Recoding first makes
# "SBI GROUP" a single bank with a single, correctly-computed share.
rbi_2013_pub <- rbi_2013_pub %>%
  mutate(rbi_bank_grp = if_else(grepl("STATE BANK", toupper(rbi_bank)),
                                "SBI GROUP", rbi_bank))

##################################################################
# Integrate recovered Delhi districts (pincode geocoding)
#
# Delhi enters the raw directory with pc11_district_id == "000" for ~95% of its
# branches: SHRUG never resolved geography within the city. The !is.na filter
# above lets "000" through, so without this step Delhi would enter the shares as
# one fake district. Recover districts via pincode.py recovers a district for each
# Delhi pincode and writes delhi_pincode_district_lookup.csv (long format:
# pin_key, pin_district, pin_share). Validated against the branches SHRUG could
# place: 89.7% overall, 92.7% on unanimous pincodes.
#
# Both allocation rules are produced in this single run (no manual switch):
#   "hard"       -> each recovered branch to its pincode's modal district, w = 1
#                   (baseline; Delhi within-state shares sum to 1 exactly).
#   "fractional" -> each branch split across its pincode's districts by pin_share
#                   (robustness; boundary pincodes apportioned, still sums to 1).
##################################################################

# Normalise a pincode to 6-digit text by coercing through numeric first. The
# master CSV stores rbi_pincode as "110040.0"; readr's col_character keeps that
# trailing ".0" verbatim, so a plain str_pad would leave the key as "110040.0"
# and match nothing. Going via as.numeric collapses it back to "110040", the
# same normalisation clean_pin does on the Python side.
clean_pin_r <- function(x) {
  n <- suppressWarnings(as.integer(round(as.numeric(x))))
  out <- formatC(n, width = 6, flag = "0", format = "d")
  out[is.na(n)] <- NA_character_
  out
}

# ---- Mode-independent preparation (done once, shared by both rules) ----

# Which states carry district-less ("000") branches we recover, and from which
# lookup. For consistency BOTH states use every pincode (min_conf = 0): a split
# pincode's uncertainty is handled continuously by the "fractional" rule rather
# than by a per-state cutoff. Delhi validates at 89.7%, J&K at 84.1% -- J&K is
# the weaker of the two, and that caution lives in the robustness runs below
# (fractional, and the all-vs-unanimous J&K comparison), not in a special
# baseline rule. min_conf = 1 would keep only unanimous pincodes.
recover_cfg <- list(
  list(state = "07", file = "delhi_pincode_district_lookup.csv", min_conf = 0),
  list(state = "01", file = "jk_pincode_district_lookup.csv",    min_conf = 0)
)
recover_states <- vapply(recover_cfg, function(c) c$state, character(1))

# Read one state's long lookup, tag it with its state, and apply its confidence
# floor. Stacking the results gives a single lookup keyed by (state, pin_key),
# so a state's branches can only match that state's pincodes.
read_lookup <- function(cfg) {
  p <- paste0(data, "/", cfg$file)
  stopifnot(file.exists(p))                      # run "Recover districts via pincode.py" first
  read_csv(p, col_types = cols(pin_key      = col_character(),
                               pin_district = col_character(),
                               pin_share    = col_double())) %>%
    mutate(pin_key       = clean_pin_r(pin_key),
           pin_district  = str_pad(pin_district, 3, pad = "0"),
           pc11_state_id = cfg$state) %>%
    filter(pin_share >= cfg$min_conf)
}
lookup_long <- bind_rows(lapply(recover_cfg, read_lookup))

# Cleaned 6-digit pincode key on the branch side, matching the lookup
rbi_2013_pub <- rbi_2013_pub %>%
  mutate(pin_key = clean_pin_r(rbi_pincode))

# "000" branches in a recovered state -> to be geocoded (with a stable id so
# fractional expansion stays countable). Everything else keeps its own district
# at full weight; any "000" NOT in a recovered state is dropped by the != "000"
# filter below, so it can never form a fake "000" district.
bad <- rbi_2013_pub %>%
  filter(pc11_district_id == "000", pc11_state_id %in% recover_states) %>%
  mutate(branch_uid = row_number())
rest <- rbi_2013_pub %>%
  filter(pc11_district_id != "000") %>%
  mutate(w = 1)

# Per-state diagnostic: how many "000" branches, and how many actually match a
# pincode in the lookup -- i.e. the recovery rate BEFORE aggregation. Expect
# ~92% for Delhi and ~61% for J&K (its unrecovered tail is remote districts
# whose post offices lack coordinates in the postal directory).
for (st in recover_states) {
  bs <- bad         %>% filter(pc11_state_id == st)
  ls <- lookup_long %>% filter(pc11_state_id == st)
  matched <- sum(bs$pin_key %in% ls$pin_key)
  cat(sprintf("state %s: 000 branches %d | lookup pincodes %d | branches matched %d (%.0f%%)\n",
              st, nrow(bs), n_distinct(ls$pin_key),
              matched, 100 * matched / max(nrow(bs), 1)))
}

# ---- One function, both rules, all recovered states ----

# Build the 2013 public-sector shares under a given allocation rule. Only the
# mode-specific step differs (how a recovered branch is spread across districts);
# everything else is prepared above. Returns the shares tibble and asserts that
# within-state shares sum to 1, so both rules are self-validated.
build_shares <- function(mode, rest, bad, lookup_long) {
  
  # Mode-specific lookup: collapse to the modal district per (state, pincode) in
  # "hard" mode. For a state restricted to unanimous pincodes this is a no-op
  # (one row already, share 1), so hard and fractional coincide there.
  lk <- lookup_long
  if (mode == "hard") {
    lk <- lk %>%
      group_by(pc11_state_id, pin_key) %>%
      slice_max(pin_share, n = 1, with_ties = FALSE) %>%   # modal district only
      ungroup() %>%
      mutate(pin_share = 1)                                 # full weight
  }
  
  # Recover. inner_join drops the unrecovered tail; in "fractional" mode it
  # expands a branch into one row per candidate district. A branch's weights sum
  # to 1 either way, so each state's denominator is unchanged. Joining on
  # (state, pin_key) keeps a state's branches matched only to its own pincodes.
  fixed <- bad %>%
    select(-any_of("pc11_district_id")) %>%
    inner_join(lk, by = c("pc11_state_id", "pin_key"),
               relationship = "many-to-many") %>%   # fractional splits a branch across its pincode's districts (expected)
    rename(pc11_district_id = pin_district) %>%
    mutate(w = pin_share)
  
  cat(sprintf("[%-10s] recovered rows: %d | distinct branches: %d\n",
              mode, nrow(fixed), n_distinct(fixed$branch_uid)))
  
  # Reassemble and aggregate: weighted sum, then within-state share.
  keep_cols <- c("pc11_state_id", "pc11_district_id", "rbi_bank_grp", "w")
  shares <- bind_rows(rest  %>% select(all_of(keep_cols)),
                      fixed %>% select(all_of(keep_cols))) %>%
    group_by(pc11_state_id, pc11_district_id, rbi_bank_grp) %>%
    summarise(branches = sum(w), .groups = "drop") %>%
    group_by(pc11_state_id, rbi_bank_grp) %>%
    mutate(share_2013 = branches / sum(branches)) %>%
    ungroup()
  
  # Self-check: within each state-bank the shares must sum to 1.
  n_bad <- shares %>%
    group_by(pc11_state_id, rbi_bank_grp) %>%
    summarise(s = sum(share_2013), .groups = "drop") %>%
    filter(abs(s - 1) > 1e-9) %>% nrow()
  stopifnot(n_bad == 0)
  
  shares
}

# Produce both allocations in one run.
shares_hard <- build_shares("hard",       rest, bad, lookup_long)
shares_frac <- build_shares("fractional", rest, bad, lookup_long)

# Baseline consumed by the map and the exports below.
shares_2013_pub <- shares_hard

# ---- Robustness 1: how far do the recovered states' shares move between rules? ----
# Both states now use all pincodes, so hard vs fractional is a genuine boundary-
# robustness signal for EACH state (per-state summary below).
recov_cmp <- shares_hard %>%
  filter(pc11_state_id %in% recover_states) %>%
  select(pc11_state_id, pc11_district_id, rbi_bank_grp, share_hard = share_2013) %>%
  full_join(shares_frac %>%
              filter(pc11_state_id %in% recover_states) %>%
              select(pc11_state_id, pc11_district_id, rbi_bank_grp, share_frac = share_2013),
            by = c("pc11_state_id", "pc11_district_id", "rbi_bank_grp")) %>%
  mutate(share_hard = coalesce(share_hard, 0),   # a cell absent in one rule = 0 there
         share_frac = coalesce(share_frac, 0),
         abs_diff   = abs(share_hard - share_frac))

print(recov_cmp %>% arrange(desc(abs_diff)) %>% head(15))       # largest divergences
print(recov_cmp %>% group_by(pc11_state_id) %>%                 # per-state summary
        summarise(mean_abs_diff = mean(abs_diff),
                  max_abs_diff  = max(abs_diff),
                  n_cells       = n(), .groups = "drop"))

# ---- Robustness 2: does including J&K's less-certain (non-unanimous) pincodes
# matter? Re-run with a stricter lookup that keeps only J&K's unanimous pincodes
# (Delhi unchanged) and compare J&K's own shares. Small movement => the baseline
# choice of using all J&K pincodes is well justified despite its lower validation;
# large movement => J&K shares are rule-sensitive and warrant caution downstream.
cat("\n-- Robustness 2: J&K all pincodes vs unanimous only --\n")
lookup_strict <- lookup_long %>%
  filter(!(pc11_state_id == "01" & pin_share < 1))   # drop J&K's split pincodes only
shares_jk_strict <- build_shares("hard", rest, bad, lookup_strict)

jk_cmp <- shares_hard %>%
  filter(pc11_state_id == "01") %>%
  select(pc11_district_id, rbi_bank_grp, share_all = share_2013) %>%
  full_join(shares_jk_strict %>%
              filter(pc11_state_id == "01") %>%
              select(pc11_district_id, rbi_bank_grp, share_unanimous = share_2013),
            by = c("pc11_district_id", "rbi_bank_grp")) %>%
  mutate(share_all       = coalesce(share_all, 0),
         share_unanimous = coalesce(share_unanimous, 0),
         abs_diff        = abs(share_all - share_unanimous))

print(jk_cmp %>% arrange(desc(abs_diff)) %>% head(15))          # largest J&K divergences
print(jk_cmp %>% summarise(mean_abs_diff = mean(abs_diff),
                           max_abs_diff  = max(abs_diff),
                           n_cells       = n()))

# Sanity check: for each bank, shares must sum to 1 WITHIN EACH STATE
shares_2013_pub %>%
  group_by(pc11_state_id, rbi_bank_grp) %>%
  summarise(s = sum(share_2013), .groups = "drop") %>%
  filter(abs(s - 1) > 1e-9) %>% nrow()   # want 0

# Diagnostic: banks present in only one district within their state
# (their share is mechanically 1, contributing no within-state variation)
shares_2013_pub %>%
  group_by(pc11_state_id, rbi_bank_grp) %>%
  summarise(n_districts = n(), .groups = "drop") %>%
  count(n_districts == 1)

# How many public-sector 2013 branches sit in each of the Mumbai codes.
# 517/519/521 are the top three Maharashtra codes in the raw directory.
shares_2013_pub %>%
  filter(pc11_state_id == "27", pc11_district_id %in% c("517", "519", "521")) %>%
  group_by(pc11_district_id) %>%
  summarise(branches = sum(branches), banks = n(), .groups = "drop")

shares_2013_pub %>%
  filter(pc11_state_id == "27", pc11_district_id %in% c("518", "519")) %>%
  group_by(pc11_district_id) %>%
  summarise(branches = sum(branches), banks = n(), .groups = "drop")

##################################################################
# Aggregate district public-bank share (Design 2 treatment)
#
# Roxana's macro-shifter design uses a single district exposure: the share of
# ALL branches in the district that are public. This is a scalar per district
# (public / all), 2013, time-invariant. It is a small aggregation of the SAME
# branch data used for s_bd -- both are kept. s_bd stays the object for a
# bank-specific shift; this aggregate share is the exposure for a NATIONAL macro
# shifter (food inflation, oil, rice), which is common across banks and so pairs
# with a single district exposure, not with the per-bank s_bd.
##################################################################

# Hard (modal) lookup: assign each recovered Delhi/J&K branch to its pincode's
# modal district. Same object build_shares("hard") uses, reused for plain counts.
lookup_hard <- lookup_long %>%
  group_by(pc11_state_id, pin_key) %>%
  slice_max(pin_share, n = 1, with_ties = FALSE) %>%
  ungroup()

# Count branches per district AFTER the same district treatment as the shares:
# drop non-recovered "000", and recover Delhi/J&K "000" to their modal district.
recover_counts <- function(df) {
  df <- df %>% mutate(pin_key = clean_pin_r(rbi_pincode))
  bad_d  <- df %>% filter(pc11_district_id == "000", pc11_state_id %in% recover_states)
  rest_d <- df %>% filter(pc11_district_id != "000")
  fixed_d <- bad_d %>%
    select(-any_of("pc11_district_id")) %>%
    inner_join(lookup_hard, by = c("pc11_state_id", "pin_key")) %>%
    rename(pc11_district_id = pin_district)
  bind_rows(rest_d  %>% select(pc11_state_id, pc11_district_id),
            fixed_d %>% select(pc11_state_id, pc11_district_id)) %>%
    count(pc11_state_id, pc11_district_id, name = "branches") %>%
    mutate(pc11_state_id    = str_pad(pc11_state_id,    2, pad = "0"),
           pc11_district_id = str_pad(pc11_district_id, 3, pad = "0"))
}

# Denominator: ALL banks, same 2013/Branch filters and Mumbai fold, but WITHOUT
# the public-group filter and WITHOUT the SBI recode (bank identity is irrelevant
# to a district count). This is the only substantive difference vs the s_bd path.
rbi_2013_all <- rbi %>%
  filter(!is.na(pc11_district_id),
         rbi_date_of_open <= as.Date("2013-12-31"),
         rbi_branch_office == "Branch") %>%
  mutate(pc11_district_id = if_else(pc11_state_id == "27" & pc11_district_id == "518",
                                    "519", pc11_district_id))

all_d <- recover_counts(rbi_2013_all) %>% rename(all_branches = branches)

# Numerator: public branches per district = the hard-mode shares summed over
# banks (the SBI-GROUP recode does not change a per-district count).
public_d <- shares_hard %>%
  group_by(pc11_state_id, pc11_district_id) %>%
  summarise(public_branches = sum(branches), .groups = "drop") %>%
  mutate(pc11_state_id    = str_pad(pc11_state_id,    2, pad = "0"),
         pc11_district_id = str_pad(pc11_district_id, 3, pad = "0"))

# public_share = public / all per district; 0 where a district has branches but
# no public ones. all_branches >= public_branches by construction.
public_share_district <- all_d %>%
  left_join(public_d, by = c("pc11_state_id", "pc11_district_id")) %>%
  mutate(public_branches = coalesce(public_branches, 0),
         public_share    = public_branches / all_branches)

cat(sprintf("Aggregate public share: %d districts | share range %.3f-%.3f | mean %.3f\n",
            nrow(public_share_district),
            min(public_share_district$public_share),
            max(public_share_district$public_share),
            mean(public_share_district$public_share)))
# Guard: every district's public count must not exceed its all count.
stopifnot(all(public_share_district$public_branches <= public_share_district$all_branches))

##################################################################
# Shapefiles
#################################################################

districts <- st_read(paste0(data, "/shrug-pc11dist-poly-shp/district.shp")) %>%
  rename(pc11_state_id    = pc11_s_id,
         pc11_district_id = pc11_d_id,
         district_name    = d_name) %>%
  mutate(pc11_state_id    = as.character(pc11_state_id),
         pc11_district_id = as.character(pc11_district_id))

states <- st_read(paste0(data, "/shrug-pc11state-poly-shp/state.shp")) %>%
  rename(pc11_state_id    = pc11_s_id) %>%
  mutate(pc11_s_id    = as.character(pc11_state_id))

##################################################################
# Homologate ID format
#################################################################

districts <- districts %>%
  mutate(pc11_state_id    = str_pad(as.character(pc11_state_id),    2, pad = "0"),
         pc11_district_id = str_pad(as.character(pc11_district_id), 3, pad = "0"))

states <- states %>%
  mutate(pc11_state_id    = str_pad(as.character(pc11_state_id),    2, pad = "0"))

# Check what the shares IDs look like, and pad the same way if needed
head(shares_2013_pub$pc11_state_id)
head(shares_2013_pub$pc11_district_id)

shares_2013_pub <- shares_2013_pub %>%
  mutate(pc11_state_id    = str_pad(as.character(pc11_state_id),    2, pad = "0"),
         pc11_district_id = str_pad(as.character(pc11_district_id), 3, pad = "0"))

##################################################################
# Merge shapefile and data
#################################################################

# Now a simple filter, not a sum: "SBI GROUP" already IS the combined share,
# correctly computed with its own state-level denominator.
map_data <- districts %>%
  left_join(
    shares_2013_pub %>%
      filter(rbi_bank_grp == "SBI GROUP") %>%
      select(pc11_state_id, pc11_district_id, sbi_share = share_2013),
    by = c("pc11_state_id", "pc11_district_id")
  )

sum(!is.na(map_data$sbi_share))   # districts that matched — want ~600+
sum( is.na(map_data$sbi_share))   # grey districts (no public branches, or no SBI presence) — want small

##################################################################
# Map
##################################################################

# NOTE on interpretation: under the bank-within-state denominator, sbi_share
# measures "this district's share of SBI GROUP's branches WITHIN ITS OWN STATE" —
# it is NOT comparable in absolute terms across states. Quintiles are therefore
# computed globally here for a single readable legend, but the title/subtitle
# must say explicitly that the measure is state-relative. If cross-state
# comparability is required instead, compute quintiles within each state
# (group_by(pc11_state_id) before the cut()).

map_data <- map_data %>%
  mutate(sbi_class = cut(
    sbi_share,
    breaks = quantile(sbi_share, probs = seq(0, 1, 0.2), na.rm = TRUE),
    include.lowest = TRUE,
    dig.lab = 2
  ))

map1 <- ggplot() +
  geom_sf(data= map_data, aes(fill = sbi_class), color = "grey", linewidth = 0.01) +
  scale_fill_viridis_d(name = "SBI share\n(quintiles)",
                       na.value = "grey85",
                       na.translate = FALSE) +
  theme_void() +
  labs(title    = "SBI group's share of public-sector bank branches",
       subtitle = "By district, as of December 2013 — share relative to the bank's own state network",
       caption  = "Source: RBI branch directory via SHRUG v2.1")

#map1 

map1 +
  geom_sf(data= states, color = "black", size = 1)

ggsave(paste0(figures, "/map_sbi_share_2013 relative to each state.png"), width = 8, height = 9, dpi = 300)

# check: each bank's shares should sum to 1 within each state (see sanity check above)
shares_2013_pub %>% group_by(pc11_state_id, rbi_bank_grp) %>% summarise(s = sum(share_2013), .groups = "drop")



####################################################


write.xlsx(shares_2013_pub, paste0(tables, "/shares.xlsx"))            # baseline (hard)
write.xlsx(shares_frac,      paste0(tables, "/shares_fractional.xlsx"))    # robustness
write.xlsx(recov_cmp,        paste0(tables, "/recovered_shares_hard_vs_fractional.xlsx"))
write.xlsx(jk_cmp,           paste0(tables, "/jk_shares_all_vs_unanimous.xlsx"))
write.xlsx(public_share_district, paste0(tables, "/public_share_district_2013.xlsx"))  # Design 2 exposure


##################################################################
# CMIE-clustered exposures for the CPHS merge (Delhi only)
#
# CPHS/CMIE reports Delhi's urban population as 3 aggregates, not by PC11
# district, so the exposure the panel merges to must live at those 3 clusters
# (the outcome side cannot be finer). Each cluster is a union of PC11 districts
# that partitions Delhi's 9; here we relabel Delhi's district to its cluster and
# re-aggregate. Everything else keeps its PC11 district unchanged. Script 2 (the
# Python merge) maps the panel's Delhi CPHS text onto the SAME cluster labels.
#
# Aggregation is done on COUNTS: the public share of a cluster is
# sum(public)/sum(all) over its districts, NOT an average of ratios; s_bd shares
# are additive within a bank-state, so a cluster's share is the sum of its
# member-district shares. The district-level objects above are left intact (the
# map still uses them); these clustered files are what Script 2 reads.
##################################################################

# PC11 district code -> Delhi cluster label (applied only within state 07).
#   DL_NNW = North(091) + North West(090) + West(096)          [CPHS "North - North West - West"]
#   DL_NE  = North East(092) + East(093)                        [CPHS "North East - East"]
#   DL_SSW = South(098) + South West(097) + Central(095) + New Delhi(094)
#                                                               [CPHS "South - South West - Central - New Delhi"]
delhi_cluster <- c("090" = "DL_NNW", "091" = "DL_NNW", "096" = "DL_NNW",
                   "092" = "DL_NE",  "093" = "DL_NE",
                   "094" = "DL_SSW", "095" = "DL_SSW", "097" = "DL_SSW", "098" = "DL_SSW")

to_cluster <- function(state, district) {
  cl <- unname(delhi_cluster[district])              # cluster label, or NA if not a Delhi code
  ifelse(state == "07" & !is.na(cl), cl, district)   # relabel only within Delhi (state guarded)
}

# s_bd shares, Delhi collapsed to clusters (per bank). Within-state shares still
# sum to 1 -- clustering only groups districts inside the state.
shares_cmie <- shares_2013_pub %>%
  mutate(pc11_district_id = to_cluster(pc11_state_id, pc11_district_id)) %>%
  group_by(pc11_state_id, pc11_district_id, rbi_bank_grp) %>%
  summarise(branches   = sum(branches),
            share_2013 = sum(share_2013), .groups = "drop")

# Aggregate public share, Delhi collapsed to clusters: sum the counts, then ratio.
public_share_cmie <- public_share_district %>%
  mutate(pc11_district_id = to_cluster(pc11_state_id, pc11_district_id)) %>%
  group_by(pc11_state_id, pc11_district_id) %>%
  summarise(public_branches = sum(public_branches),
            all_branches    = sum(all_branches), .groups = "drop") %>%
  mutate(public_share = public_branches / all_branches)

# Sanity: Delhi now has exactly 3 rows (the clusters); shares still sum to 1.
cat("Delhi rows in public_share_cmie:", sum(public_share_cmie$pc11_state_id == "07"), "(expect 3)\n")
stopifnot(sum(public_share_cmie$pc11_state_id == "07") == 3)
n_bad_cmie <- shares_cmie %>%
  group_by(pc11_state_id, rbi_bank_grp) %>%
  summarise(s = sum(share_2013), .groups = "drop") %>%
  filter(abs(s - 1) > 1e-9) %>% nrow()
stopifnot(n_bad_cmie == 0)

write.xlsx(shares_cmie,       paste0(tables, "/shares_cmie.xlsx"))              # s_bd, Delhi clustered
write.xlsx(public_share_cmie, paste0(tables, "/public_share_cmie_2013.xlsx"))  # Design 2 exposure, Delhi clustered