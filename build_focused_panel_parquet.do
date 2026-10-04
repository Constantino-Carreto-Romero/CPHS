*===========================================================================
* build_focused_panel_parquet.do  (true month-by-month, self-contained)
*
* Builds the focused household-month panel and writes it straight to
* monthly Parquet parts (part_NNN_YYYYMMDD.parquet) using `pq`.
*
* Requires: ssc install pq   (installed automatically below if missing)
*
* 2026-09-29 changes: new variables (Monthly Expenses: m_exp_remittances_sent;
* Household Income: inc_of_hh_frm_govt_trf, inc_of_all_mems_frm_interest;
* Aspirational: borrowing sources & purposes, chit-fund savings, toilet, asset
* counts; People of India: marital/employment status, caste category, religion,
* hospitalised/healthy/on medication), type guards so every monthly part has
* the same schema, all 20 member slots always created, loud reshape, and a
* test switch (CPHS_TEST, set in run_cphs_panel.do).

*------------------------- SETTINGS (folders: see run_cphs_panel.do) --------
version 17.0
clear
set more off
capture set varabbrev off
capture set maxvar 32767
capture log close _all

* All folders are defined in run_cphs_panel.do (the master). Stop if this
* do-file is run on its own, so that nothing is read from or written to a
* wrong folder. (CPHS_PARQUET is the last folder the master defines.)
if "$CPHS_PARQUET" == "" {
    di as error "Folders not defined: run this do-file from run_cphs_panel.do."
    exit 198
}

* Months to build: idx 0 = Jan 2014 ... idx 143 = Dec 2025. In test mode
* (CPHS_TEST = 1 in the master) only April and May 2014 (idx 3-4) are built:
* two months of DIFFERENT waves, so the wave-change logic of the load is also
* tested. The master then sends the parts to a separate test folder.
if $CPHS_TEST == 1 {
    local IDX_FIRST = 3
    local IDX_LAST  = 4
}
else {
    local IDX_FIRST = 0
    local IDX_LAST  = 143
}

capture mkdir "$CPHS_TEMP"
capture mkdir "$CPHS_TABLES"
capture mkdir "$CPHS_PARQUET"
*-----------------------------------------------------------------------

* run log next to the do-files; the slot diagnostics go to CPHS_TABLES
log using "$CPHS_DOFILES/build_focused_panel_parquet.log", replace text

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
* Helper (2026-09-29): force categorical text variables to be STRING in every
* monthly part. A variable absent from a raw file (e.g. employment_status in
* early People of India waves) or entirely blank would otherwise be created /
* imported as NUMERIC in that month and as string in others, and the append
* in load_parquet_selected.do would fail with a type mismatch.
*===========================================================================
capture program drop cphs_force_string
program define cphs_force_string
    syntax namelist
    foreach v of local namelist {
        capture confirm variable `v'
        if _rc {
            gen str1 `v' = ""
        }
        else {
            capture confirm string variable `v'
            if _rc {
                tostring `v', replace force
                replace `v' = "" if `v' == "."
            }
        }
    }
end

*===========================================================================
* Helper: delete a folder and everything inside it (files and subfolders)
* using only Stata commands, so it works on Windows, Mac and Linux. (The
* Unix command "rm -rf", called through -shell-, does not exist on Windows.)
* Use:  capture cphs_rmdir "<folder>"
*===========================================================================
capture program drop cphs_rmdir
program define cphs_rmdir
    args folder
    * safety: only folders INSIDE the scratch folder CPHS_TEMP can be deleted
    * (an empty or wrong path stops here and nothing is deleted)
    if `"`folder'"' == "" | strpos(`"`folder'"', "$CPHS_TEMP/") != 1 {
        di as error "cphs_rmdir: `folder' is not inside $CPHS_TEMP -- not deleted."
        exit 198
    }
    * 1. delete the files of this folder
    local files : dir "`folder'" files "*"
    foreach f of local files {
        erase "`folder'/`f'"
    }
    * 2. delete each subfolder in the same way (the program calls itself)
    local subs : dir "`folder'" dirs "*"
    foreach d of local subs {
        cphs_rmdir "`folder'/`d'"
    }
    * 3. the folder is now empty: delete it
    rmdir "`folder'"
end

*===========================================================================
* Unzip each outer module zip ONCE. Nested (per-month/per-wave) zips are
* left zipped; only the one needed at a time gets extracted, used, deleted.
*===========================================================================
local j = 0                                    // progress counter (modules unzipped)
foreach m in expenses income members poi aspirational {
    if "`m'" == "expenses"     local outer_`m' "Monthly Expenses"
    if "`m'" == "income"       local outer_`m' "Household Income"
    if "`m'" == "members"      local outer_`m' "Members Income"
    if "`m'" == "poi"          local outer_`m' "People of India"
    if "`m'" == "aspirational" local outer_`m' "Aspirational India"

    * progress message: which module is being unzipped, out of 5
    local ++j
    di as result "Unzipping module `j' of 5: `outer_`m''"

    local work_`m' "$CPHS_TEMP/w_`m'"
    capture cphs_rmdir "`work_`m''"
    capture mkdir "`work_`m''"
    cd "`work_`m''"
    unzipfile "$CPHS_RAW/`outer_`m''.zip", replace
    local nested_`m' : dir "`work_`m''/`outer_`m''" files "*.zip"
}

*===========================================================================
* Month loop: idx 0 = Jan2014 (part_000) ... idx 143 = Dec2025 (part_143)
*===========================================================================
local last_wave = .

* Intermediate datasets of each month, as Stata TEMPORARY files. Stata
* deletes them by itself when this do-file ends, also if it stops with an
* error, so no cleanup code is needed. They are declared ONCE, here, before
* the month loop, and overwritten every month: declaring them inside the
* loop would create a new set of files each month, and all of them would
* stay on disk until the end of the run (144 months).
*   f_poi_wave, f_aspirational_wave : the current wave (People of India,
*       Aspirational India), reused by the 4 months of that wave
*   f_expenses_m, f_income_m, f_members_m, f_size_m, f_members_wide_m :
*       the current month
tempfile f_poi_wave f_aspirational_wave f_expenses_m f_income_m ///
         f_members_m f_size_m f_members_wide_m

local diag_month = tm(2014m7)   // July 2014: last month before PMJDY launch

* progress counter: number of months to build and how many have started
local nmonths = `IDX_LAST' - `IDX_FIRST' + 1
local k = 0

* months to build, set above from CPHS_TEST (full run: 0-143; test: 3-4)
forvalues idx = `IDX_FIRST'/`IDX_LAST' {
    local ++k

    local month_date = tm(2014m1) + `idx'
    local yr  = year(dofm(`month_date'))
    local mo  = month(dofm(`month_date'))
	*last day of month
    local eom = dofm(`month_date' + 1) - 1                     
    local datestr = string(`yr',"%04.0f") + string(`mo',"%02.0f") + string(day(`eom'),"%02.0f")
    local partno  = string(`idx',"%03.0f")
    local outpart = "$CPHS_PARQUET/part_`partno'_`datestr'.parquet"

    * progress message: month k of the total and the share of months
    * already finished
    local pct = round(100 * (`k' - 1) / `nmonths')
    di as result _newline "==== Month `k' of `nmonths': `datestr' (part_`partno')  |  `pct'% of months done ===="

    * ---- wave for this month (Jan-Apr=1, May-Aug=2, Sep-Dec=3) ----
    local wave_slot     = ceil(`mo'/4)
    local wave_no       = (`yr' - 2014)*3 + `wave_slot'
    local wave_start_mo = (`wave_slot'-1)*4 + 1
    local wave_startstr = string(`yr',"%04.0f") + string(`wave_start_mo',"%02.0f") + "01"

    *-----------------------------------------------------------------------
    
    *-----------------------------------------------------------------------
    if `wave_no' != `last_wave' {
        * progress message (only when a new wave starts, every 4 months)
        di as text "   new wave `wave_no': reading People of India and Aspirational India"

        foreach m in poi aspirational {
            local hit ""
            foreach z of local nested_`m' {
                if strpos("`z'", "`wave_startstr'") & "`hit'" == "" local hit "`z'"
            }
            if "`hit'" == "" {
                di as error "No `m' file found for wave start `wave_startstr'"
                exit 601
            }

            capture cphs_rmdir "`work_`m''/csv"
            capture mkdir "`work_`m''/csv"
            cd "`work_`m''/csv"
            unzipfile "`work_`m''/`outer_`m''/`hit'", replace
            local csvs_`m' : dir "`work_`m''/csv" files "*.csv"
            local c_`m' : word 1 of `csvs_`m''

            if "`m'" == "poi" {
                import delimited "`work_`m''/csv/`c_`m''", varnames(1) ///
                    stringcols(2 3) bindquote(strict) case(lower) clear
                cphs_clean_flags has_*
                * health flags Y/N -> 0/1 with the same helper (2026-09-29)
                cphs_clean_flags is_*
                * numeric / flag variables (created as missing if absent)
                local keep_poi_num "hh_id mem_id wave_no has_bank_ac has_creditcard has_kisan_creditcard has_demat_ac has_pf_ac has_lic has_health_ins has_mobile r_ge15_mem_wgt_w is_hospitalised is_healthy is_on_regular_medication"
                foreach kk of local keep_poi_num {
                    capture confirm variable `kk'
                    if _rc {
                        * absent from this raw file -> created all-missing; say so
                        di as error "NOTE (`m', wave start `wave_startstr'): `kk' not in raw file, created as missing"
                        gen `kk' = .
                    }
                }
                * categorical member variables, always STRING (2026-09-29)
                local keep_poi_str "marital_status employment_status caste_category religion"
                cphs_force_string `keep_poi_str'
                keep `keep_poi_num' `keep_poi_str'
                save "`f_poi_wave'", replace
            }
            else {
                import delimited "`work_`m''/csv/`c_`m''", varnames(1) ///
                    stringcols(2) bindquote(strict) case(lower) clear
                cphs_clean_flags has_*
                cphs_clean_flags borr_*
                * original variables + (2026-09-29) borrowing sources/purposes,
                * chit-fund savings, toilet, and asset counts
                local keep_asp "hh_id wave_no has_borr borr_frm_bank borr_frm_lender borr_frm_shg_mfi borr_frm_rel_frnds borr_frm_oth_srcs has_saving_in_fd has_saving_in_po has_saving_in_pf has_saving_in_life_ins has_saving_in_mf has_saving_in_shares has_saving_in_gold has_saving_in_real_estate has_access_to_electricity r_hh_wgt_w"
                local keep_asp "`keep_asp' borr_frm_shg borr_frm_mfi borr_frm_nbfc borr_frm_chtfund borr_frm_shops borr_frm_cc"
                local keep_asp "`keep_asp' borr_for_hsg borr_for_edu borr_for_med_exp borr_for_wedding borr_for_cons_exp borr_for_cds borr_for_biz borr_for_invsts borr_for_repay borr_for_vehicle borr_for_oth_prps"
                local keep_asp "`keep_asp' has_saving_in_chtfund has_toilet_in_house"
                local keep_asp_cnt "two_wheelers_owned refrigerators_owned cattle_owned tractors_owned"
                foreach kk in `keep_asp' `keep_asp_cnt' {
                    capture confirm variable `kk'
                    if _rc {
                        * absent from this raw file -> created all-missing; say so
                        di as error "NOTE (`m', wave start `wave_startstr'): `kk' not in raw file, created as missing"
                        gen `kk' = .
                    }
                }
                * asset counts must be NUMERIC in every wave (text such as
                * "Data Not Available" -> missing)
                foreach kk of local keep_asp_cnt {
                    capture confirm string variable `kk'
                    if !_rc destring `kk', replace force
                }
                * inc_group is text: keep it STRING in every wave
                cphs_force_string inc_group
                keep `keep_asp' `keep_asp_cnt' inc_group
                save "`f_aspirational_wave'", replace
            }
            erase "`work_`m''/csv/`c_`m''"
        }
        local last_wave = `wave_no'
    }

    *-----------------------------------------------------------------------
    * This month's Monthly Expenses
    *-----------------------------------------------------------------------
    di as text "   reading Monthly Expenses"           // progress message
    local hit ""
    foreach z of local nested_expenses {
        if strpos("`z'", "`datestr'") & "`hit'" == "" local hit "`z'"
    }
    capture cphs_rmdir "`work_expenses'/csv"
    capture mkdir "`work_expenses'/csv"
    cd "`work_expenses'/csv"
    unzipfile "`work_expenses'/`outer_expenses'/`hit'", replace
    local csvs : dir "`work_expenses'/csv" files "*.csv"
    local c : word 1 of `csvs'
    import delimited "`work_expenses'/csv/`c'", varnames(1) stringcols(1) ///
        bindquote(strict) case(lower) clear
    local keep_exp "hh_id month state hr district region_type stratum psu_id response_status nr_reason r_hh_wgt_ms hh_wgt_ms age_group occupation_group edu_group gender_group size_group tot_exp adj_tot_exp m_exp_food m_exp_intoxicants m_exp_clothing_n_footwear m_exp_cosmetic_n_toiletries m_exp_appliances m_exp_restaurants m_exp_recreation m_exp_bills_n_rent m_exp_house_rent m_exp_power_n_fuel m_exp_transport m_exp_communication_n_info m_exp_edu m_exp_health m_exp_health_ins_premium m_exp_all_emis m_exp_emi_for_house m_exp_emi_for_vehicle m_exp_emi_for_durables m_exp_misc"
    * added 2026-09-29
    local keep_exp "`keep_exp' m_exp_remittances_sent"
    foreach kk of local keep_exp {
        capture confirm variable `kk'
        if _rc {
            * absent from this raw file -> created all-missing; say so
            di as error "NOTE (`datestr'): `kk' not in raw file, created as missing"
            gen `kk' = .
        }
    }
    * text classifiers: keep them STRING in every month (2026-09-29)
    cphs_force_string response_status age_group occupation_group edu_group gender_group size_group
    keep `keep_exp'
    * money flows must be NUMERIC in every month (2026-09-29 guard)
    foreach kk of varlist tot_exp adj_tot_exp m_exp_* {
        capture confirm string variable `kk'
        if !_rc destring `kk', replace force
    }
    gen int month_date = monthly(strtrim(month), "MY")
    format month_date %tm
    drop month
    erase "`work_expenses'/csv/`c'"
    save "`f_expenses_m'", replace

    *-----------------------------------------------------------------------
    * This month's Household Income
    *-----------------------------------------------------------------------
    di as text "   reading Household Income"           // progress message
    local hit ""
    foreach z of local nested_income {
        if strpos("`z'", "`datestr'") & "`hit'" == "" local hit "`z'"
    }
    capture cphs_rmdir "`work_income'/csv"
    capture mkdir "`work_income'/csv"
    cd "`work_income'/csv"
    unzipfile "`work_income'/`outer_income'/`hit'", replace
    local csvs : dir "`work_income'/csv" files "*.csv"
    local c : word 1 of `csvs'
    import delimited "`work_income'/csv/`c'", varnames(1) stringcols(1) ///
        bindquote(strict) case(lower) clear
    local keep_inc "hh_id month tot_inc inc_of_all_mems_frm_all_srcs inc_of_all_mems_frm_wages inc_of_hh_frm_all_srcs inc_of_hh_frm_rent inc_of_hh_frm_self_prodn inc_of_hh_frm_pvt_trf inc_of_hh_frm_biz_profit"
    * added 2026-09-29 (govt transfers = DBT channel; interest income)
    local keep_inc "`keep_inc' inc_of_hh_frm_govt_trf inc_of_all_mems_frm_interest"
    foreach kk of local keep_inc {
        capture confirm variable `kk'
        if _rc {
            * absent from this raw file -> created all-missing; say so
            di as error "NOTE (`datestr'): `kk' not in raw file, created as missing"
            gen `kk' = .
        }
    }
    keep `keep_inc'
    * money flows must be NUMERIC in every month (2026-09-29 guard)
    foreach kk of varlist tot_inc inc_of_* {
        capture confirm string variable `kk'
        if !_rc destring `kk', replace force
    }
    gen int month_date = monthly(strtrim(month), "MY")
    format month_date %tm
    drop month
    erase "`work_income'/csv/`c'"
    save "`f_income_m'", replace

    *-----------------------------------------------------------------------
    * This month's Members Income -> hh_size/n_adults + wide member block
    *-----------------------------------------------------------------------
    di as text "   reading Members Income and building the member block"   // progress message
    local hit ""
    foreach z of local nested_members {
        if strpos("`z'", "`datestr'") & "`hit'" == "" local hit "`z'"
    }
    capture cphs_rmdir "`work_members'/csv"
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
        if _rc {
            * absent from this raw file -> created all-missing; say so
            di as error "NOTE (`datestr'): `kk' not in raw file, created as missing"
            gen `kk' = .
        }
    }
    keep `keep_mem'
    gen int month_date = monthly(strtrim(month), "MY")
    format month_date %tm
    drop month
    erase "`work_members'/csv/`c'"
    save "`f_members_m'", replace

    * -- household size / adult count --
    use "`f_members_m'", clear
    gen byte is_member = mem_status == "Member of the household"
    gen byte is_adult  = is_member == 1 & age_yrs > 14 & !missing(age_yrs)
    collapse (sum) hh_size=is_member n_adults=is_adult, by(hh_id month_date)
    save "`f_size_m'", replace

    * -- wide member block, merged with this wave's cached POI data
    *    (broadcast to every month of the wave via wave_no) --
    use "`f_members_m'", clear
    gen int wave_no = `wave_no'
    merge m:1 hh_id mem_id wave_no using "`f_poi_wave'", keep(1 3) nogen

    keep if mem_status == "Member of the household" & age_yrs > 14 & !missing(age_yrs)
    gen byte ishead = relation_with_hoh == "HOH"
    gsort hh_id month_date -ishead -age_yrs mem_id
    by hh_id month_date: gen int slot = _n
	
	
	
	
	* ---- DIAGNOSTIC: distribution of slot (adult members per household) ----
    * ---- Runs only for `diag_month'. Placed BEFORE the cap so the full, ----
    * ---- untruncated distribution is measured.                          ----
    if `month_date' == `diag_month' {
        preserve

            keep hh_id month_date slot
            tempfile slotdata
            save `slotdata', replace

            * --- (1) summary statistics: sum slot, d ---
            summarize slot, detail
            matrix S = (r(N), r(mean), r(sd), r(min), r(p1), r(p5), r(p10), ///
                        r(p25), r(p50), r(p75), r(p90), r(p95), r(p99),     ///
                        r(max), r(skewness), r(kurtosis))
            matrix colnames S = N mean sd min p1 p5 p10 p25 p50 p75 p90 p95 p99 max skewness kurtosis
            clear
            svmat double S, names(col)
            export excel using "$CPHS_TABLES/slot statistics.xlsx", ///
                sheet("summary") firstrow(variables) replace

            * --- (2) frequency table ---
            * NOTE: the count at slot == k is the number of household-months
            * with AT LEAST k adult members, so this table directly answers
            * how many households a cap at 10 (or 20) would truncate.
            use `slotdata', clear
            contract slot, freq(freq)
            egen double total = total(freq)
            gen double pct = 100 * freq / total
            drop total
            export excel using "$CPHS_TABLES/slot statistics.xlsx", ///
                sheet("frequency") firstrow(variables) sheetmodify

            * --- (3) frequency histogram ---
            use `slotdata', clear
            histogram slot, discrete freq ///
                xtitle("Adult members per household (slot)") ///
                ytitle("Frequency") ///
                title("Distribution of slot, `datestr'")
            graph export "$CPHS_TABLES/slot histogram.png", replace width(1600)

        restore
    }
	
	
	
	
	
	
	
	
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
    * People of India variables added 2026-09-29 (short slot stubs)
    rename marital_status           marital
    rename employment_status        empst
    rename caste_category           castecat
    rename religion                 relig
    rename is_hospitalised          hosp
    rename is_healthy               healthy
    rename is_on_regular_medication medic

    * Reshape only when there are adult members this month. (Before 2026-09-29
    * this was -capture noisily reshape-, which would also have turned ANY
    * reshape error into a silent empty member block; now a real error stops
    * the build immediately instead of producing hours of empty output.)
    if _N == 0 {
        * no adult members recorded this month (edge case) -> empty shell
        clear
        gen str20 hh_id = ""
        gen int month_date = .
    }
    else {
        reshape wide gender age edu occ minc_all minc_wage ///
            bank cc kcc demat pf lic hins mobile mwgt ///
            marital empst castecat relig hosp healthy medic, i(hh_id month_date) j(slot)
    }

    * FIXED SCHEMA (2026-09-29): reshape only creates slots up to this month's
    * largest household, so a part could lack e.g. bank20 and -pq use- would
    * then skip the whole month in the load. Create every slot 1-20 with a
    * fixed type: text stubs as string, flags as byte, the rest as double.
    local slot_str  "gender edu occ marital empst castecat relig"
    local slot_byte "bank cc kcc demat pf lic hins mobile hosp healthy medic"
    local slot_dbl  "age minc_all minc_wage mwgt"
    forvalues s = 1/20 {
        local slot_str_s ""
        foreach v of local slot_str {
            local slot_str_s "`slot_str_s' `v'`s'"
        }
        cphs_force_string `slot_str_s'
        foreach v of local slot_byte {
            capture confirm variable `v'`s'
            if _rc gen byte `v'`s' = .
        }
        foreach v of local slot_dbl {
            capture confirm variable `v'`s'
            if _rc {
                gen double `v'`s' = .
            }
            else {
                * existing numeric stub imported as text -> numeric
                capture confirm string variable `v'`s'
                if !_rc destring `v'`s', replace force
            }
        }
    }
    save "`f_members_wide_m'", replace

    *-----------------------------------------------------------------------
  
    *-----------------------------------------------------------------------
    di as text "   merging the modules and saving the part"   // progress message
    use "`f_expenses_m'", clear
    gen int wave_no = `wave_no'

    merge 1:1 hh_id month_date using "`f_income_m'",       keep(1 3) nogen
    merge 1:1 hh_id month_date using "`f_size_m'",         keep(1 3) nogen
    merge 1:1 hh_id month_date using "`f_members_wide_m'", keep(1 3) nogen
    merge m:1 hh_id wave_no    using "`f_aspirational_wave'", keep(1 3) nogen

    order hh_id month_date wave_no state district region_type hh_size n_adults
    sort hh_id
    compress

    pq save "`outpart'", replace
    di as result "Wrote `outpart'  (`=_N' rows)"
    * progress message: months finished so far
    di as result "   month `k' of `nmonths' finished (" round(100 * `k' / `nmonths') "% of months done)"
}

*===========================================================================
* Delete the unzipped module folders (the temporary .dta files declared
* before the month loop are deleted by Stata itself)
*===========================================================================
foreach m in expenses income members poi aspirational {
    cd "$CPHS_TEMP"
    capture cphs_rmdir "`work_`m''"
}

di as result _newline "Done. Parts written to $CPHS_PARQUET"
log close
