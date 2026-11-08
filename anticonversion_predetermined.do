version 17.0
clear all
set more off
set linesize 255
set graphics on

local root "C:/Users/sophi/OneDrive - ΠΑΝΕΠΙΣΤΗΜΙΟ ΙΩΑΝΝΙΝΩΝ/papers/anticonversion"
local out "`root'/Data/predetermined_2014_results"
capture mkdir "`out'"
capture log close pred
log using "`out'/predetermined_results.log", text replace name(pred)
csdid version

* DEFAULT: three main outcomes. Set run_all=1 to repeat the expanded outcome screen (education-category outcomes excluded).
local run_all 0
* All baseline covariates use wave 1 (Jan-Apr 2014), before every in-panel adoption.
* No contemporaneous covariates, survey weights, logs, or winsorization.
* This does not establish conditional parallel trends or solve few-state inference.
use "`root'/Data/sample20percent_with_treatment_districts.dta", clear
keep if analysis_eligible==1
isid hh_panel_id wave_no
assert !missing(pc11_state_id,cohort_onset)
bysort hh_panel_id (wave_no): assert pc11_state_id==pc11_state_id[1]
bysort hh_panel_id (wave_no): assert cohort_onset==cohort_onset[1]

* Build one baseline row per household, using observed labels/codes in this file.
* Member 1 is a household roster slot, not necessarily a stable person over time.
preserve
    keep if wave_no==1
    isid hh_panel_id
    gen double b_age10=age1/10 if age1>0 & age1<.
    gen byte b_female=(gender1==1) if inlist(gender1,1,2)
    gen double b_hhsize=hh_size if hh_size>0 & hh_size<.
    assert inlist(upper(strtrim(region_type)),"RURAL","URBAN") | missing(region_type)
    gen byte b_urban=(upper(strtrim(region_type))=="URBAN") if !missing(region_type)
    * Education categories: no schooling/preschool; grades 1-5; grades 6-12;
    * diploma/degree. Never interpret the original edu1 codes as years.
    gen byte b_educ=0 if inlist(edu1,15,18)
    replace b_educ=1 if inlist(edu1,3,4,5,6,7)
    replace b_educ=2 if inlist(edu1,0,1,2,8,9,10,11)
    replace b_educ=3 if inlist(edu1,13,14,16,17)
    label define base_edu 0 "No schooling/preschool" 1 "Grades 1-5" 2 "Grades 6-12" 3 "Diploma/degree"
    label values b_educ base_edu
    * Broad baseline religion categories limit sparse cells; they do not exhaust
    * potentially relevant religious differences. Invalid/nonresponse codes missing.
    gen byte b_relig=0 if relig1==3
    replace b_relig=1 if relig1==6
    replace b_relig=2 if inlist(relig1,0,1,4,5,8,9,11)
    label define base_relig 0 "Hindu" 1 "Muslim" 2 "Other stated religion"
    label values b_relig base_relig
    gen byte has_baseline=1
    keep hh_panel_id has_baseline b_*
    tempfile baseline
    save `baseline'
restore
merge m:1 hh_panel_id using `baseline', keep(master match) nogen
replace has_baseline=0 if missing(has_baseline)
gen byte baseline_complete=has_baseline & !missing(b_age10,b_female,b_hhsize,b_urban,b_educ,b_relig)

* Audit distinct households and household-wave retention by state.
egen byte household_tag=tag(hh_panel_id)
gen byte complete_tag=household_tag*baseline_complete
gen byte baseline_tag=household_tag*has_baseline
preserve
    collapse (count) observations=wave_no (sum) retained_observations=baseline_complete households=household_tag households_at_wave1=baseline_tag retained_households=complete_tag, by(state pc11_state_id cohort_onset)
    gen double retained_household_share=retained_households/households
    export delimited using "`out'/baseline_retention_by_state.csv", replace
    list state households retained_households retained_household_share, noobs
restore
keep if baseline_complete==1
assert wave_no==floor(wave_no)
* Check baseline covariates are fixed over time.
foreach x of varlist b_* {
    bysort hh_panel_id (wave_no): assert `x'==`x'[1]
}
* Inspect covariate distributions by cohort; this is not an overlap proof.
preserve
    keep if household_tag==1
    tab cohort_onset b_educ, row
    tab cohort_onset b_relig, row
    tab cohort_onset b_female, row
    tab cohort_onset b_urban, row
    table cohort_onset, statistic(mean b_age10 b_hhsize)
restore

local controls "c.b_age10##c.b_age10 c.b_hhsize i.b_female i.b_urban i.b_educ i.b_relig"

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

local outcomes pc_01 pc_02 employed_m1
if `run_all'==1 local outcomes `all_outcomes'
postfile status str32 outcome str12 specification str12 stage int rc using "`out'/run_status.dta", replace

foreach y of local outcomes {
    * Only doubly robust estimation with fixed 2014 baseline covariates.
    foreach spec in dr_baseline {
        local xs "`controls'"
        local estimator "dr"
        display as text "OUTCOME `y'; SPECIFICATION `spec'"
        capture noisily csdid `y' `xs', ivar(hh_panel_id) time(wave_no) gvar(cohort_onset) notyet method(`estimator') bal(none) baseperiod(universal) cluster(pc11_state_id) wboot(reps(999) rseed(29102026))
        local rc=_rc
        post status ("`y'") ("`spec'") ("estimation") (`rc')
        if `rc' continue

        * Inspect warnings about propensity-score trimming, missing cells, or
        * singular designs. No dropmissing: do not conceal non-estimable cells.
        * DR defaults to pscoretrim(.995). Any cell-level trimming may change
        * usable controls; inspect the warnings and covariate distributions.
        foreach a in simple group {
            capture noisily estat `a', saving("`out'/`y'_`spec'_`a'.dta") replace
            local rc=_rc
            post status ("`y'") ("`spec'") ("`a'") (`rc')
            if !`rc' {
                matrix A=e(aggte)
                preserve
                    clear
                    svmat double A, names(col)
                    export delimited using "`out'/`y'_`spec'_`a'.csv", replace
                restore
            }
        }
        capture noisily csdid_stats event, window(-6 6) balance(6)
        local rc=_rc
        post status ("`y'") ("`spec'") ("event") (`rc')
        if `rc' continue
        matrix A=e(aggte)
        preserve
            clear
            svmat double A, names(col)
            export delimited using "`out'/`y'_`spec'_event.csv", replace
        restore
        csdid_plot, saving("`out'/`y'_`spec'_plotdata.dta") replace
        preserve
            use "`out'/`y'_`spec'_plotdata.dta", clear
            twoway (rcap ci_high ci_low x, lcolor(navy)) (scatter estimate x, mcolor(navy) msize(small)), title("`y': `spec'") xtitle("Waves relative to law commencement") ytitle("ATT in outcome units") xlabel(-6(1)6) yline(0, lpattern(dash) lcolor(gs8)) xline(-0.5, lpattern(dash) lcolor(maroon)) legend(off) note("Baseline-complete households. Covariates, when included, fixed at wave 1 (2014)." "State-clustered multiplier bootstrap: 999 draws. No survey weights." "Event aggregation: -6 to +6, balance(6). Few treated states; preliminary inference.", size(vsmall)) name(pred_event, replace)
            graph export "`out'/`y'_`spec'_event.png", replace width(2400)
            graph save "`out'/`y'_`spec'_event.gph", replace
            graph drop pred_event
        restore
    }
}
postclose status
preserve
    use "`out'/run_status.dta", clear
    export delimited using "`out'/run_status.csv", replace
    tab specification rc, missing
    list if rc!=0, noobs
restore
log close pred
* No original input datasets are overwritten. Stata remains open.
