*===========================================================================
* build_focused_panel_parquet.do  (true month-by-month, self-contained)
*
* Builds the focused household-month panel and writes it straight to
* monthly Parquet parts (part_NNN_YYYYMMDD.parquet) using `pq`.
*
* Requires: ssc install pq   (installed automatically below if missing)

*------------------------- SELF-CONTAINED SETTINGS -------------------------
version 17.0
clear
set more off
capture set varabbrev off
capture set maxvar 32767
capture log close _all

* CPHS_ROOT: where the project lives (OneDrive) -- final parquet output and
* logs go here so they're synced/backed up.
** you can choose variables from variable list and generate parquet

global CPHS_ROOT  "C:/Users/HP/Documents/QMUL/Financial inclusion in India/data/CPHS"

* CPHS_RAW: where the raw CMIE zips actually are (local disk, not OneDrive
* -- much faster to read repeatedly during the build). Change this if your
* raw zips live somewhere else.
global CPHS_RAW  "C:/Users/HP/Documents/QMUL/Financial inclusion in India/data/CPHS/Raw Files"

global CPHS_BUILD "$CPHS_ROOT/build"
global CPHS_LOGS  "$CPHS_BUILD/logs"
global CPHS_PARQUET_OUT "$CPHS_ROOT/cphs_panel_parquet"

* CPHS_TEMP: scratch chunks, created/deleted constantly during the build.
* Kept OFF OneDrive on purpose for faster processing.

global CPHS_TEMP  "$CPHS_RAW/build_tmp"

capture mkdir "$CPHS_BUILD"
capture mkdir "$CPHS_TEMP"
capture mkdir "$CPHS_LOGS"
capture mkdir "$CPHS_PARQUET_OUT"
*-----------------------------------------------------------------------

log using "$CPHS_LOGS/13_build_focused_panel_parquet.do.log", replace text

capture which pq
if _rc {
    di as text "Installing pq (Parquet read/write for Stata) from SSC..."
    ssc install pq
}

if "$CPHS_TEMP" == "" | "$CPHS_TEMP" == "$CPHS_RAW" | "$CPHS_TEMP" == "$CPHS_ROOT" {
    di as error "CPHS_TEMP is not separate from the raw-data folder. Stopping to protect the original zips."
    exit 459
}

*===========================================================================
* Helper: map CMIE Y/N (+DK/NA/Not Applicable) flags to 0/1 on whatever
*===========================================================================
capture program drop cphs_clean_flags
program define cphs_clean_flags
    args pattern
    capture ds `pattern', has(type string)
    if !_rc {
        foreach v in `r(varlist)' {
            tempvar _b
            gen byte `_b' = .
            replace `_b' = 1 if inlist(lower(strtrim(`v')), "y", "yes", "1", "true")
            replace `_b' = 0 if inlist(lower(strtrim(`v')), "n", "no", "0", "false")
            drop `v'
            rename `_b' `v'
        }
    }
end

*===========================================================================
* Unzip each outer module zip ONCE. Nested (per-month/per-wave) zips are
* left zipped; only the one needed at a time gets extracted, used, deleted.
*===========================================================================
foreach m in expenses income members poi aspirational {
    if "`m'" == "expenses"     local outer_`m' "Monthly Expenses"
    if "`m'" == "income"       local outer_`m' "Household Income"
    if "`m'" == "members"      local outer_`m' "Members Income"
    if "`m'" == "poi"          local outer_`m' "People of India"
    if "`m'" == "aspirational" local outer_`m' "Aspirational India"

    local work_`m' "$CPHS_TEMP/w_`m'"
    capture shell rm -rf "`work_`m''"
    capture mkdir "`work_`m''"
    cd "`work_`m''"
    unzipfile "$CPHS_RAW/`outer_`m''.zip", replace
    local nested_`m' : dir "`work_`m''/`outer_`m''" files "*.zip"
}

*===========================================================================
* Month loop: idx 0 = Jan2014 (part_000) ... idx 143 = Dec2025 (part_143)
*===========================================================================
local last_wave = .

forvalues idx = 0/143 {

    local month_date = tm(2014m1) + `idx'
    local yr  = year(dofm(`month_date'))
    local mo  = month(dofm(`month_date'))
    local eom = dofm(`month_date' + 1) - 1                     // last day of month
    local datestr = string(`yr',"%04.0f") + string(`mo',"%02.0f") + string(day(`eom'),"%02.0f")
    local partno  = string(`idx',"%03.0f")
    local outpart = "$CPHS_PARQUET_OUT/part_`partno'_`datestr'.parquet"

    * optional date window
    if "${CPHS_FIRST_SOURCE_DATE}" != "" & "`datestr'" < "${CPHS_FIRST_SOURCE_DATE}" continue
    if "${CPHS_LAST_SOURCE_DATE}"  != "" & "`datestr'" > "${CPHS_LAST_SOURCE_DATE}"  continue

    di as result _newline "==== month `datestr'  (part_`partno') ===="

    * ---- wave for this month (Jan-Apr=1, May-Aug=2, Sep-Dec=3) ----
    local wave_slot     = ceil(`mo'/4)
    local wave_no       = (`yr' - 2014)*3 + `wave_slot'
    local wave_start_mo = (`wave_slot'-1)*4 + 1
    local wave_startstr = string(`yr',"%04.0f") + string(`wave_start_mo',"%02.0f") + "01"

    *-----------------------------------------------------------------------
    
    *-----------------------------------------------------------------------
    if `wave_no' != `last_wave' {

        foreach m in poi aspirational {
            local hit ""
            foreach z of local nested_`m' {
                if strpos("`z'", "`wave_startstr'") & "`hit'" == "" local hit "`z'"
            }
            if "`hit'" == "" {
                di as error "No `m' file found for wave start `wave_startstr'"
                exit 601
            }

            capture shell rm -rf "`work_`m''/csv"
            capture mkdir "`work_`m''/csv"
            cd "`work_`m''/csv"
            unzipfile "`work_`m''/`outer_`m''/`hit'", replace
            local csvs_`m' : dir "`work_`m''/csv" files "*.csv"
            local c_`m' : word 1 of `csvs_`m''

            if "`m'" == "poi" {
                import delimited "`work_`m''/csv/`c_`m''", varnames(1) ///
                    stringcols(2 3) bindquote(strict) case(lower) clear
                cphs_clean_flags has_*
                foreach kk in hh_id mem_id wave_no has_bank_ac has_creditcard ///
                    has_kisan_creditcard has_demat_ac has_pf_ac has_lic ///
                    has_health_ins has_mobile r_ge15_mem_wgt_w {
                    capture confirm variable `kk'
                    if _rc gen `kk' = .
                }
                keep hh_id mem_id wave_no has_bank_ac has_creditcard ///
                    has_kisan_creditcard has_demat_ac has_pf_ac has_lic ///
                    has_health_ins has_mobile r_ge15_mem_wgt_w
                save "$CPHS_TEMP/f_poi_wave.dta", replace
            }
            else {
                import delimited "`work_`m''/csv/`c_`m''", varnames(1) ///
                    stringcols(2) bindquote(strict) case(lower) clear
                cphs_clean_flags has_*
                cphs_clean_flags borr_*
                foreach kk in hh_id wave_no inc_group has_borr borr_frm_bank ///
                    borr_frm_lender borr_frm_shg_mfi borr_frm_rel_frnds ///
                    borr_frm_oth_srcs has_saving_in_fd has_saving_in_po ///
                    has_saving_in_pf has_saving_in_life_ins has_saving_in_mf ///
                    has_saving_in_shares has_saving_in_gold ///
                    has_saving_in_real_estate has_access_to_electricity r_hh_wgt_w {
                    capture confirm variable `kk'
                    if _rc gen `kk' = .
                }
                keep hh_id wave_no inc_group has_borr borr_frm_bank ///
                    borr_frm_lender borr_frm_shg_mfi borr_frm_rel_frnds ///
                    borr_frm_oth_srcs has_saving_in_fd has_saving_in_po ///
                    has_saving_in_pf has_saving_in_life_ins has_saving_in_mf ///
                    has_saving_in_shares has_saving_in_gold ///
                    has_saving_in_real_estate has_access_to_electricity r_hh_wgt_w
                save "$CPHS_TEMP/f_aspirational_wave.dta", replace
            }
            erase "`work_`m''/csv/`c_`m''"
        }
        local last_wave = `wave_no'
    }

    *-----------------------------------------------------------------------
    * This month's Monthly Expenses
    *-----------------------------------------------------------------------
    local hit ""
    foreach z of local nested_expenses {
        if strpos("`z'", "`datestr'") & "`hit'" == "" local hit "`z'"
    }
    capture shell rm -rf "`work_expenses'/csv"
    capture mkdir "`work_expenses'/csv"
    cd "`work_expenses'/csv"
    unzipfile "`work_expenses'/`outer_expenses'/`hit'", replace
    local csvs : dir "`work_expenses'/csv" files "*.csv"
    local c : word 1 of `csvs'
    import delimited "`work_expenses'/csv/`c'", varnames(1) stringcols(1) ///
        bindquote(strict) case(lower) clear
    local keep_exp "hh_id month state hr district region_type stratum psu_id response_status nr_reason r_hh_wgt_ms hh_wgt_ms age_group occupation_group edu_group gender_group size_group tot_exp adj_tot_exp m_exp_food m_exp_intoxicants m_exp_clothing_n_footwear m_exp_cosmetic_n_toiletries m_exp_appliances m_exp_restaurants m_exp_recreation m_exp_bills_n_rent m_exp_house_rent m_exp_power_n_fuel m_exp_transport m_exp_communication_n_info m_exp_edu m_exp_health m_exp_health_ins_premium m_exp_all_emis m_exp_emi_for_house m_exp_emi_for_vehicle m_exp_emi_for_durables m_exp_misc"
    foreach kk of local keep_exp {
        capture confirm variable `kk'
        if _rc gen `kk' = .
    }
    keep `keep_exp'
    gen int month_date = monthly(strtrim(month), "MY")
    format month_date %tm
    drop month
    erase "`work_expenses'/csv/`c'"
    save "$CPHS_TEMP/f_expenses_m.dta", replace

    *-----------------------------------------------------------------------
    * This month's Household Income
    *-----------------------------------------------------------------------
    local hit ""
    foreach z of local nested_income {
        if strpos("`z'", "`datestr'") & "`hit'" == "" local hit "`z'"
    }
    capture shell rm -rf "`work_income'/csv"
    capture mkdir "`work_income'/csv"
    cd "`work_income'/csv"
    unzipfile "`work_income'/`outer_income'/`hit'", replace
    local csvs : dir "`work_income'/csv" files "*.csv"
    local c : word 1 of `csvs'
    import delimited "`work_income'/csv/`c'", varnames(1) stringcols(1) ///
        bindquote(strict) case(lower) clear
    local keep_inc "hh_id month tot_inc inc_of_all_mems_frm_all_srcs inc_of_all_mems_frm_wages inc_of_hh_frm_all_srcs inc_of_hh_frm_rent inc_of_hh_frm_self_prodn inc_of_hh_frm_pvt_trf inc_of_hh_frm_biz_profit"
    foreach kk of local keep_inc {
        capture confirm variable `kk'
        if _rc gen `kk' = .
    }
    keep `keep_inc'
    gen int month_date = monthly(strtrim(month), "MY")
    format month_date %tm
    drop month
    erase "`work_income'/csv/`c'"
    save "$CPHS_TEMP/f_income_m.dta", replace

    *-----------------------------------------------------------------------
    * This month's Members Income -> hh_size/n_adults + wide member block
    *-----------------------------------------------------------------------
    local hit ""
    foreach z of local nested_members {
        if strpos("`z'", "`datestr'") & "`hit'" == "" local hit "`z'"
    }
    capture shell rm -rf "`work_members'/csv"
    capture mkdir "`work_members'/csv"
    cd "`work_members'/csv"
    unzipfile "`work_members'/`outer_members'/`hit'", replace
    local csvs : dir "`work_members'/csv" files "*.csv"
    local c : word 1 of `csvs'
    import delimited "`work_members'/csv/`c'", varnames(1) stringcols(1 2) ///
        bindquote(strict) case(lower) clear
    local keep_mem "hh_id mem_id month mem_status gender age_yrs relation_with_hoh edu nature_of_occupation inc_of_mem_frm_all_srcs inc_of_mem_frm_wages"
    foreach kk of local keep_mem {
        capture confirm variable `kk'
        if _rc gen `kk' = .
    }
    keep `keep_mem'
    gen int month_date = monthly(strtrim(month), "MY")
    format month_date %tm
    drop month
    erase "`work_members'/csv/`c'"
    save "$CPHS_TEMP/f_members_m.dta", replace

    * -- household size / adult count --
    use "$CPHS_TEMP/f_members_m.dta", clear
    gen byte is_member = mem_status == "Member of the household"
    gen byte is_adult  = is_member == 1 & age_yrs > 14 & !missing(age_yrs)
    collapse (sum) hh_size=is_member n_adults=is_adult, by(hh_id month_date)
    save "$CPHS_TEMP/f_size_m.dta", replace

    * -- wide member block, merged with this wave's cached POI data
    *    (broadcast to every month of the wave via wave_no) --
    use "$CPHS_TEMP/f_members_m.dta", clear
    gen int wave_no = `wave_no'
    merge m:1 hh_id mem_id wave_no using "$CPHS_TEMP/f_poi_wave.dta", keep(1 3) nogen

    keep if mem_status == "Member of the household" & age_yrs > 14 & !missing(age_yrs)
    gen byte ishead = relation_with_hoh == "HOH"
    gsort hh_id month_date -ishead -age_yrs mem_id
    by hh_id month_date: gen int slot = _n
    keep if slot <= 20
    drop ishead relation_with_hoh wave_no mem_id mem_status

    rename age_yrs                 age
    rename nature_of_occupation    occ
    rename inc_of_mem_frm_all_srcs minc_all
    rename inc_of_mem_frm_wages    minc_wage
    rename has_bank_ac             bank
    rename has_creditcard          cc
    rename has_kisan_creditcard    kcc
    rename has_demat_ac            demat
    rename has_pf_ac               pf
    rename has_lic                 lic
    rename has_health_ins          hins
    rename has_mobile              mobile
	rename r_ge15_mem_wgt_w 	   mwgt

    capture noisily reshape wide gender age edu occ minc_all minc_wage ///
        bank cc kcc demat pf lic hins mobile mwgt, i(hh_id month_date) j(slot)
    if _rc {
        * no adult members recorded this month (edge case) -> empty shell
        clear
        gen str20 hh_id = ""
        gen int month_date = .
    }
    save "$CPHS_TEMP/f_members_wide_m.dta", replace

    *-----------------------------------------------------------------------
  
    *-----------------------------------------------------------------------
    use "$CPHS_TEMP/f_expenses_m.dta", clear
    gen int wave_no = `wave_no'

    merge 1:1 hh_id month_date using "$CPHS_TEMP/f_income_m.dta",       keep(1 3) nogen
    merge 1:1 hh_id month_date using "$CPHS_TEMP/f_size_m.dta",         keep(1 3) nogen
    merge 1:1 hh_id month_date using "$CPHS_TEMP/f_members_wide_m.dta", keep(1 3) nogen
    merge m:1 hh_id wave_no    using "$CPHS_TEMP/f_aspirational_wave.dta", keep(1 3) nogen

    order hh_id month_date wave_no state district region_type hh_size n_adults
    sort hh_id
    compress

    pq save "`outpart'", replace
    di as result "Wrote `outpart'  (`=_N' rows)"

    * ---- clean up this month's scratch files (wave cache files are kept
    * until the wave changes, deleted only in final cleanup below) ----
    foreach f in f_expenses_m f_income_m f_members_m f_size_m f_members_wide_m {
        capture erase "$CPHS_TEMP/`f'.dta"
    }
}

*===========================================================================
* 
*===========================================================================
foreach m in expenses income members poi aspirational {
    cd "$CPHS_TEMP"
    capture shell rm -rf "`work_`m''"
}
capture erase "$CPHS_TEMP/f_poi_wave.dta"
capture erase "$CPHS_TEMP/f_aspirational_wave.dta"

di as result _newline "Done. Parts written to $CPHS_PARQUET_OUT"
log close
