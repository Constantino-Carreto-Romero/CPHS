version 17.0
clear all
set more off
set linesize 255
set graphics on

local root "C:/Users/HP/Documents/QMUL/Financial inclusion in India"  // CC 2026-11: project root on Constantino's laptop
local out "`root'/tables/anticonversion/csdid_standard_panel_results"  // CC 2026-11: CSV and DTA results
capture mkdir "`out'"
local fig "`root'/figures/anticonversion/csdid_standard_panel_results"  // CC 2026-11: PNG and GPH figures
capture mkdir "`fig'"
capture log close cs_standard
log using "`root'/code/anticonversion/Sofia/csdid_standard_panel.log", text replace name(cs_standard)  // CC 2026-11: logs stay with the code
csdid version

* Standard pooled csdid; no manual cohort recoding or censoring.
* All outcomes in the previous screen, excluding education-category indicators.
local run_all 1
if "$AC_RUN_ALL" != "" local run_all $AC_RUN_ALL  // CC 2026-11: a master do-file can override run_all through this global
local reps 999
* Use run_all=0 for a short run with pc_01 pc_02 employed_m1.

use hh_panel_id wave_no pc11_state_id analysis_eligible cohort_onset hh_size age1 gender1 edu1 occ1 marital1 empst1 relig1 r_tot_inc r_tot_exp r_minc_all1 r_inc_of_all_mems_frm_wages r_inc_of_hh_frm_pvt_trf r_inc_of_hh_frm_biz_profit r_inc_of_hh_frm_self_prodn r_inc_of_hh_frm_govt_trf r_inc_of_all_mems_frm_interest r_m_exp_food r_m_exp_all_emis r_m_exp_health r_m_exp_edu r_m_exp_remittances_sent has_borr borr_frm_bank borr_frm_lender borr_frm_shg_mfi borr_frm_shg borr_frm_mfi borr_frm_nbfc borr_frm_rel_frnds borr_frm_chtfund borr_frm_shops borr_frm_cc borr_frm_oth_srcs borr_for_hsg borr_for_edu borr_for_med_exp borr_for_wedding borr_for_cons_exp borr_for_cds borr_for_biz borr_for_invsts borr_for_repay borr_for_vehicle borr_for_oth_prps has_saving_in_fd has_saving_in_po has_saving_in_pf has_saving_in_life_ins has_saving_in_mf has_saving_in_shares has_saving_in_gold has_saving_in_real_estate has_saving_in_chtfund has_access_to_electricity has_toilet_in_house two_wheelers_owned refrigerators_owned cattle_owned tractors_owned any_bank sh_bank any_cc sh_cc any_kcc sh_kcc any_lic sh_lic any_hins sh_hins any_mobile sh_mobile any_hosp sh_hosp any_healthy sh_healthy any_medic sh_medic using "`root'/data/anticonversion/cphs_wave_merged_with_treatment_districts.dta", clear  // CC 2026-11: merged panel built from the full CPHS panel; only the variables used, to fit in 12 GB of RAM
keep if analysis_eligible==1
isid hh_panel_id wave_no
assert !missing(pc11_state_id,cohort_onset)
assert inrange(wave_no,1,36) & wave_no==floor(wave_no)
bysort hh_panel_id (wave_no): assert pc11_state_id==pc11_state_id[1]
bysort hh_panel_id (wave_no): assert cohort_onset==cohort_onset[1]

* Covariates are recorded at each observed wave, NOT frozen at 2014 or g-1.
* On the pair-balanced panel path, csdid selects the earlier-period X for each
* 2x2 comparison: g-1 for post effects, t for earlier pre cells with universal base.
* No use of contemporaneous post-treatment X in post-treatment panel contrasts.
* Periods with no valid covariates and missing-covariate units may be excluded
* by csdid; inspect its sample-reduction and calendar warnings.
gen double x_age10=age1/10 if age1>0 & age1<.
gen byte x_female=(gender1==1) if inlist(gender1,1,2)
gen double x_hhsize=hh_size if hh_size>0 & hh_size<.
gen byte x_educ=0 if inlist(edu1,15,18)
replace x_educ=1 if inlist(edu1,3,4,5,6,7)
replace x_educ=2 if inlist(edu1,0,1,2,8,9,10,11)
replace x_educ=3 if inlist(edu1,13,14,16,17)
gen byte x_relig=0 if relig1==3
replace x_relig=1 if relig1==6
replace x_relig=2 if inlist(relig1,0,1,4,5,8,9,11)
* Urban remains outside this initial covariate set after the prior singularity.
* Member-1 characteristics describe the observed household member in that slot;
* the slot does not establish that the same individual is followed over time.
local controls "c.x_age10##c.x_age10 c.x_hhsize i.x_female i.x_educ i.x_relig"

gen double pc_01 = r_tot_inc/hh_size if hh_size>0 & hh_size<.
gen double pc_02 = r_tot_exp/hh_size if hh_size>0 & hh_size<.
gen double pc_03 = r_minc_all1/hh_size if hh_size>0 & hh_size<.
gen double pc_04 = r_inc_of_all_mems_frm_wages/hh_size if hh_size>0 & hh_size<.
gen double pc_05 = r_inc_of_hh_frm_pvt_trf/hh_size if hh_size>0 & hh_size<.
gen double pc_06 = r_inc_of_hh_frm_biz_profit/hh_size if hh_size>0 & hh_size<.
gen double pc_07 = r_inc_of_hh_frm_self_prodn/hh_size if hh_size>0 & hh_size<.
gen double pc_08 = r_inc_of_hh_frm_govt_trf/hh_size if hh_size>0 & hh_size<.
gen double pc_09 = r_inc_of_all_mems_frm_interest/hh_size if hh_size>0 & hh_size<.
gen double pc_10 = r_m_exp_food/hh_size if hh_size>0 & hh_size<.
gen double pc_11 = r_m_exp_all_emis/hh_size if hh_size>0 & hh_size<.
gen double pc_12 = r_m_exp_health/hh_size if hh_size>0 & hh_size<.
gen double pc_13 = r_m_exp_edu/hh_size if hh_size>0 & hh_size<.
gen double pc_14 = r_m_exp_remittances_sent/hh_size if hh_size>0 & hh_size<.
gen byte employed_m1 = (empst1==1) if inlist(empst1,1,3,4,5)
gen byte seeking_m1 = (empst1==4) if inlist(empst1,1,3,4,5)
gen byte notwilling_m1 = (empst1==3) if inlist(empst1,1,3,4,5)
gen byte willing_notlooking_m1 = (empst1==5) if inlist(empst1,1,3,4,5)
gen byte student_m1 = (occ1==16) if !inlist(occ1,2) & !missing(occ1)
gen byte homemaker_m1 = (occ1==3) if !inlist(occ1,2) & !missing(occ1)
gen byte relig_0_m1 = (relig1==0) if !missing(relig1) & !inlist(relig1,2,7,10)
gen byte relig_1_m1 = (relig1==1) if !missing(relig1) & !inlist(relig1,2,7,10)
gen byte relig_3_m1 = (relig1==3) if !missing(relig1) & !inlist(relig1,2,7,10)
gen byte relig_4_m1 = (relig1==4) if !missing(relig1) & !inlist(relig1,2,7,10)
gen byte relig_5_m1 = (relig1==5) if !missing(relig1) & !inlist(relig1,2,7,10)
gen byte relig_6_m1 = (relig1==6) if !missing(relig1) & !inlist(relig1,2,7,10)
gen byte relig_8_m1 = (relig1==8) if !missing(relig1) & !inlist(relig1,2,7,10)
gen byte relig_9_m1 = (relig1==9) if !missing(relig1) & !inlist(relig1,2,7,10)
gen byte relig_11_m1 = (relig1==11) if !missing(relig1) & !inlist(relig1,2,7,10)
gen byte marital_1_m1 = (marital1==1) if !missing(marital1) & !inlist(marital1,0,3)
gen byte marital_2_m1 = (marital1==2) if !missing(marital1) & !inlist(marital1,0,3)
gen byte marital_4_m1 = (marital1==4) if !missing(marital1) & !inlist(marital1,0,3)
gen byte marital_5_m1 = (marital1==5) if !missing(marital1) & !inlist(marital1,0,3)


local all_outcomes r_tot_inc r_tot_exp r_minc_all1 r_inc_of_all_mems_frm_wages r_inc_of_hh_frm_pvt_trf r_inc_of_hh_frm_biz_profit r_inc_of_hh_frm_self_prodn r_inc_of_hh_frm_govt_trf r_inc_of_all_mems_frm_interest r_m_exp_food r_m_exp_all_emis r_m_exp_health r_m_exp_edu r_m_exp_remittances_sent has_borr borr_frm_bank borr_frm_lender borr_frm_shg_mfi borr_frm_shg borr_frm_mfi borr_frm_nbfc borr_frm_rel_frnds borr_frm_chtfund borr_frm_shops borr_frm_cc borr_frm_oth_srcs borr_for_hsg borr_for_edu borr_for_med_exp borr_for_wedding borr_for_cons_exp borr_for_cds borr_for_biz borr_for_invsts borr_for_repay borr_for_vehicle borr_for_oth_prps has_saving_in_fd has_saving_in_po has_saving_in_pf has_saving_in_life_ins has_saving_in_mf has_saving_in_shares has_saving_in_gold has_saving_in_real_estate has_saving_in_chtfund has_access_to_electricity has_toilet_in_house two_wheelers_owned refrigerators_owned cattle_owned tractors_owned any_bank sh_bank any_cc sh_cc any_kcc sh_kcc any_lic sh_lic any_hins sh_hins any_mobile sh_mobile any_hosp sh_hosp any_healthy sh_healthy any_medic sh_medic pc_01 pc_02 pc_03 pc_04 pc_05 pc_06 pc_07 pc_08 pc_09 pc_10 pc_11 pc_12 pc_13 pc_14 employed_m1 seeking_m1 notwilling_m1 willing_notlooking_m1 student_m1 homemaker_m1 relig_0_m1 relig_1_m1 relig_3_m1 relig_4_m1 relig_5_m1 relig_6_m1 relig_8_m1 relig_9_m1 relig_11_m1 marital_1_m1 marital_2_m1 marital_4_m1 marital_5_m1                  

local outcomes `all_outcomes'
if `run_all'==0 local outcomes pc_01 pc_02 employed_m1
postfile status str32 outcome str12 stage int rc using "`out'/run_status.dta", replace
foreach y of local outcomes {
    display as text "OUTCOME: `y' $S_DATE $S_TIME"  // CC 2026-11: time stamp to follow progress and time the run
    * DR DiD with genuine cohorts and built-in not-yet-treated comparisons.
    * Pair balancing uses households observed in BOTH periods of each contrast.
    * Universal base keeps event time -1 as the reference. The default no-
    * anticipation assumption remains substantive, not verified by this command.
    capture noisily csdid `y' `controls', ///
        ivar(hh_panel_id) time(wave_no) gvar(cohort_onset) ///
        notyet method(dr) bal(pair) baseperiod(universal) ///
        cluster(pc11_state_id) wboot(reps(`reps') rseed(29102026))
    local rc=_rc
    post status ("`y'") ("estimation") (`rc')
    if `rc' continue
    display as text "Panel computation: `e(panel_mode)'"
    assert "`e(panel_mode)'"=="pair-balanced"

    * Export the primitive ATT(g,t) cells before any aggregation.
    capture noisily estat attgt, saving("`out'/`y'_attgt.dta") replace
    local rc=_rc
    post status ("`y'") ("attgt") (`rc')

    * Native csdid overall and cohort summaries, all available post periods.
    foreach a in simple group {
        capture noisily estat `a', saving("`out'/`y'_`a'.dta") replace
        local rc=_rc
        post status ("`y'") ("`a'") (`rc')
        if !`rc' {
            matrix A=e(aggte)
            preserve
                clear
                svmat double A, names(col)
                export delimited using "`out'/`y'_`a'.csv", replace
            restore
        }
    }

    * Restricted dynamic aggregation. Rajasthan lacks +6 support and is not
    * included in this event aggregation, but remains a control before wave 36.
    * No dropmissing: failed cells must be diagnosed, not silently omitted.
    capture noisily csdid_stats event, window(-6 6) balance(6)
    local rc=_rc
    post status ("`y'") ("event") (`rc')
    if `rc' continue
    matrix A=e(aggte)
    preserve
        clear
        svmat double A, names(col)
        export delimited using "`out'/`y'_event.csv", replace
    restore
    csdid_plot, saving("`out'/`y'_plotdata.dta") replace
    preserve
        use "`out'/`y'_plotdata.dta", clear
        twoway (rcap ci_high ci_low x, lcolor(navy)) (scatter estimate x, mcolor(navy) msize(small)), title("`y': pooled csdid") xtitle("Waves relative to law commencement") ytitle("ATT in outcome units") xlabel(-6(1)6) yline(0, lpattern(dash) lcolor(gs8)) xline(-0.5, lpattern(dash) lcolor(maroon)) legend(off) note("DR panel DiD; built-in not-yet-treated controls; pair-balanced comparisons." "Earlier-period covariates selected by csdid. No survey weights." "State-clustered multiplier bootstrap: `reps' draws. Few treated states." "Intervals as returned by csdid; inspect log for pointwise fallbacks.", size(vsmall)) name(standard_event, replace)
        graph export "`fig'/`y'_event.png", replace width(2400)  // CC 2026-11: figures go to figures/anticonversion
        graph save "`fig'/`y'_event.gph", replace
        graph drop standard_event
    restore
}
postclose status
preserve
    use "`out'/run_status.dta", clear
    export delimited using "`out'/run_status.csv", replace
    tab stage rc, missing
    list if rc!=0, noobs
restore
log close cs_standard
* No sample restriction to wave 1 and no manual filling of missing covariates.
* No original data or previous results overwritten. No across-outcome adjustment.
