*===========================================================================
* Append cphs_wave_merged.do
*
* 2026-09-29. Builds the final household-wave base cphs_wave_merged.dta from
* the parts written by Merge_CHPS_and_shares.py. Python writes the base in
* row blocks (cphs_wave_merged_part1.dta, part2, ...) because writing the
* 6.2M x 154 file in one call ran out of memory. This do-file:
*   1. appends the parts in order (each part is compressed first, one at a
*      time, so Stata never holds more than needed),
*   2. checks one row per household-wave and sorts by hh_id wave_no,
*   3. attaches variable labels (CPHS dictionary + the variables created in
*      the Python merge: exposure, deflator, shifters, real flows),
*   4. saves cphs_wave_merged.dta and, only after the save succeeds, erases
*      the parts (they are a duplicate of the final base).
* RUN ORDER: Merge_CHPS_and_shares.py -> THIS FILE -> pmjdy_estimates.do
*===========================================================================

clear all
set more off

* Project folder: CHANGE THIS LINE to the project folder on your computer
global PROJ "C:/Users/HP/Documents/QMUL/Financial inclusion in India"
local DATA   "$PROJ/data"
local STEM   "`DATA'/cphs_wave_merged_part"
local OUT    "`DATA'/cphs_wave_merged.dta"
* dictionary do-file of the CPHS build (variable labels of the CPHS variables)
local DICT   "$PROJ/code/cphs_focused_dictionary.do"

capture log close _all
log using "`DATA'/append_cphs_wave_merged.log", replace text

*---------------------------------------------------------------------------
* 1. Find the parts: part1, part2, ... until the first missing number
*---------------------------------------------------------------------------
local nparts = 0
while 1 {
    capture confirm file "`STEM'`=`nparts'+1'.dta"
    if _rc continue, break
    local nparts = `nparts' + 1
}
if `nparts' == 0 {
    di as error "No parts found (`STEM'1.dta ...). Run Merge_CHPS_and_shares.py first."
    exit 601
}
di as result "Found `nparts' parts."

*---------------------------------------------------------------------------
* 2. Append in order. Each part is compressed before it joins the base
*    (integer-valued doubles -> byte/int/long, shorter strings), which keeps
*    the memory of the full base down. -append- promotes a variable's storage
*    type when two parts differ (e.g. byte in one, int in another).
*---------------------------------------------------------------------------
* 2a. compress each part on its own (only one part in memory at a time)
forvalues k = 1/`nparts' {
    use "`STEM'`k'.dta", clear
    compress
    tempfile p`k'
    save "`p`k''"
}
* 2b. stack the compressed parts in order
use "`p1'", clear
forvalues k = 2/`nparts' {
    append using "`p`k''"
    di as text "  part `k' of `nparts' appended: " as result %12.0fc _N as text " rows so far"
}

* one row per household-wave (the Python merge guarantees it; stop if not)
isid hh_id wave_no
sort hh_id wave_no

*---------------------------------------------------------------------------
* 3. Variable labels
*---------------------------------------------------------------------------
* CPHS variables: labels from the build dictionary (captured: if the file is
* not found the base is still saved, only without these labels)
capture noisily do "`DICT'"
if _rc di as error "NOTE: `DICT' not run (r(`=_rc')); CPHS variable labels not attached."

* variables created in the Python merge
label var pc11_state_id         "PC11 state code (Census 2011)"
label var merge_key             "District exposure key: PC11 district code or Delhi cluster (DL_NNW/DL_NE/DL_SSW)"
label var bank_share_sum        "Sum over public-sector banks of 2013 bank shares s_bd (within-state denominator)"
label var n_banks               "Number of public-sector banks with branches in the district, 2013"
label var gen_index             "CPI General Index (2012=100), wave average, rural or urban"
label var food_index_national   "Consumer Food Price Index, All-India, wave average (2012=100)"
label var food_inflation_wave   "National food inflation, 4-month (100*dln of wave-avg index)"
label var rice_prod_lakh_t      "Rice production, All-India, lakh tonnes (harvest year of the wave)"
label var rice_growth           "Rice production growth, 100*dln annual, held 3 waves"
label var rice_growth_harvest   "Rice production growth, 100*dln annual, harvest wave only"
label var brent_usd_bbl         "Brent crude, USD per barrel, wave average"
label var brent_inr_bbl         "Brent crude, INR per barrel, wave average"
label var brent_usd_growth_wave "Brent inflation in USD, 4-month (100*dln of wave-avg price)"
label var brent_inr_growth_wave "Brent inflation in INR, 4-month (100*dln of wave-avg price)"
label var inr_per_usd           "INR per USD, wave average"
label var inr_depreciation_wave "Rupee depreciation, 4-month (100*dln of wave-avg rate)"
* real flows: "Real (2012 Rs/month): " + the label of the nominal flow
foreach v in tot_inc tot_exp minc_all1 inc_of_all_mems_frm_wages inc_of_hh_frm_pvt_trf ///
    inc_of_hh_frm_biz_profit inc_of_hh_frm_self_prodn inc_of_hh_frm_govt_trf       ///
    inc_of_all_mems_frm_interest m_exp_food m_exp_all_emis m_exp_health m_exp_edu   ///
    m_exp_remittances_sent {
    local lab : variable label `v'
    if "`lab'" == "" local lab "`v'"
    label var r_`v' "Real (2012 Rs/month): `lab'"
}
label data "CPHS household-wave base, PMJDY project (built `c(current_date)')"

*---------------------------------------------------------------------------
* 4. Quick checks, save, then erase the parts
*---------------------------------------------------------------------------
quietly egen long _hh = group(hh_id)
quietly summarize _hh, meanonly
di as result _newline "Rows: " %12.0fc _N "   households: " %10.0fc r(max)
drop _hh
di as text "Waves:"
tab wave_no
quietly count if missing(bank_share_sum)
di as text "Rows with missing bank_share_sum: " as result r(N)
quietly count if missing(r_tot_inc)
di as text "Rows with missing r_tot_inc: " as result r(N)

compress
save "`OUT'", replace
di as result "Saved -> `OUT'"

* the parts duplicate the saved base: remove them only now that it is saved
forvalues k = 1/`nparts' {
    erase "`STEM'`k'.dta"
}
di as text "`nparts' part files erased."

log close
