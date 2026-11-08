version 17.0
clear all
set more off

* Original inputs are never overwritten.
local root "C:/Users/sophi/OneDrive - ΠΑΝΕΠΙΣΤΗΜΙΟ ΙΩΑΝΝΙΝΩΝ/papers/anticonversion"
local out "`root'/Data"
capture log close anticonversion
log using "`out'/anticonversion_build_merged.log", text replace name(anticonversion)

tempfile policy
import delimited using "`root'/anticonversion_states.csv", clear varnames(1) stringcols(_all) encoding(utf8)
assert _N == 36
rename state policy_state
rename group policy_group
rename treated ever_treated
rename treat_wave onset_wave
rename treat_wave_lower onset_wave_lower
rename treat_wave_upper onset_wave_upper
destring pc11_state_id ever_treated onset_wave onset_wave_lower onset_wave_upper intens_wave first_law_year, replace
gen str1 policy_class = substr(policy_group, 1, 1)
gen byte pretreated = inlist(policy_class, "B", "C")
gen byte never_treated = inlist(policy_class, "D", "E", "F")
gen double onset_date_lower = daily(treat_date_lower, "YMD")
gen double onset_date_upper = daily(treat_date_upper, "YMD")
format onset_date_lower onset_date_upper %td

* First calendar wave entirely after commencement (not a full interview recall window).
* All main commencement dates are within a wave, so main start is onset_wave + 1.
* Haryana has no exact main date: retain wave 26 assumption, hence full wave 27.
gen byte first_full_wave = onset_wave + 1 if ever_treated == 1
gen byte full_wave_lower = onset_wave_lower + 1 if ever_treated == 1
gen byte full_wave_upper = onset_wave_upper + 1 if ever_treated == 1
assert onset_wave == 14 if policy_state == "Uttarakhand"
assert onset_wave == 26 if policy_state == "Haryana"
assert onset_wave == 36 & first_full_wave == 37 if policy_state == "Rajasthan"

* Telangana and Andhra Pradesh share PC11 code 28. Their treatment coding agrees.
bysort pc11_state_id: assert policy_class == policy_class[1]
bysort pc11_state_id: assert onset_wave == onset_wave[1]
drop if policy_state == "Telangana"
isid pc11_state_id
assert _N == 35
save `policy'

use "`root'/Data/sample20percent.dta", clear
confirm variable wave_no state pc11_state_id
capture confirm string variable pc11_state_id
if !_rc destring pc11_state_id, replace
assert inrange(wave_no, 1, 36) & wave_no == floor(wave_no)
merge m:1 pc11_state_id using `policy', keep(master match) generate(policy_merge)
tab state if policy_merge == 1, missing
assert policy_merge == 3
drop policy_merge
gen int year = 2014 + floor((wave_no - 1)/3)
gen byte analysis_eligible = !pretreated

* DiD cohort: 0 = never treated IN THE OBSERVED PANEL, missing = excluded.
* Rajasthan stays in the sample as a control under the full-wave specification.
quietly summarize wave_no, meanonly
local lastwave = r(max)
gen byte cohort_full = 0 if analysis_eligible
replace cohort_full = first_full_wave if ever_treated & first_full_wave <= `lastwave'
gen byte cohort_onset = 0 if analysis_eligible
replace cohort_onset = onset_wave if ever_treated & onset_wave <= `lastwave'
gen byte treatedpolicy = (wave_no >= first_full_wave) if analysis_eligible & ever_treated
replace treatedpolicy = 0 if never_treated
gen byte treated_onset = (wave_no >= onset_wave) if analysis_eligible & ever_treated
replace treated_onset = 0 if never_treated

* Sensitivity: Haryana lower/upper bound; Uttarakhand partial/full commencement.
gen byte treated_full_early = (wave_no >= full_wave_lower) if analysis_eligible & ever_treated
gen byte treated_full_late = (wave_no >= full_wave_upper) if analysis_eligible & ever_treated
replace treated_full_early = 0 if never_treated
replace treated_full_late = 0 if never_treated
label var treatedpolicy "First full calendar wave after legal commencement"
label var treated_onset "RA commencement wave (partial exposure allowed)"
label var cohort_full "First full wave within panel; 0=untreated in panel; .=excluded"
label var analysis_eligible "Excludes pre-2014 law states, including Arunachal Pradesh"

assert missing(treatedpolicy) & missing(cohort_full) if pretreated
assert treatedpolicy == 0 if never_treated
assert treatedpolicy <= treated_onset if analysis_eligible
assert treated_full_late <= treatedpolicy & treatedpolicy <= treated_full_early if analysis_eligible
tab state treatedpolicy, missing

* Household-wave panel; preserves all original rows and survey weights.
* No monthly treatment: this file has wave_no, but no interview month/date.
compress
* The treatment-enriched panel remains in memory for the district merge.

* State policy audit table (also shows excluded states and future cohorts).
preserve
keep pc11_state_id policy_state policy_class ever_treated pretreated never_treated onset_wave first_full_wave onset_wave_lower onset_wave_upper cohort_full cohort_onset
duplicates drop
isid pc11_state_id
sort pc11_state_id
export delimited using "`out'/treatment_audit.csv", replace
restore

* Add district geography to the same household panel.
tempfile household_treatment
save `household_treatment'

tempfile districts

* Step 1 only: district attributes. No pair expansion or estimation.
import delimited using "`root'/border_districts.csv", clear varnames(1) stringcols(_all) encoding(utf8)
assert _N == 640
rename pc11_district_id merge_key
destring pc11_state_id, replace
keep pc11_state_id merge_key district_name border_any border_treated border_control border_pretreated n_border_pairs neighbour_states first_window_wave last_window_wave dist_border_km dist_to_never_km dist_to_treated_km cphs
isid pc11_state_id merge_key
foreach v in border_any border_treated border_control border_pretreated cphs {
    assert inlist(`v', "TRUE", "FALSE")
    replace `v' = "1" if `v' == "TRUE"
    replace `v' = "0" if `v' == "FALSE"
}
destring border_any border_treated border_control border_pretreated n_border_pairs first_window_wave last_window_wave dist_border_km dist_to_never_km dist_to_treated_km cphs, replace
* Prefix all attributes to prevent conflicts with household treatment variables.
foreach v of varlist district_name-cphs {
    rename `v' ra_`v'
}
save `districts'

use `household_treatment', clear
confirm string variable merge_key
capture confirm string variable pc11_state_id
if !_rc destring pc11_state_id, replace
local original_N = _N
merge m:1 pc11_state_id merge_key using `districts', keep(master match) generate(district_merge)
assert _N == `original_N'
* Delhi's three clusters span several PC11 districts: no centroid/distance assigned.
assert district_merge == 3 if pc11_state_id != 7
assert district_merge == 1 if pc11_state_id == 7
gen byte geo_cluster_unresolved = (district_merge == 1)
label var geo_cluster_unresolved "Delhi multi-district cluster: RA district geography not assigned"
tab district_merge, missing
tab state ra_border_any, missing

preserve
keep pc11_state_id merge_key ra_* geo_cluster_unresolved district_merge
duplicates drop
isid pc11_state_id merge_key
sort pc11_state_id merge_key
export delimited using "`out'/district_geography_audit.csv", replace
restore
save "`out'/sample20percent_with_treatment_districts.dta", replace

* Distances are from district central points, never household distances.
* window bounds use commencement-wave coding; they are descriptive here.
* Do not use the min/max district window to assign active district-pair treatment.

log close anticonversion
