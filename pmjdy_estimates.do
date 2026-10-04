*===========================================================================
* pmjdy_estimates.do  --  first estimates
*
* Shift-share design: the 2013 bank-branch shares s_bd (share of bank b's
* branches in its state located in district d; public banks) interacted with
* NATIONAL macro shifters g_t. The shift-share instrument sum_b s_bd * g_t
* equals bank_share_sum_d * g_t because a national shifter is common to all
* banks, with bank_share_sum_d = sum_b s_bd (built in Build share exposure.py).
* Shifters: 4-month food inflation (main); rice-production growth and
* Brent-in-rupees growth as alternatives. Unit = household x wave.
*
* Sections
*   1. Load only the needed variables, build ids, outcomes, instruments
*   2. Sample description
*   3. MAIN: reduced form in FIRST DIFFERENCES (household effect removed by
*      differencing), wave FE + district FE, SE clustered by district
*   4. Robustness: LEVELS with household FE + wave FE
*   5. Alternative shifters (rice, Brent in INR) for the key outcomes
*   6. Post-PMJDY timing: food-inflation instrument x post (wave >= 3)
*   7. IV: financial inclusion (any adult with a bank account) instrumented
*   8. Event study with -xtevent-: policy = exposure x post-launch
*      (event time 0 = wave 3), graphs exported as .png
* Output folders:
*   <project>/tables  : regression tables, .rtf FORMATTED for Word (open,
*                       copy and paste) and plain .csv
*   <project>/figures : event-study graphs (.png and .gph)
*   <project>/results : log (pmjdy_estimates.log)
*===========================================================================

version 17.0
clear all
set more off
capture log close _all

*--------------------------- USER SETTINGS ---------------------------------
* Project folder: CHANGE THIS LINE to the project folder on your computer
global PROJ "C:/Users/HP/Documents/QMUL/Financial inclusion in India"
local BASEFILE "$PROJ/data/cphs_wave_merged.dta"
*--------------------------- USER SETTINGS ---------------------------------

* district exposure that multiplies every national shifter below
local EXPO "bank_share_sum"
* log folder (tables go to <project>/tables, see the TABLE WRITER below)
local OUT "$PROJ/results"
capture mkdir "`OUT'"
* event-study graphs (.png and .gph) go to their own folder
local FIG "$PROJ/figures"
capture mkdir "`FIG'"
log using "`OUT'/pmjdy_estimates.log", replace text
timer clear 1
timer on 1

* user-written packages (installed once from SSC if missing)
foreach p in ftools reghdfe ivreg2 ranktest ivreghdfe estout {
    capture which `p'
    if _rc {
        ssc install `p', replace
    }
}

*===========================================================================
* 1. DATA
*===========================================================================
* load only what is used (the full base has ~155 columns and millions of rows)
use hh_id wave_no pc11_state_id merge_key bank_share_sum r_hh_wgt_w region_type ///
    hh_size n_adults                                                          ///
    food_inflation_wave rice_growth_harvest rice_growth                       ///
    brent_inr_growth_wave brent_usd_growth_wave                               ///
    r_tot_inc r_tot_exp r_inc_of_hh_frm_govt_trf r_inc_of_hh_frm_pvt_trf      ///
    r_m_exp_all_emis                                                          ///
    any_bank sh_bank n_bank has_borr borr_frm_bank borr_frm_lender            ///
    has_saving_in_fd has_saving_in_gold                                       ///
    using "`BASEFILE'", clear

* panel waves only (wave 1 = Jan-Apr 2014 ... wave 36 = Sep-Dec 2025)
keep if inrange(wave_no, 1, 36)

* identifiers: household (numeric) and district = cluster of the instrument
* (PC11 state + merge_key; Delhi enters as its 3 CMIE clusters)
egen long hh      = group(hh_id)
egen long dist_id = group(pc11_state_id merge_key)
label var hh      "Household id (numeric)"
label var dist_id "District / Delhi cluster id (instrument level, SE cluster)"
xtset hh wave_no

* households without exposure (no crosswalk / no 2013 branches) cannot be used
count if missing(`EXPO')
drop if missing(`EXPO')

* ---- outcomes ----
* strictly positive real flows (constant 2012 rupees per month): logs
gen double ln_r_tot_inc = ln(r_tot_inc) if r_tot_inc > 0
gen double ln_r_tot_exp = ln(r_tot_exp) if r_tot_exp > 0
label var ln_r_tot_inc "log real household income (Rs 2012/month)"
label var ln_r_tot_exp "log real household expenditure (Rs 2012/month)"
* flows that are often zero: inverse hyperbolic sine
foreach v in r_inc_of_hh_frm_govt_trf r_inc_of_hh_frm_pvt_trf r_m_exp_all_emis {
    gen double ihs_`v' = asinh(`v')
    label var ihs_`v' "asinh of `v'"
}

* outcome lists
*   financial inclusion (household): any adult with an account, share of
*   adults with an account, borrowing and saving flags
local Y_FIN "any_bank sh_bank has_borr borr_frm_bank borr_frm_lender has_saving_in_fd has_saving_in_gold"
*   welfare / channels
local Y_WEL "ln_r_tot_inc ln_r_tot_exp ihs_r_inc_of_hh_frm_govt_trf ihs_r_inc_of_hh_frm_pvt_trf ihs_r_m_exp_all_emis"
local Y_ALL "`Y_FIN' `Y_WEL'"

* first differences between consecutive waves (missing when the previous
* wave is missing -- xtset handles gaps). Explicit d_ variables so that the
* same variables are used by reghdfe and ivreghdfe.
foreach y of local Y_ALL {
    gen double d_`y' = D.`y'
    label var d_`y' "First difference of `y'"
}
* change in household size (control for composition changes)
gen double ln_hh_size   = ln(hh_size) if hh_size > 0
gen double d_ln_hh_size = D.ln_hh_size

* ---- instruments: exposure x national shifter ----
* (EXPO = bank_share_sum = sum over banks of the 2013 shares s_bd)
gen double z_food  = `EXPO' * food_inflation_wave
gen double z_rice  = `EXPO' * rice_growth_harvest
gen double z_brent = `EXPO' * brent_inr_growth_wave
label var z_food  "`EXPO' x food inflation (4-month)"
label var z_rice  "`EXPO' x rice production growth (harvest wave)"
label var z_brent "`EXPO' x Brent inflation in INR (4-month)"

* post-PMJDY: PMJDY launched 28-Aug-2014 (end of wave 2), first full wave = 3
gen byte post = wave_no >= 3
gen double z_food_post = z_food * post
label var z_food_post "`EXPO' x food inflation x post-PMJDY (wave >= 3)"

*===========================================================================
* 2. SAMPLE DESCRIPTION
*===========================================================================
di as result _newline "==== Estimation base ===="
* number of households (built-in commands only)
egen byte _tag = tag(hh)
count if _tag
di as text "Households: " r(N)
drop _tag
quietly tab dist_id
di as text "Districts / Delhi clusters: " r(r)
tab wave_no
di as text "District exposure: `EXPO'"
summarize `EXPO' food_inflation_wave rice_growth_harvest brent_inr_growth_wave ///
    z_food z_rice z_brent `Y_ALL' [aw = r_hh_wgt_w]

*===========================================================================
* TABLE WRITER (2026-09-29). Every regression table is saved in
* $PMJDY_TAB (= <project>/tables) in two formats:
*   .rtf : FORMATTED for Word -- readable column titles and coefficient
*          names, 4 decimals, stars, observations with thousands separators,
*          notes. Open it in Word, select the table, copy and paste.
*   .csv : plain version (variable names).
* Estimates are stored as <prefix>_1, <prefix>_2, ... in the order of the
* outcome list all(): Stata limits stored-estimate names to 27 characters,
* and names such as fd_ihs_r_inc_of_hh_frm_govt_trf would exceed it.
* The .rtf can show a SUBSET of the outcomes (ylist) so that wide tables
* are split into financial-inclusion and welfare panels that fit a page.
*===========================================================================
global PMJDY_TAB "$PROJ/tables"
capture mkdir "$PMJDY_TAB"

* column titles of the formatted tables (short: they head a table column)
global L_any_bank                     "Any adult: bank account"
global L_sh_bank                      "Share of adults: bank account"
global L_has_borr                     "Any borrowing"
global L_borr_frm_bank                "Borrowed: bank"
global L_borr_frm_lender              "Borrowed: moneylender"
global L_has_saving_in_fd             "Saves: fixed deposit"
global L_has_saving_in_gold           "Saves: gold"
global L_ln_r_tot_inc                 "Log real income"
global L_ln_r_tot_exp                 "Log real expenditure"
global L_ihs_r_inc_of_hh_frm_govt_trf "asinh govt. transfers"
global L_ihs_r_inc_of_hh_frm_pvt_trf  "asinh private transfers"
global L_ihs_r_m_exp_all_emis         "asinh EMI payments"

* row names of the coefficients (ASCII only: RTF does not carry UTF-8)
global PMJDY_COEFL `"z_food "Exposure x food inflation" z_food_post "Exposure x food inflation x post-PMJDY" z_rice "Exposure x rice production growth" z_brent "Exposure x Brent inflation (INR)" d_ln_hh_size "Change in log household size" d_any_bank "Change in any adult with bank account""'

* first line of every table note
global PMJDY_NOTE "Household wave weights. Standard errors clustered by district (Delhi: 3 CMIE clusters) in parentheses. * p<0.10, ** p<0.05, *** p<0.01. Exposure = sum over public-sector banks of the 2013 district shares of each bank's branches in the state."

capture program drop pmjdy_tab
program define pmjdy_tab
    * prefix(): stored estimates <prefix>_<j>; all(): outcome list that
    * defines j; ylist(): outcomes shown (default: all); keep(): coefficients;
    * file(): name without extension; format(): csv, rtf or both;
    * stats()/coefl(): override the default statistics / add row names;
    * note(): second line of the table note.
    syntax , PREfix(name) ALL(string) KEEP(string) FILE(string) TITLE(string) ///
        [YLIST(string) FORMAT(string) STATS(string asis) COEFL(string asis) NOTE(string)]
    if "`ylist'"  == "" local ylist "`all'"
    if "`format'" == "" local format "both"
    local est ""
    local ml ""
    foreach y of local ylist {
        local j : list posof "`y'" in all
        if `j' == 0 {
            di as error "pmjdy_tab: `y' is not in all()"
            exit 198
        }
        local est "`est' `prefix'_`j'"
        local ml `"`ml' "${L_`y'}""'
    }
    * plain csv (same layout as before)
    if inlist("`format'", "csv", "both") {
        local st `"N N_clust r2, labels("Observations" "Districts" "R-squared")"'
        if `"`stats'"' != "" local st `"`stats'"'
        esttab `est' using "$PMJDY_TAB/`file'.csv", replace ///
            keep(`keep') b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
            stats(`st') mtitles(`ylist') title(`"`title'"')
    }
    * formatted rtf for Word
    if inlist("`format'", "rtf", "both") {
        local st `"N N_clust r2, fmt(%12.0fc %9.0fc %9.3f) labels("Observations" "Districts" "R-squared")"'
        if `"`stats'"' != "" local st `"`stats'"'
        local notes `"addnotes("$PMJDY_NOTE")"'
        if `"`note'"' != "" local notes `"addnotes("$PMJDY_NOTE" "`note'")"'
        esttab `est' using "$PMJDY_TAB/`file'.rtf", replace rtf ///
            keep(`keep') order(`keep') b(%9.4f) se(%9.4f) ///
            star(* 0.10 ** 0.05 *** 0.01) stats(`st') ///
            mlabels(`ml') numbers coeflabels($PMJDY_COEFL `coefl') ///
            title(`"`title'"') nonotes `notes' nogaps
    }
end

*===========================================================================
* 3. MAIN: reduced form in first differences
*    D.y = b * (EXPO x food inflation) + wave FE + district FE
*    b = effect of +1 pp of 4-month food inflation per unit of the exposure
*    (sum over banks of the 2013 shares s_bd).
*    Household weights, district clusters.
*===========================================================================
di as result _newline "==== 3. Reduced form, first differences ===="
eststo clear
local j = 0
foreach y of local Y_ALL {
    local ++j
    reghdfe d_`y' z_food [pw = r_hh_wgt_w], absorb(wave_no dist_id) vce(cluster dist_id)
    eststo fd_`j'
}
local T "Reduced form, first differences: exposure x food inflation"
local N "Dependent variable: change between consecutive waves. Wave and district fixed effects."
pmjdy_tab, prefix(fd) all(`Y_ALL') keep(z_food) file(T1_reduced_form_FD) format(csv) title("`T'")
pmjdy_tab, prefix(fd) all(`Y_ALL') ylist(`Y_FIN') keep(z_food) file(T1_reduced_form_FD_financial) ///
    format(rtf) title("`T' -- financial inclusion") note("`N'")
pmjdy_tab, prefix(fd) all(`Y_ALL') ylist(`Y_WEL') keep(z_food) file(T1_reduced_form_FD_welfare) ///
    format(rtf) title("`T' -- welfare") note("`N'")
* on screen / in the log
esttab fd_*, keep(z_food) b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) stats(N N_clust) mtitles(`Y_ALL')

* same, controlling for the change in household size
local j = 0
foreach y of local Y_ALL {
    local ++j
    reghdfe d_`y' z_food d_ln_hh_size [pw = r_hh_wgt_w], absorb(wave_no dist_id) vce(cluster dist_id)
    eststo fs_`j'
}
local T "Reduced form, first differences, controlling for household size"
pmjdy_tab, prefix(fs) all(`Y_ALL') keep(z_food d_ln_hh_size) file(T1b_reduced_form_FD_hhsize) format(csv) title("`T'")
pmjdy_tab, prefix(fs) all(`Y_ALL') ylist(`Y_FIN') keep(z_food d_ln_hh_size) file(T1b_reduced_form_FD_hhsize_financial) ///
    format(rtf) title("`T' -- financial inclusion") note("`N'")
pmjdy_tab, prefix(fs) all(`Y_ALL') ylist(`Y_WEL') keep(z_food d_ln_hh_size) file(T1b_reduced_form_FD_hhsize_welfare) ///
    format(rtf) title("`T' -- welfare") note("`N'")

*===========================================================================
* 4. ROBUSTNESS: levels with household FE (+ wave FE)
*===========================================================================
di as result _newline "==== 4. Reduced form, levels with household FE ===="
local j = 0
foreach y of local Y_ALL {
    local ++j
    reghdfe `y' z_food [pw = r_hh_wgt_w], absorb(hh wave_no) vce(cluster dist_id)
    eststo fe_`j'
}
local T "Reduced form in levels: exposure x food inflation"
local N2 "Dependent variable in levels. Household and wave fixed effects."
pmjdy_tab, prefix(fe) all(`Y_ALL') keep(z_food) file(T2_reduced_form_levelsFE) format(csv) title("`T'")
pmjdy_tab, prefix(fe) all(`Y_ALL') ylist(`Y_FIN') keep(z_food) file(T2_reduced_form_levelsFE_financial) ///
    format(rtf) title("`T' -- financial inclusion") note("`N2'")
pmjdy_tab, prefix(fe) all(`Y_ALL') ylist(`Y_WEL') keep(z_food) file(T2_reduced_form_levelsFE_welfare) ///
    format(rtf) title("`T' -- welfare") note("`N2'")

*===========================================================================
* 5. ALTERNATIVE SHIFTERS (key outcomes, first differences)
*===========================================================================
di as result _newline "==== 5. Alternative shifters ===="
local Y_KEY "any_bank sh_bank ln_r_tot_inc ln_r_tot_exp"
local T_z_rice  "Reduced form, first differences: exposure x rice production growth (harvest wave)"
local T_z_brent "Reduced form, first differences: exposure x Brent inflation in rupees"
foreach z in z_rice z_brent {
    local j = 0
    foreach y of local Y_KEY {
        local ++j
        reghdfe d_`y' `z' [pw = r_hh_wgt_w], absorb(wave_no dist_id) vce(cluster dist_id)
        eststo `z'_`j'
    }
    pmjdy_tab, prefix(`z') all(`Y_KEY') keep(`z') file(T3_reduced_form_FD_`z') ///
        title("`T_`z''") note("`N'")
}

*===========================================================================
* 6. POST-PMJDY TIMING: does the exposure x food-inflation effect change
*    after the launch? (z_food alone absorbs the pre-period relation)
*===========================================================================
di as result _newline "==== 6. Post-PMJDY interaction ===="
local j = 0
foreach y of local Y_KEY {
    local ++j
    reghdfe d_`y' z_food z_food_post [pw = r_hh_wgt_w], absorb(wave_no dist_id) vce(cluster dist_id)
    eststo post_`j'
}
pmjdy_tab, prefix(post) all(`Y_KEY') keep(z_food z_food_post) file(T4_post_PMJDY) ///
    title("Reduced form, first differences: interaction with the post-PMJDY period (wave >= 3)") ///
    note("`N' Post-PMJDY = waves from Sep-Dec 2014 onwards.")

*===========================================================================
* 7. IV: change in "any adult has a bank account" instrumented by z_food
*    (first stage = column any_bank of section 3). Kleibergen-Paap F reported.
*===========================================================================
di as result _newline "==== 7. IV (2SLS), first differences ===="
local Y_IV "ln_r_tot_inc ln_r_tot_exp ihs_r_m_exp_all_emis"
local j = 0
foreach y of local Y_IV {
    local ++j
    ivreghdfe d_`y' (d_any_bank = z_food) [pw = r_hh_wgt_w], ///
        absorb(wave_no dist_id) cluster(dist_id) first
    eststo iv_`j'
    estadd scalar kpF = e(widstat)
}
pmjdy_tab, prefix(iv) all(`Y_IV') keep(d_any_bank) file(T5_IV_any_bank) format(csv) ///
    title("2SLS, first differences") stats(N kpF, labels("Observations" "First-stage KP F"))
pmjdy_tab, prefix(iv) all(`Y_IV') keep(d_any_bank) file(T5_IV_any_bank) format(rtf) ///
    title("2SLS, first differences: change in any adult with a bank account, instrumented by exposure x food inflation") ///
    stats(N kpF, fmt(%12.0fc %9.2f) labels("Observations" "First-stage Kleibergen-Paap F")) ///
    note("Wave and district fixed effects.")

*===========================================================================
* 8. EVENT STUDY with -xtevent- (Freyaldenhoven, Hansen, Perez Perez,
*    Shapiro & Carreto, Stata Journal 2025). The framework allows a
*    NON-BINARY policy: the model uses leads and lags of the first difference
*    of the policy variable, with binned endpoints.
*    Policy variable = PMJDY exposure = EXPO x 1[wave >= 3]: it jumps at
*    wave 3 (Sep-Dec 2014, first full wave after the 28-Aug-2014 launch) by
*    the district's 2013 exposure (bank_share_sum). Event time 0 = wave 3; default
*    normalisation: event time -1 (wave 2) = 0. Household and wave FE are
*    included by xtevent; SE clustered by district.
*    Only waves 1-2 are pre-launch, so the pre-trend evidence rests on one
*    pre-period (the -2 endpoint): report it as indicative.
*===========================================================================
di as result _newline "==== 8. Event study (xtevent) ===="
capture which xtevent
if _rc {
    ssc install xtevent, replace
}

* post-event window: 12 waves (4 years) or fewer if the data end earlier;
* endpoints bin everything beyond it
quietly summarize wave_no
local K2 = min(12, r(max) - 3 - 1)
di as text "Event window: 1 pre-period, `K2' post-periods (+ binned endpoints)"

* outcomes with an event-study graph: financial inclusion, credit, welfare
local Y_ES "any_bank sh_bank has_borr borr_frm_bank ln_r_tot_inc ln_r_tot_exp"
* graph titles (variable labels do not survive the Python merge)
local t_any_bank     "Any adult member has a bank account"
local t_sh_bank      "Share of adult members with a bank account"
local t_has_borr     "Household has any borrowing"
local t_borr_frm_bank "Household borrowed from a bank"
local t_ln_r_tot_inc "Log real household income"
local t_ln_r_tot_exp "Log real household expenditure"

preserve
    keep hh wave_no dist_id `EXPO' r_hh_wgt_w `Y_ES'
    * The policy path is known for EVERY wave (0 before wave 3, the exposure
    * after), also in waves where a household was not interviewed. Balance
    * the panel so xtevent builds the leads/lags from the true policy path
    * instead of imputing it; the added rows have missing outcomes and are
    * not used in the regression itself.
    tsfill, full
    * exposure and district are fixed per household: fill them into the new rows
    bysort hh (`EXPO'): replace `EXPO' = `EXPO'[1]
    bysort hh (dist_id):      replace dist_id      = dist_id[1]
    gen double pmjdy_exp = `EXPO' * (wave_no >= 3)
    label var pmjdy_exp "PMJDY exposure: `EXPO' x post-launch (wave >= 3)"

    local j = 0
    foreach y of local Y_ES {
        local ++j
        * window(-1 K2): event times -1 (normalised to 0) to K2, endpoints -2 and K2+1.
        * impute(nuchange): the policy is 0 before wave 1 and stays at its last
        * value after wave 36, so leads/lags reaching outside the sample are
        * imputed instead of dropping the first and last waves.
        xtevent `y' [pw = r_hh_wgt_w], policyvar(pmjdy_exp) panelvar(hh) timevar(wave_no) ///
            window(-1 `K2') impute(nuchange) vce(cluster dist_id) reghdfe
        estimates store xe_`j'
        * pre-trend test (only one pre-period available, see note above)
        capture noisily xteventtest, allpre
        * plot: Wald and sup-t bands, pre-trend and leveling-off p-values
        xteventplot, ytitle("Effect on `y' (per unit of `EXPO')") ///
            xtitle("Waves since PMJDY launch (0 = Sep-Dec 2014)") ///
            title("`t_`y''", size(medium)) name(es_`y', replace)
        * .png for the report, .gph to edit the graph later in Stata
        graph export "`FIG'/F_event_study_`y'.png", replace width(1600)
        graph save es_`y' "`FIG'/F_event_study_`y'.gph", replace
    }
    * event-time rows of the formatted table: _k_eq_m2 = endpoint -2,
    * _k_eq_p0.._k_eq_p<K2> = event times 0..K2, _k_eq_p<K2+1> = endpoint
    local KL `"_k_eq_m2 "Event time -2 (endpoint)""'
    forvalues k = 0/`K2' {
        local KL `"`KL' _k_eq_p`k' "Event time `k'""'
    }
    local KL `"`KL' _k_eq_p`=`K2'+1' "Event time `=`K2'+1' (endpoint)""'
    pmjdy_tab, prefix(xe) all(`Y_ES') keep(_k_eq_*) file(T6_event_study_xtevent) format(csv) ///
        title("Event study (xtevent)") stats(N, labels("Observations"))
    pmjdy_tab, prefix(xe) all(`Y_ES') keep(_k_eq_*) file(T6_event_study_xtevent) format(rtf) ///
        title("Event study (xtevent): effect of PMJDY exposure by waves since the launch") ///
        stats(N N_clust, fmt(%12.0fc %9.0fc) labels("Observations" "Districts")) coefl(`KL') ///
        note("Policy = exposure x 1[wave >= 3]. Event time -1 (May-Aug 2014) normalised to 0. Household and wave fixed effects.")
restore

timer off 1
timer list 1
di as result _newline "Done. Tables in $PMJDY_TAB; graphs in `FIG'; log in `OUT'"
log close
