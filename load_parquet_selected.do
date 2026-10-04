*===========================================================================
* load_parquet_selected.do  --  Loads the monthly CPHS parquet parts (built
*                               by build_focused_panel_parquet.do) into Stata
*                               and saves the files used in the analysis.
*
* OUTPUT: TWO files (the original version of this do-file saved one)
*   (1) selected_cphs_panel_data.dta  -- household-MONTH (~24 million rows):
*       keys, geography, sampling weights, household size and the monthly
*       money flows (income and expenditure). Same file name as before.
*   (2) selected_cphs_wave_data.dta   -- household-WAVE (~6 million rows):
*       the variables CMIE collects once per wave -- Aspirational India
*       (borrowing, savings, assets), People of India (bank account and the
*       other member flags) -- plus the CMIE household groups, the household
*       head's characteristics and household summaries of the member flags.
*   Both files share the keys hh_id and wave_no.
*
* WHY TWO FILES INSTEAD OF ONE
*   1. CPHS collects the data at two frequencies. Income and expenditure are
*      recorded every month, but Aspirational India and People of India are
*      recorded once per wave (4 months). In a single household-month file,
*      each wave-level value is copied into the 4 months of its wave: the
*      file becomes larger without containing any additional information.
*   2. Size and memory. The wave-level block has almost 100 variables. Kept
*      at the monthly level it adds those columns to ~24 million rows; kept
*      at the wave level it adds them to ~6 million rows (one quarter). The
*      full panel had already exhausted the computer's memory in the Python
*      merge (Merge_CHPS_and_shares.py) before the new variables requested
*      by the team were added; with them, a single file would make both
*      Stata and Python slower and more likely to fail.
*   3. It matches the unit of the estimation base, which is household-WAVE:
*      the Python merge averages the monthly flows of file (1) to the wave
*      and then attaches file (2) directly, one row to one row.
*   4. Nothing is lost and the change can be undone. The single
*      household-month file can be rebuilt at any time with one merge:
*          use "selected_cphs_panel_data.dta", clear
*          merge m:1 hh_id wave_no using "selected_cphs_wave_data.dta"
*      and the parquet parts still contain every variable.
*
* MEMBER SLOTS
*   The parts store each adult member (15+) in slots 1-20 (slot 1 = household
*   head, then the other adults from oldest to youngest; e.g. bank1 = head
*   has a bank account, bank2 = second member, ...). Here the 20 slots of
*   each member flag are summarised into household variables (any_, n_,
*   nm_, sh_; defined below) and slot 1 is kept as the head's own value.
*   Slots 2-20 are not saved in the .dta files (9 flags x 19 slots = 171
*   columns); they remain available in the parquet parts.
*
* CHECKS
*   After each file is saved, read-only checks are written to the log
*   (LOGFILE below): special CMIE codes in the money flows, waves present,
*   variables entirely missing, coverage by wave of the new variables, and
*   values outside 0/1 in the yes/no flags. They only report; they never
*   change or stop the saved files.
*
* RUN: from run_cphs_panel.do (step 3), after build_focused_panel_parquet.do.
*===========================================================================

clear all
set more off
*ssc install pq

** Please change user setting and cols in the section "Variables to pull" below to generate the panel you wish to analyse. variables are given in cphs_focused_dictionary.do
** all variable list is avilable in Tables folder.
** if you need more variabled which are not available in cphs_focused_dictionary.do but available in Tables, please let me know and I will generate the parquets agains.

* All folders are defined in run_cphs_panel.do (the master). Stop if this
* do-file is run on its own, so that nothing is read from or written to a
* wrong folder. (CPHS_PARQUET is the last folder the master defines.)
if "$CPHS_PARQUET" == "" {
    di as error "Folders not defined: run this do-file from run_cphs_panel.do."
    exit 198
}

* input folder, output files and log. CPHS_SUFFIX is "_test" in test mode
* (set in the master), so a test never overwrites the files of the full panel.
local PQFOLDER "$CPHS_PARQUET"
local OUT_M    "$CPHS_ROOT/selected_cphs_panel_data$CPHS_SUFFIX.dta"
local OUT_W    "$CPHS_ROOT/selected_cphs_wave_data$CPHS_SUFFIX.dta"
local LOGFILE  "$CPHS_DOFILES/load_parquet_selected$CPHS_SUFFIX.log"

* log of the whole run, including the CHECKS at the end (send this file)
capture log close _all
log using "`LOGFILE'", replace text

*---------------------------------------------------------------------------
* Variables to pull (every name must exist in the parquet parts, otherwise
* -pq use- fails and the month is SKIPPED).
*---------------------------------------------------------------------------
* keys, present in both output files
local KEYS "hh_id month_date wave_no"

* ---- (1) household-MONTH file: one local per block, joined at the end ----
* geography, sampling weights and household size
local M_HH  "state district region_type hh_size n_adults response_status r_hh_wgt_ms hh_wgt_ms r_hh_wgt_w"
* monthly income flows (Rs/month)
local M_INC "tot_inc minc_all1 inc_of_all_mems_frm_wages inc_of_hh_frm_pvt_trf inc_of_hh_frm_biz_profit inc_of_hh_frm_self_prodn inc_of_hh_frm_govt_trf inc_of_all_mems_frm_interest"
* monthly expenditure flows (Rs/month)
local M_EXP "tot_exp m_exp_food m_exp_all_emis m_exp_health m_exp_edu m_exp_remittances_sent"
* all money flows in one list (also used by the checks below)
local FLOWS_M "`M_INC' `M_EXP'"
* final list of the household-month file
local COLS_M  "`M_HH' `FLOWS_M'"

* ---- (2) household-WAVE file: one local per block, joined at the end ----
* Aspirational India: borrowing (yes/no) and its sources
local W_BORR_SRC "has_borr borr_frm_bank borr_frm_lender borr_frm_shg_mfi borr_frm_shg borr_frm_mfi borr_frm_nbfc borr_frm_rel_frnds borr_frm_chtfund borr_frm_shops borr_frm_cc borr_frm_oth_srcs"
* Aspirational India: purposes of the borrowing
local W_BORR_FOR "borr_for_hsg borr_for_edu borr_for_med_exp borr_for_wedding borr_for_cons_exp borr_for_cds borr_for_biz borr_for_invsts borr_for_repay borr_for_vehicle borr_for_oth_prps"
* Aspirational India: savings instruments
local W_SAVING   "has_saving_in_fd has_saving_in_po has_saving_in_pf has_saving_in_life_ins has_saving_in_mf has_saving_in_shares has_saving_in_gold has_saving_in_real_estate has_saving_in_chtfund"
* Aspirational India: income group, housing and assets
local W_ASSETS   "inc_group has_access_to_electricity has_toilet_in_house two_wheelers_owned refrigerators_owned cattle_owned tractors_owned"
* CMIE household classifier groups (from Monthly Expenses)
local W_GROUPS   "age_group occupation_group edu_group gender_group size_group"
* household head = member slot 1 (Members Income + People of India)
local W_HEAD     "gender1 age1 edu1 occ1 marital1 empst1 castecat1 relig1 mwgt1"
* final list of the household-wave file
local COLS_W "`W_BORR_SRC' `W_BORR_FOR' `W_SAVING' `W_ASSETS' `W_GROUPS' `W_HEAD'"

* adult-member flags summarised over slots 1-20 into household variables;
* slot 1 of each flag is also kept as the head's own value (e.g. bank1)
local AGGVARS "bank cc kcc lic hins mobile hosp healthy medic"
* The loop below writes three lists of names for these 9 flags:
*   SLOTCOLS = the 20 slots of every flag, to read them from the parquet
*              parts (bank1 bank2 ... bank20 cc1 ... medic20)
*   AGG_HEAD = slot 1 of every flag = the household head (bank1 cc1 ...)
*   AGG_OUT  = the household summaries created later (any_bank n_bank
*              nm_bank sh_bank any_cc ...)
* Each pass adds names to the end of the list, so the local appears on both
* sides of the "=" (the usual way to build a list in a loop in Stata).
local SLOTCOLS ""
local AGG_HEAD ""
local AGG_OUT  ""
foreach v of local AGGVARS {
    forvalues s = 1/20 {
        local SLOTCOLS "`SLOTCOLS' `v'`s'"
    }
    local AGG_HEAD "`AGG_HEAD' `v'1"
    local AGG_OUT  "`AGG_OUT' any_`v' n_`v' nm_`v' sh_`v'"
}

* text variables of the wave file, encoded to labelled numbers at the end
* (a labelled number takes far less memory than a long string)
local ENCODE_W "inc_group age_group occupation_group edu_group gender_group size_group gender1 edu1 occ1 marital1 empst1 castecat1 relig1"

* all variables to read from the parquet parts (list uniq drops any name
* that appears in more than one list)
local COLS_ALL "`KEYS' `COLS_M' `COLS_W' `SLOTCOLS'"
local COLS : list uniq COLS_ALL
*---------------------------------------------------------------------------

*===========================================================================
* MAIN LOOP: read the monthly parquet parts one at a time
*   For each part (= one month):
*   a. read the selected variables (pq use) into the frame pq_scratch;
*   b. compute the household summaries of the member flags;
*   c. split the month into its two pieces: the household-MONTH piece is
*      appended to the monthly file (default frame); the household-WAVE
*      piece is appended to the frame wv_acc;
*   d. when a new wave starts, the finished wave in wv_acc (up to 4 months)
*      is reduced to one row per household and saved to a temporary file.
*   Working one month at a time (and one wave at a time for the wave file)
*   keeps in memory only what each step needs. A "frame" is an additional
*   dataset that Stata holds in memory next to the main one.
*===========================================================================
* list of parts, sorted so the months are read in calendar order
local files : dir "`PQFOLDER'" files "part_*.parquet"
local files : list sort files
local nfiles : list sizeof files
if `nfiles' == 0 {
    di as error "No parquet parts found in `PQFOLDER'"
    exit 601
}
di as text "Reading `nfiles' parquet parts one at a time..."

* pq_scratch: receives one monthly part at a time
capture frame drop pq_scratch
frame create pq_scratch
* wv_acc accumulates the rows of the CURRENT wave only (<= 4 months); when
* the wave changes it is reduced to one row per household and written to disk
capture frame drop wv_acc
frame create wv_acc

local started = 0
local ngood = 0
local badfiles ""
local cur_wave ""
local wave_files ""
* the two monthly pieces are overwritten every iteration (declared once so
* the temp folder does not fill up with 144 x 2 files)
tempfile onemonth onewave

local i = 0
foreach f of local files {
    local i = `i' + 1
    if mod(`i', 20) == 0 di as text "  ...`i' of `nfiles'"

    * read the part. -capture- lets the run continue if a part cannot be
    * read (e.g. a damaged file): the part is skipped and listed at the end,
    * so it can be rebuilt; the parts that were read are not affected.
    capture {
        frame pq_scratch {
            if "`COLS'" != "" {
                *import parquet `COLS' using "`PQFOLDER'/`f'", clear
				*I cannot use "import parquet" because I have Stata 17
				pq use `COLS' using "`PQFOLDER'/`f'", clear
            }
            else {
                *import parquet using "`PQFOLDER'/`f'", clear
				pq use "`PQFOLDER'/`f'", clear
            }
        }
    }
    if _rc {
        di as error "SKIPPING unreadable file: `f'  (r(`=_rc'))"
        local badfiles "`badfiles' `f'"
        continue
    }

    local ngood = `ngood' + 1

    * ---- household summaries of the member flags + split into two pieces ----
    * Outside -capture- on purpose: an error here must STOP the run, not be
    * reported as an unreadable file.
    frame pq_scratch {
        * For each flag v (e.g. bank), across the 20 slots of the household:
        * any_<v> = 1 if at least one adult member (15+) has the flag (max);
        * n_<v>   = number of adult members with the flag (sum);
        * nm_<v>  = number of adult members with information on the flag;
        * sh_<v>  = n_<v> / nm_<v>, share of adults with the flag.
        * any_<v>, n_<v> and sh_<v> are missing when no slot has information.
        * Example: 3 adults with bank1=1 bank2=0 bank3=. give any_bank=1,
        * n_bank=1, nm_bank=2, sh_bank=0.5.
        foreach v of local AGGVARS {
            local vl ""
            forvalues s = 1/20 {
                local vl "`vl' `v'`s'"
            }
            egen byte any_`v' = rowmax(`vl')
            egen byte n_`v'   = rowtotal(`vl'), missing
            * nm_<v> = number of adult members WITH information on the flag
            * (denominator of the share; can be below n_adults when some
            * adults have no People of India record)
            egen byte nm_`v'  = rownonmiss(`vl')
            * sh_<v> = share (0-1) of adult members with the flag, among those
            * with information; missing when no adult has information
            gen float sh_`v'  = n_`v' / nm_`v' if nm_`v' > 0
            * keep slot 1 (household head), drop slots 2-20
            forvalues s = 2/20 {
                drop `v'`s'
            }
        }

        * Split the month into the two pieces. preserve/restore keeps the
        * full month in memory while the first piece is saved, so the second
        * piece is taken from the same complete data.
        * (1) household-month piece
        preserve
            keep `KEYS' `COLS_M'
            save "`onemonth'", replace
        restore

        * (2) household-wave piece (still one row per household-MONTH here)
        keep `KEYS' `COLS_W' `AGG_HEAD' `AGG_OUT'
        save "`onewave'", replace

        * wave of this part (every row of a monthly part has the same wave)
        quietly summarize wave_no, meanonly
        local w = r(min)
    }

    * monthly file: accumulate in the default frame (as before)
    if `started' == 0 {
        use "`onemonth'", clear
        local started = 1
    }
    else {
        append using "`onemonth'"
    }

    * wave file: when the wave changes, reduce the finished wave to one row
    * per household and store it on disk.
    * Why one row is enough: the Aspirational India and People of India values
    * are the same in the 4 months of a wave (the build copies the wave value
    * into each month). The CMIE groups and the head's characteristics come
    * from monthly modules; the value of the household's first month WITH
    * member data is taken for the wave (a month without member data, e.g.
    * a month the members module did not record the household, would leave
    * those variables empty).
    if "`cur_wave'" != "" & "`w'" != "`cur_wave'" {
        frame wv_acc {
            * one row per household-wave: its first month WITH member data
            * (age1 present), otherwise its first month
            gen byte _nomem = missing(age1)
            bysort hh_id wave_no (_nomem month_date): keep if _n == 1
            drop _nomem
            tempfile wfile_`cur_wave'
            save "`wfile_`cur_wave''", replace
            clear
        }
        local wave_files "`wave_files' `wfile_`cur_wave''"
    }
    * add this month's wave piece to wv_acc (c(k) == 0 means the frame is
    * still empty, i.e. this is the first month of a new wave)
    frame wv_acc {
        if c(k) == 0 {
            use "`onewave'", clear
        }
        else {
            append using "`onewave'"
        }
    }
    local cur_wave "`w'"
}

* close the last wave: inside the loop a wave is saved only when the next
* wave starts, so the last wave of the panel is saved here, with the same rule
if "`cur_wave'" != "" {
    frame wv_acc {
        * one row per household-wave: its first month WITH member data
        * (age1 present), otherwise its first month
        gen byte _nomem = missing(age1)
        bysort hh_id wave_no (_nomem month_date): keep if _n == 1
        drop _nomem
        tempfile wfile_`cur_wave'
        save "`wfile_`cur_wave''", replace
        clear
    }
    local wave_files "`wave_files' `wfile_`cur_wave''"
}

frame drop pq_scratch
frame drop wv_acc

if `started' == 0 {
    di as error "No parquet part could be read successfully -- nothing to load."
    exit 601
}

di as result "Loaded `ngood' of `nfiles' parts successfully."
if `"`badfiles'"' != "" {
    di as error "-------------------------------------------------------------"
    di as error "The following part(s) were unreadable and were SKIPPED:"
    di as error "`badfiles'"
    di as error "Re-run build_focused_panel_parquet.do to rebuild them."
    di as error "-------------------------------------------------------------"
}

*===========================================================================
* (1) household-MONTH file (already in memory: the parts appended above).
* Steps 3-5 are those of the original version of this do-file.
*===========================================================================
* 3. Format month variable if present.
capture confirm variable month_date
if !_rc {
    format month_date %tm
}

* 4. Create panel id and xtset if possible.
capture confirm variable hh_id
if !_rc {
    capture drop hh_panel_id
    egen long hh_panel_id = group(hh_id)

    capture confirm variable month_date
    if !_rc {
        capture xtset hh_panel_id month_date
    }
}

* 5. Apply dictionary / labels if available.
capture noisily do "$CPHS_DOFILES/cphs_focused_dictionary.do"

compress
describe
di as result _newline "Household-month file: `=_N' rows."
save "`OUT_M'", replace

*---------------------------------------------------------------------------
* CHECK 1 -- special codes in the monthly money flows. CMIE may code "data
* not available" / "not applicable" as -99 / -100; if they appear they must
* be set to missing (in Merge_CHPS_and_shares.py) before averaging. Other negative
* values can be legitimate (e.g. business losses) and are only reported.
*---------------------------------------------------------------------------
capture noisily {
    di as result _newline "==== CHECK 1: special codes in monthly money flows (rows) ===="
    di as text %-30s "variable" %10s "-99" %10s "-100" %12s "other <0" %12s "missing" %12s "non-miss"
    foreach v of local FLOWS_M {
        quietly count if `v' == -99
        local c99 = r(N)
        quietly count if `v' == -100
        local c100 = r(N)
        quietly count if `v' < 0 & !inlist(`v', -99, -100)
        local cneg = r(N)
        quietly count if missing(`v')
        local cmiss = r(N)
        local cok = _N - `cmiss'
        di as text %-30s "`v'" as result %10.0fc `c99' %10.0fc `c100' %12.0fc `cneg' %12.0fc `cmiss' %12.0fc `cok'
    }
    di as text "Rows in the household-month file by wave:"
    tab wave_no
}

*===========================================================================
* (2) household-WAVE file: stack the temporary files saved wave by wave in
*     the main loop (one per wave, already one row per household)
*===========================================================================
clear
local first = 1
foreach wf of local wave_files {
    if `first' {
        use "`wf'", clear
        local first = 0
    }
    else {
        append using "`wf'"
    }
}

* one row per household-wave by construction; stop if that ever fails
isid hh_id wave_no
* the file is by wave: month_date (the month whose values were kept) is
* no longer needed
drop month_date

* encode the text variables to labelled numbers (one consistent coding for
* the whole file; empty strings become missing)
foreach v of local ENCODE_W {
    capture confirm string variable `v'
    if !_rc {
        tempvar enc
        * trim so "Married" and "Married " do not become two categories
        replace `v' = strtrim(`v')
        encode `v', gen(`enc') label(lb_`v')
        drop `v'
        rename `enc' `v'
    }
}

* labels (the dictionary also labels any_* / n_* and the head variables)
capture noisily do "$CPHS_DOFILES/cphs_focused_dictionary.do"

order hh_id wave_no
sort hh_id wave_no
compress
describe
di as result _newline "Household-wave file: `=_N' rows."
save "`OUT_W'", replace

*---------------------------------------------------------------------------
* CHECKS 2-5 on the household-wave file (read-only: the file is already saved)
*---------------------------------------------------------------------------
capture noisily {
    * CHECK 2 -- waves present (the test run must show 2 waves)
    di as result _newline "==== CHECK 2: household-waves by wave ===="
    tab wave_no

    * CHECK 3 -- variables that came out ENTIRELY missing (name not in the
    * raw files, or never answered): these need a decision before analysis
    di as result _newline "==== CHECK 3: variables entirely missing in the wave file ===="
    local nallmiss = 0
    foreach v of varlist _all {
        quietly count if !missing(`v')
        if r(N) == 0 {
            di as error "  ALL MISSING: `v'"
            local nallmiss = `nallmiss' + 1
        }
    }
    di as text "  `nallmiss' variable(s) entirely missing."

    * CHECK 4 -- coverage by wave (share non-missing) of key new variables;
    * shows e.g. whether SHG/MFI come combined or separately in each wave
    di as result _newline "==== CHECK 4: share non-missing by wave ===="
    local COVER "borr_frm_shg_mfi borr_frm_shg borr_frm_mfi borr_frm_nbfc borr_for_biz has_toilet_in_house two_wheelers_owned empst1 relig1 castecat1 marital1 hosp1 any_bank"
    local nmlist ""
    local k = 0
    foreach v of local COVER {
        local k = `k' + 1
        gen byte nm`k' = !missing(`v')
        label var nm`k' "`v'"
        local nmlist "`nmlist' nm`k'"
    }
    * one row per variable (numbered as in the list above)
    local k = 0
    foreach v of local COVER {
        local k = `k' + 1
        di as text "  nm`k' = `v'"
    }
    tabstat `nmlist', by(wave_no) statistics(mean) format(%4.2f) nototal
    drop `nmlist'

    * CHECK 5 -- yes/no flags outside 0/1, and negative asset counts / head age
    di as result _newline "==== CHECK 5: out-of-range values ===="
    local nbad = 0
    foreach v of varlist has_* borr_* any_* bank1 cc1 kcc1 lic1 hins1 mobile1 hosp1 healthy1 medic1 {
        quietly count if !missing(`v') & !inlist(`v', 0, 1)
        if r(N) > 0 {
            di as error "  `v': " r(N) " values not 0/1"
            local nbad = `nbad' + 1
        }
    }
    foreach v of varlist two_wheelers_owned refrigerators_owned cattle_owned tractors_owned age1 n_* {
        quietly count if `v' < 0
        if r(N) > 0 {
            di as error "  `v': " r(N) " negative values (CMIE code -99/-100?)"
            local nbad = `nbad' + 1
        }
    }
    foreach v of local AGGVARS {
        quietly count if !missing(sh_`v') & (sh_`v' < 0 | sh_`v' > 1)
        if r(N) > 0 {
            di as error "  sh_`v': " r(N) " shares outside [0,1]"
            local nbad = `nbad' + 1
        }
        quietly count if n_`v' > nm_`v' & !missing(n_`v', nm_`v')
        if r(N) > 0 {
            di as error "  n_`v' > nm_`v' in " r(N) " rows"
            local nbad = `nbad' + 1
        }
    }
    di as text "  `nbad' variable(s) with out-of-range values."
}

di as result _newline "Done. Send the log: `LOGFILE'"
log close
