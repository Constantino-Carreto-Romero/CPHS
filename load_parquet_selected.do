*===========================================================================
* load_parquet_selected.do   --  Load selected CPHS parquet variables into
*                                 Stata using native `import parquet`.

clear all
set more off

** Please change user setting and cols on line 22 to generate the panel you wish to analyse. variables are given in cphs_focused_dictionary.do
** all variable list is avilable in Tables folder.
** if you need more variabled which are not available in cphs_focused_dictionary.do but available in Tables, please let me know and I will generate the parquets agains. 

*--------------------------- USER SETTINGS ---------------------------------

global CPHS_ROOT "/Users/abhishekkumar/Library/CloudStorage/OneDrive-UniversityofSouthampton/CPHS"

*--------------------------- USER SETTINGS ---------------------------------


local PQFOLDER "$CPHS_ROOT/cphs_panel_parquet"

* Variables to pull. Leave empty ("") to load every column.
local COLS "hh_id month_date wave_no state region_type hh_size n_adults tot_inc tot_exp bank1 occ1 minc_all1 has_borr borr_frm_bank borr_frm_lender has_saving_in_fd"
*---------------------------------------------------------------------------

local files : dir "`PQFOLDER'" files "part_*.parquet"
local files : list sort files
local nfiles : list sizeof files
if `nfiles' == 0 {
    di as error "No parquet parts found in `PQFOLDER'"
    exit 601
}
di as text "Reading `nfiles' parquet parts one at a time..."

capture frame drop pq_scratch
frame create pq_scratch

local started = 0
local ngood = 0
local badfiles ""

local i = 0
foreach f of local files {
    local i = `i' + 1
    if mod(`i', 20) == 0 di as text "  ...`i' of `nfiles'"

    capture {
        frame pq_scratch {
            if "`COLS'" != "" {
                import parquet `COLS' using "`PQFOLDER'/`f'", clear
            }
            else {
                import parquet using "`PQFOLDER'/`f'", clear
            }
        }
    }
    if _rc {
        di as error "SKIPPING unreadable file: `f'  (r(`=_rc'))"
        local badfiles "`badfiles' `f'"
        continue
    }

    local ngood = `ngood' + 1
    tempfile onemonth
    frame pq_scratch: save `onemonth', replace

    if `started' == 0 {
        use `onemonth', clear
        local started = 1
    }
    else {
        append using `onemonth'
    }
}

frame drop pq_scratch

if `started' == 0 {
    di as error "No parquet part could be read successfully -- nothing to load."
    exit 601
}

di as result "Loaded `ngood' of `nfiles' parts successfully."
if `"`badfiles'"' != "" {
    di as error "-------------------------------------------------------------"
    di as error "The following part(s) were unreadable and were SKIPPED:"
    di as error "`badfiles'"
    di as error "Rebuild just these months by setting CPHS_FIRST_SOURCE_DATE /"
    di as error "CPHS_LAST_SOURCE_DATE to the corresponding date(s) and"
    di as error "re-running build_focused_panel_parquet.do."
    di as error "-------------------------------------------------------------"
}

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
capture do "$CPHS_ROOT/StataDoFiles/cphs_focused_dictionary.do"

describe
di as result _newline "Loaded `=_N' rows."
di as result "Variables requested: `COLS'"


save  "$CPHS_ROOT/selected_cphs_panel_data.dta", replace
