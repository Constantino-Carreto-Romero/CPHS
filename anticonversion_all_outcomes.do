version 17.0
clear all
set more off
set linesize 255
set graphics on
local root "C:/Users/HP/Documents/QMUL/Financial inclusion in India"  // CC 2026-11: project root on Constantino's laptop
local out "`root'/tables/anticonversion/all_outcomes_results"  // CC 2026-11: CSV and DTA results
capture mkdir "`out'"
local fig "`root'/figures/anticonversion/all_outcomes_results"  // CC 2026-11: PNG figures
capture mkdir "`fig'"
capture log close allout  // CC 2026-11: close a log of the same name if an earlier run left it open
log using "`root'/code/anticonversion/Sofia/all_outcomes.log", text replace name(allout)  // CC 2026-11: named log, so a log left open by an earlier run cannot block this one
csdid version
* CC 2026-11: run_all=1 runs the full outcome list (default, as before); 0 runs three outcomes as a
* quick test. A master do-file can override the value through the global AC_RUN_ALL.
local run_all 1
if "$AC_RUN_ALL" != "" local run_all $AC_RUN_ALL
* Exploratory outcomes, no covariates, no survey weights, no winsorization.
* All outputs are retained irrespective of significance. No family-wise correction
* across outcomes. Categorical indicators describe member-1 composition only.
* Household membership changes can alter member 1: these are not person transitions.
use hh_panel_id wave_no pc11_state_id analysis_eligible cohort_onset hh_size empst1 occ1 relig1 marital1 edu1 r_tot_inc r_tot_exp r_minc_all1 r_inc_of_all_mems_frm_wages r_inc_of_hh_frm_pvt_trf r_inc_of_hh_frm_biz_profit r_inc_of_hh_frm_self_prodn r_inc_of_hh_frm_govt_trf r_inc_of_all_mems_frm_interest r_m_exp_food r_m_exp_all_emis r_m_exp_health r_m_exp_edu r_m_exp_remittances_sent has_borr borr_frm_bank borr_frm_lender borr_frm_shg_mfi borr_frm_shg borr_frm_mfi borr_frm_nbfc borr_frm_rel_frnds borr_frm_chtfund borr_frm_shops borr_frm_cc borr_frm_oth_srcs borr_for_hsg borr_for_edu borr_for_med_exp borr_for_wedding borr_for_cons_exp borr_for_cds borr_for_biz borr_for_invsts borr_for_repay borr_for_vehicle borr_for_oth_prps has_saving_in_fd has_saving_in_po has_saving_in_pf has_saving_in_life_ins has_saving_in_mf has_saving_in_shares has_saving_in_gold has_saving_in_real_estate has_saving_in_chtfund has_access_to_electricity has_toilet_in_house two_wheelers_owned refrigerators_owned cattle_owned tractors_owned any_bank sh_bank any_cc sh_cc any_kcc sh_kcc any_lic sh_lic any_hins sh_hins any_mobile sh_mobile any_hosp sh_hosp any_healthy sh_healthy any_medic sh_medic using "`root'/data/anticonversion/cphs_wave_merged_with_treatment_districts.dta", clear  // CC 2026-11: merged panel built from the full CPHS panel
keep if analysis_eligible==1
isid hh_panel_id wave_no
assert !missing(pc11_state_id,cohort_onset)
bysort hh_panel_id (wave_no): assert pc11_state_id==pc11_state_id[1]
bysort hh_panel_id (wave_no): assert cohort_onset==cohort_onset[1]
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

local outcomes r_tot_inc r_tot_exp r_minc_all1 r_inc_of_all_mems_frm_wages r_inc_of_hh_frm_pvt_trf r_inc_of_hh_frm_biz_profit r_inc_of_hh_frm_self_prodn r_inc_of_hh_frm_govt_trf r_inc_of_all_mems_frm_interest r_m_exp_food r_m_exp_all_emis r_m_exp_health r_m_exp_edu r_m_exp_remittances_sent has_borr borr_frm_bank borr_frm_lender borr_frm_shg_mfi borr_frm_shg borr_frm_mfi borr_frm_nbfc borr_frm_rel_frnds borr_frm_chtfund borr_frm_shops borr_frm_cc borr_frm_oth_srcs borr_for_hsg borr_for_edu borr_for_med_exp borr_for_wedding borr_for_cons_exp borr_for_cds borr_for_biz borr_for_invsts borr_for_repay borr_for_vehicle borr_for_oth_prps has_saving_in_fd has_saving_in_po has_saving_in_pf has_saving_in_life_ins has_saving_in_mf has_saving_in_shares has_saving_in_gold has_saving_in_real_estate has_saving_in_chtfund has_access_to_electricity has_toilet_in_house two_wheelers_owned refrigerators_owned cattle_owned tractors_owned any_bank sh_bank any_cc sh_cc any_kcc sh_kcc any_lic sh_lic any_hins sh_hins any_mobile sh_mobile any_hosp sh_hosp any_healthy sh_healthy any_medic sh_medic pc_01 pc_02 pc_03 pc_04 pc_05 pc_06 pc_07 pc_08 pc_09 pc_10 pc_11 pc_12 pc_13 pc_14 employed_m1 seeking_m1 notwilling_m1 willing_notlooking_m1 student_m1 homemaker_m1 relig_0_m1 relig_1_m1 relig_3_m1 relig_4_m1 relig_5_m1 relig_6_m1 relig_8_m1 relig_9_m1 relig_11_m1 marital_1_m1 marital_2_m1 marital_4_m1 marital_5_m1  // CC 2026-11: the 18 edu_*_m1 indicators are no longer generated above (dropped in the 29 Oct version), so they are removed from the list
if `run_all'==0 local outcomes pc_01 pc_02 employed_m1  // CC 2026-11: test run
postfile progress str32 outcome str12 stage int rc using "`out'/run_status.dta", replace
foreach y of local outcomes {
    display as text "START_OUTCOME `y' $S_TIME"
    capture noisily csdid `y', ivar(hh_panel_id) time(wave_no) gvar(cohort_onset) method(reg) bal(none) baseperiod(universal) cluster(pc11_state_id) wboot(reps(999) rseed(28102026))
    local rc=_rc
    post progress ("`y'") ("estimation") (`rc')
    if `rc' continue
    foreach a in simple group {
        capture noisily estat `a', saving("`out'/`y'_`a'.dta") replace
        local rc=_rc
        post progress ("`y'") ("`a'") (`rc')
        if !`rc' {
            matrix A=e(aggte)
            preserve
                clear
                svmat double A, names(col)
                export delimited using "`out'/`y'_`a'.csv", replace
            restore
        }
    }
    capture noisily csdid_stats event, window(-6 6) balance(6)
    local rc=_rc
    post progress ("`y'") ("event") (`rc')
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
        twoway (rcap ci_high ci_low x, lcolor(navy)) (scatter estimate x, mcolor(navy) msize(small)), title("`y'") xtitle("Waves relative to law commencement") ytitle("ATT in outcome units") xlabel(-6(1)6) yline(0, lpattern(dash) lcolor(gs8)) xline(-0.5, lpattern(dash) lcolor(maroon)) legend(off) note("No covariates or survey weights. State-clustered multiplier bootstrap: 999 draws." "Event window -6 to +6; balance(6). Bands are not adjusted across outcomes." "Preliminary; full CPHS panel (base of 20 Oct 2026); few treated states. See outcome dictionary for definitions.", size(vsmall)) name(current_event, replace)  // CC 2026-11: note states the sample actually used
        graph export "`fig'/`y'_event.png", replace width(2000)  // CC 2026-11: figures go to figures/anticonversion
        graph drop current_event
    restore
    display as text "END_OUTCOME `y' $S_TIME"
}
postclose progress
preserve
    use "`out'/run_status.dta", clear
    export delimited using "`out'/run_status.csv", replace
    tab stage rc, missing  // CC 2026-11: summary of failed estimates, as in the other two analysis files
    list if rc!=0, noobs
restore
file open done using "`out'/COMPLETED.txt", write replace
file write done "Batch finished; inspect run_status.csv for failed estimates or aggregations."
file close done
log close allout  // CC 2026-11: named log
set graphics on
