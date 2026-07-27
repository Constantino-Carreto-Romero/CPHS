*===========================================================================
* list_module_variables.do  (self-contained, doesn't unzip everything)
*
* Lists every RAW variable available in each of the 5 CPHS source modules
* (Monthly Expenses, Household Income, Members Income, People of India,
* Aspirational India), using ONE sample raw file per module.
*
*===========================================================================

version 18.0
clear
set more off
capture log close _all

global CPHS_ROOT "/Users/abhishekkumar/Library/CloudStorage/OneDrive-UniversityofSouthampton/CPHS"
*** I am using data from local stoarge as this is fast
global CPHS_RAW    "/Users/abhishekkumar/Desktop/CPHS"
global CPHS_BUILD  "$CPHS_ROOT/build"
global CPHS_TEMP   "$CPHS_BUILD/tmp"
global CPHS_LOGS   "$CPHS_BUILD/logs"
global CPHS_TABLES "$CPHS_ROOT/Tables"

capture mkdir "$CPHS_BUILD"
capture mkdir "$CPHS_TEMP"
capture mkdir "$CPHS_LOGS"
capture mkdir "$CPHS_TABLES"

log using "$CPHS_LOGS/list_module_variables.do.log", replace text

foreach m in expenses income members poi aspirational {
    if "`m'" == "expenses"     local outer "Monthly Expenses"
    if "`m'" == "income"       local outer "Household Income"
    if "`m'" == "members"      local outer "Members Income"
    if "`m'" == "poi"          local outer "People of India"
    if "`m'" == "aspirational" local outer "Aspirational India"

    di as result _newline "==== `outer' ===="

    local work "$CPHS_TEMP/varlist_`m'"
    capture shell rm -rf "`work'"
    capture mkdir "`work'"

    * ---- list contents WITHOUT extracting the whole archive ----
    local listing "`work'/listing.txt"
    shell unzip -Z1 "$CPHS_RAW/`outer'.zip" > "`listing'"

    import delimited using "`listing'", delimiter(",") varnames(nonames) ///
        stringcols(1) clear
    rename v1 fname
    keep if strpos(fname, ".zip") & !strpos(fname, "__MACOSX")
    local first = fname[1]

    if "`first'" == "" {
        di as error "Could not find a nested zip inside `outer'.zip -- skipping."
        continue
    }

    * ---- extract ONLY that one nested zip, not the other ~143 ----
    shell unzip -j "$CPHS_RAW/`outer'.zip" "`first'" -d "`work'"
    local nestedfile : dir "`work'" files "*.zip"
    local nestedfile : word 1 of `nestedfile'

    shell unzip -p "`work'/`nestedfile'" | head -n 1 > "`work'/header.csv"

    import delimited "`work'/header.csv", varnames(1) bindquote(strict) ///
        case(lower) clear

    di as txt "Source file: `first'"
    describe, short

    file open fh using "$CPHS_TABLES/variables_`m'.txt", write replace
    file write fh "Module: `outer'" _n "Source file: `first'" _n _n
    foreach v of varlist * {
        file write fh "`v'" _n
    }
    file close fh
    di as result "Variable list written to $CPHS_TABLES/variables_`m'.txt"

    cd "$CPHS_TEMP"
    capture shell rm -rf "`work'"
}

di as result _newline "Done. See $CPHS_TABLES/variables_<module>.txt for each module's full raw variable list."
log close
