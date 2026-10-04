*===========================================================================
* list_module_variables.do
*
* Lists every RAW variable available in each of the 5 CPHS source modules
* (Monthly Expenses, Household Income, Members Income, People of India,
* Aspirational India), using ONE sample raw file per module (the first
* month or wave). Output: $CPHS_TABLES/variables_<module>.txt
* Uses only Stata commands (unzipfile, import delimited), so it runs on
* Windows, Mac and Linux.
*
*===========================================================================

*version 18.0
version 17.0
clear
set more off
capture log close _all

* All folders are defined in run_cphs_panel.do (the master). Stop if this
* do-file is run on its own, so that nothing is read from or written to a
* wrong folder. (CPHS_PARQUET is the last folder the master defines.)
if "$CPHS_PARQUET" == "" {
    di as error "Folders not defined: run this do-file from run_cphs_panel.do."
    exit 198
}

capture mkdir "$CPHS_TEMP"
capture mkdir "$CPHS_TABLES"

log using "$CPHS_DOFILES/list_module_variables.log", replace text

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

local j = 0                                    // progress counter (modules done)
foreach m in expenses income members poi aspirational {
    if "`m'" == "expenses"     local outer "Monthly Expenses"
    if "`m'" == "income"       local outer "Household Income"
    if "`m'" == "members"      local outer "Members Income"
    if "`m'" == "poi"          local outer "People of India"
    if "`m'" == "aspirational" local outer "Aspirational India"

    * progress message: which module, out of 5
    local ++j
    di as result _newline "==== Module `j' of 5: `outer' ===="

    * scratch folder of this module (emptied first, in case an earlier run
    * stopped half-way)
    local work "$CPHS_TEMP/varlist_`m'"
    capture cphs_rmdir "`work'"
    capture mkdir "`work'"

    * ---- 1. unzip the module's zip with Stata's own -unzipfile- ----
    * (works on any operating system; the Unix tools unzip/head used before
    * do not exist on Windows). Inside there is one zip per month or wave,
    * in a subfolder named like the module, as in the build.
    cd "`work'"
    * progress message (unzipfile prints nothing while it works, and a
    * module zip can take a few minutes)
    di as text "   unzipping `outer'.zip ..."
    unzipfile "$CPHS_RAW/`outer'.zip", replace
    local nested : dir "`work'/`outer'" files "*.zip"
    local nested : list sort nested
    local first : word 1 of `nested'
    if "`first'" == "" {
        di as error "Could not find a nested zip inside `outer'.zip -- skipping."
        continue
    }

    * ---- 2. unzip ONLY the first monthly/wave zip (one csv file) ----
    capture mkdir "`work'/csv"
    cd "`work'/csv"
    di as text "   unzipping the first file, `first', and reading its variable names"   // progress message
    unzipfile "`work'/`outer'/`first'", replace
    local csvs : dir "`work'/csv" files "*.csv"
    local c : word 1 of `csvs'

    * ---- 3. read only the first rows: enough to get the variable names ----
    import delimited "`work'/csv/`c'", varnames(1) rowrange(:10) ///
        bindquote(strict) case(lower) clear

    di as txt "Source file: `first'"
    describe, short

    * ---- 4. write the list of variable names ----
    file open fh using "$CPHS_TABLES/variables_`m'.txt", write replace
    file write fh "Module: `outer'" _n "Source file: `first'" _n _n
    foreach v of varlist * {
        file write fh "`v'" _n
    }
    file close fh
    di as result "Variable list written to $CPHS_TABLES/variables_`m'.txt"

    * ---- 5. delete the unzipped files of this module ----
    cd "$CPHS_TEMP"
    capture cphs_rmdir "`work'"
    * progress message: modules finished so far
    di as result "   module `j' of 5 done"
}

di as result _newline "Done. See $CPHS_TABLES/variables_<module>.txt for each module's full raw variable list."
log close
