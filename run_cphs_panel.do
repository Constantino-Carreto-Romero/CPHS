*===========================================================================
* run_cphs_panel.do  --  MASTER: builds the CPHS panel from scratch in one go
*
* Runs, in sequence and without manual intervention:
*   1. list_module_variables.do        (lists the variables available in each
*                                       raw CMIE module -> data/CPHS/Tables)
*   2. build_focused_panel_parquet.do  (raw CMIE zips -> monthly parquet parts, ~6-7 h)
*   3. load_parquet_selected.do        (parquet parts -> selected_cphs_panel_data.dta
*                                       + selected_cphs_wave_data.dta + CHECKS log)
* If a step stops with an error, the master stops too and the next steps are
* NOT run (so no file is built from an incomplete panel).
* Afterwards run Merge_CHPS_and_shares.py in Python.
*
* Logs (written next to the do-files, in code/):
*   list_module_variables.log
*   build_focused_panel_parquet.log
*   load_parquet_selected.log
*===========================================================================

clear all
set more off

*--------------------------- USER SETTINGS ---------------------------------
* All folders are defined HERE ONLY; the do-files called below use them.
* To run the panel on another computer, change only CPHS_PROJ (the project
* folder that contains data/ and code/).
global CPHS_PROJ    "C:/Users/HP/Documents/QMUL/Financial inclusion in India"
global CPHS_DOFILES "$CPHS_PROJ/code"             // do-files and their logs
global CPHS_ROOT    "$CPHS_PROJ/data/CPHS"        // CPHS data and output .dta files
global CPHS_RAW     "$CPHS_ROOT/Raw Files"        // raw CMIE zips (only read, never modified)
global CPHS_TEMP    "$CPHS_RAW/build_tmp"         // scratch files, created and deleted during the build
global CPHS_TABLES  "$CPHS_ROOT/Tables"           // variable lists and slot diagnostics

* 0 = FULL run (all 144 months); 1 = 2-month test (Apr-May 2014)
global CPHS_TEST 0
*--------------------------- USER SETTINGS ---------------------------------

* folder of the monthly parquet parts, and suffix of the output files. The
* test uses its own folder and "_test" files, so it never overwrites the
* full panel.
if $CPHS_TEST == 1 {
    global CPHS_PARQUET "$CPHS_ROOT/cphs_panel_parquet_test"
    global CPHS_SUFFIX  "_test"
}
else {
    global CPHS_PARQUET "$CPHS_ROOT/cphs_panel_parquet"
    global CPHS_SUFFIX  ""
}

* ---- step 1: list the variables available in each raw CMIE module ----
di as result _newline "=== MASTER: step 1/3 -- list_module_variables.do ==="
do "$CPHS_DOFILES/list_module_variables.do"

* ---- cphs_focused_dictionary.do: NOT run here (line commented out) ----
* This do-file only attaches labels to the variables of the data in memory;
* it does not create any file. load_parquet_selected.do (step 3) already
* runs it on each of the two files it saves, so running it here would have
* no effect (there is no panel in memory yet). It is listed so that all the
* do-files of the panel appear in this master.
*do "$CPHS_DOFILES/cphs_focused_dictionary.do"

* ---- step 2: build the monthly parquet parts ----
di as result _newline "=== MASTER: step 2/3 -- build_focused_panel_parquet.do ==="
do "$CPHS_DOFILES/build_focused_panel_parquet.do"

* ---- step 3: load the parts into the two analysis files (+ CHECKS) ----
di as result _newline "=== MASTER: step 3/3 -- load_parquet_selected.do ==="
do "$CPHS_DOFILES/load_parquet_selected.do"

di as result _newline "=== MASTER: DONE ==="
