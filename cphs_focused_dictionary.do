*===========================================================================
* cphs_focused_dictionary.do  --  variable labels of the CPHS panel
*
* What it does: attaches a descriptive label to every variable of the CPHS
* panel, and the "No"/"Yes" value label to the 0/1 flags. It does not create,
* drop or change any data.
*
* Who runs it: it is NOT run on its own. load_parquet_selected.do calls it
* just before saving each of its two output files, and Append
* cphs_wave_merged.do calls it on the final base.
*
* Why every line starts with -capture-: one dictionary serves files that
* contain different variables. -capture- makes Stata skip, without an error,
* the label of any variable that is not in the data currently in memory.
*===========================================================================

* ---- value label "yesno" (0 = No, 1 = Yes), attached below to all 0/1 flags ----
capture label define yesno 0 "No" 1 "Yes", replace

* ---- keys / identifiers ----
capture label var hh_id        "CPHS household identifier (string, stable over time)"
capture label var hh_panel_id  "Numeric household id for xtset"
capture label var month_date   "Calendar month (Stata monthly date, %tm)"
capture label var wave_no      "CPHS four-month wave number (1=Jan-Apr 2014 ... 36=Sep-Dec 2025)"

* ---- geography ----
capture label var state        "State"
capture label var hr           "Homogeneous region (CMIE)"
capture label var district     "District"
capture label var region_type  "Rural / Urban"
capture label var stratum      "Sampling stratum"
capture label var psu_id       "Primary sampling unit id"

* ---- interview status and sampling weights (Monthly Expenses module) ----
capture label var response_status "Monthly Expenses response status"
capture label var nr_reason       "Non-response reason"
capture label var r_hh_wgt_ms     "Household monthly survey weight (revised)"
capture label var hh_wgt_ms       "Household monthly survey weight (original)"
capture label var r_hh_wgt_w      "Household wave survey weight (revised)"

* ---- CMIE household groups: categories CMIE assigns to each household ----
capture label var age_group        "Head age group (CMIE)"
capture label var occupation_group "Head occupation group (CMIE)"
capture label var edu_group        "Head education group (CMIE)"
capture label var gender_group     "Head gender group (CMIE)"
capture label var size_group       "Household size group (CMIE)"
capture label var inc_group        "Household income group (CMIE, from Aspirational India)"

* ---- household composition ----
capture label var hh_size  "Number of current household members"
capture label var n_adults "Number of members aged over 14"

* ---- income (Household Income module) ----
capture label var tot_inc                      "Total household income (Rs/month)"
capture label var inc_of_all_mems_frm_all_srcs "Income of all members from all sources"
capture label var inc_of_all_mems_frm_wages    "Income of all members from wages"
capture label var inc_of_hh_frm_all_srcs       "Household income from all sources"
capture label var inc_of_hh_frm_rent           "Household income from rent"
capture label var inc_of_hh_frm_self_prodn     "Household income from self-production"
capture label var inc_of_hh_frm_pvt_trf        "Household income from private transfers"
capture label var inc_of_hh_frm_biz_profit     "Household income from business profit"
capture label var inc_of_all_mems_frm_interest "Income of all members from interest"
capture label var inc_of_hh_frm_govt_trf       "Household income from government transfers (incl. DBT)"

* ---- expenditure group totals (Monthly Expenses module, Rs/month) ----
capture label var tot_exp                    "Total monthly expenditure"
capture label var adj_tot_exp                "Adjusted total monthly expenditure"
capture label var m_exp_food                 "Expenditure: food"
capture label var m_exp_intoxicants          "Expenditure: intoxicants (tobacco, liquor)"
capture label var m_exp_clothing_n_footwear  "Expenditure: clothing & footwear"
capture label var m_exp_cosmetic_n_toiletries "Expenditure: cosmetics & toiletries"
capture label var m_exp_appliances           "Expenditure: appliances"
capture label var m_exp_restaurants          "Expenditure: restaurants"
capture label var m_exp_recreation           "Expenditure: recreation"
capture label var m_exp_bills_n_rent         "Expenditure: bills & rent"
capture label var m_exp_house_rent           "Expenditure: house rent"
capture label var m_exp_power_n_fuel         "Expenditure: power & fuel"
capture label var m_exp_transport            "Expenditure: transport"
capture label var m_exp_communication_n_info "Expenditure: communication & information"
capture label var m_exp_edu                  "Expenditure: education"
capture label var m_exp_health               "Expenditure: health"
capture label var m_exp_health_ins_premium   "Expenditure: health insurance premium"
capture label var m_exp_all_emis             "Expenditure: all EMIs"
capture label var m_exp_emi_for_house        "Expenditure: EMI for house"
capture label var m_exp_emi_for_vehicle      "Expenditure: EMI for vehicle"
capture label var m_exp_emi_for_durables     "Expenditure: EMI for consumer durables"
capture label var m_exp_misc                 "Expenditure: miscellaneous"
capture label var m_exp_remittances_sent     "Expenditure: remittances sent"

* ---- borrowing, savings and housing: yes/no questions answered once per
* ---- wave (four months) in the Aspirational India module ----
capture label var has_borr                  "Household has any borrowing"
capture label var borr_frm_bank             "Borrowed from a bank"
capture label var borr_frm_lender           "Borrowed from a moneylender"
capture label var borr_frm_shg_mfi          "Borrowed from SHG / MFI"
capture label var borr_frm_rel_frnds        "Borrowed from relatives / friends"
capture label var borr_frm_oth_srcs         "Borrowed from other sources"
* Loans from self-help groups (SHG) and microfinance institutions (MFI): the
* 2014 raw files ask about both together (borr_frm_shg_mfi, labelled above);
* later raw files ask about each one separately (borr_frm_shg, borr_frm_mfi).
* Both versions are labelled. The lines below also cover the other lenders
* that only appear in later raw files.
capture label var borr_frm_shg              "Borrowed from a self-help group (SHG)"
capture label var borr_frm_mfi              "Borrowed from a microfinance institution (MFI)"
capture label var borr_frm_nbfc             "Borrowed from an NBFC"
capture label var borr_frm_chtfund          "Borrowed from a chit fund"
capture label var borr_frm_shops            "Borrowed from shops (store credit)"
capture label var borr_frm_cc               "Borrowed on a credit card"
* purpose of the loans (whatever the lender)
capture label var borr_for_hsg              "Borrowed for housing"
capture label var borr_for_edu              "Borrowed for education"
capture label var borr_for_med_exp          "Borrowed for medical expenses"
capture label var borr_for_wedding          "Borrowed for a wedding"
capture label var borr_for_cons_exp         "Borrowed for consumption expenses"
capture label var borr_for_cds              "Borrowed for consumer durables"
capture label var borr_for_biz              "Borrowed for business"
capture label var borr_for_invsts           "Borrowed for investments"
capture label var borr_for_repay            "Borrowed to repay other debt"
capture label var borr_for_vehicle          "Borrowed for a vehicle"
capture label var borr_for_oth_prps         "Borrowed for other purposes"
capture label var has_saving_in_fd          "Has savings in fixed deposit"
capture label var has_saving_in_po          "Has savings in post office"
capture label var has_saving_in_pf          "Has savings in provident fund"
capture label var has_saving_in_life_ins    "Has savings in life insurance"
capture label var has_saving_in_mf          "Has savings in mutual funds"
capture label var has_saving_in_shares      "Has savings in shares"
capture label var has_saving_in_gold        "Has savings in gold"
capture label var has_saving_in_real_estate "Has savings in real estate"
capture label var has_saving_in_chtfund     "Has savings in a chit fund"
capture label var has_access_to_electricity "Has access to electricity"
capture label var has_toilet_in_house       "Has a toilet in the house"

* ---- household assets: number of items owned (Aspirational India module).
* ---- These are counts, not yes/no, so they get no value label ----
capture label var two_wheelers_owned  "Number of two-wheelers owned"
capture label var refrigerators_owned "Number of refrigerators owned"
capture label var cattle_owned        "Number of cattle owned"
capture label var tractors_owned      "Number of tractors owned"

* attach the "yesno" value label to every 0/1 household flag listed above
foreach v in has_borr borr_frm_bank borr_frm_lender borr_frm_shg_mfi ///
    borr_frm_rel_frnds borr_frm_oth_srcs has_saving_in_fd has_saving_in_po ///
    has_saving_in_pf has_saving_in_life_ins has_saving_in_mf has_saving_in_shares ///
    has_saving_in_gold has_saving_in_real_estate has_access_to_electricity ///
    borr_frm_shg borr_frm_mfi borr_frm_nbfc borr_frm_chtfund borr_frm_shops borr_frm_cc ///
    borr_for_hsg borr_for_edu borr_for_med_exp borr_for_wedding borr_for_cons_exp ///
    borr_for_cds borr_for_biz borr_for_invsts borr_for_repay borr_for_vehicle ///
    borr_for_oth_prps has_saving_in_chtfund has_toilet_in_house {
    capture label values `v' yesno
}

* ---- member variables. The build stores the adult members (age 15+) of each
* ---- household side by side, in "slots" numbered 1 to 20: the number at the
* ---- end of the name is the member's slot. Slot 1 is the household head;
* ---- slots 2-20 are the other adults, from oldest to youngest. Example:
* ---- bank1 = the head has a bank account, bank2 = the oldest other adult has one.
* ---- The final files keep slot 1 only (slots 2-20 are summarised into the
* ---- household totals labelled at the end of this file).
* Variables per slot: gender age edu occ minc_all minc_wage (Members Income);
* bank cc kcc demat pf lic hins mobile mwgt marital empst castecat relig
* hosp healthy medic (People of India).
forvalues s = 1/20 {
    capture label var gender`s'    "Member `s': gender (slot `s' = head/older first)"
    capture label var age`s'       "Member `s': age in years"
    capture label var edu`s'       "Member `s': education"
    capture label var occ`s'       "Member `s': occupation / activity (nature_of_occupation)"
    capture label var minc_all`s'  "Member `s': income from all sources (Rs/month)"
    capture label var minc_wage`s' "Member `s': income from wages (Rs/month)"
    capture label var bank`s'      "Member `s': has bank account"
    capture label var cc`s'        "Member `s': has credit card"
    capture label var kcc`s'       "Member `s': has Kisan credit card"
    capture label var demat`s'     "Member `s': has demat account"
    capture label var pf`s'        "Member `s': has provident fund account"
    capture label var lic`s'       "Member `s': has LIC policy"
    capture label var hins`s'      "Member `s': has health insurance"
    capture label var mobile`s'    "Member `s': has mobile phone"
	capture label var mwgt`s'      "Member `s': wave weight, age 15+ (revised)"
    capture label var marital`s'   "Member `s': marital status"
    capture label var empst`s'     "Member `s': employment status"
    capture label var castecat`s'  "Member `s': caste category"
    capture label var relig`s'     "Member `s': religion"
    capture label var hosp`s'      "Member `s': hospitalised"
    capture label var healthy`s'   "Member `s': is healthy"
    capture label var medic`s'     "Member `s': on regular medication"
    * the yes/no member variables of this slot get the "yesno" value label
    foreach v in bank cc kcc demat pf lic hins mobile hosp healthy medic {
        capture label values `v'`s' yesno
    }
}

* ---- household totals of the adult-member yes/no variables, computed in
* ---- load_parquet_selected.do from slots 1-20. For each variable <v>
* ---- (bank, cc, kcc, lic, hins, mobile, hosp, healthy, medic):
*   any_<v> = 1 if at least one adult member answers "yes", 0 otherwise
*   n_<v>   = number of adult members who answer "yes"
*   nm_<v>  = number of adult members with an answer (yes or no)
*   sh_<v>  = n_<v> / nm_<v>, the share of adult members who answer "yes"
capture label var any_bank    "Any adult member has a bank account"
capture label var n_bank      "Number of adult members with a bank account"
capture label var any_cc      "Any adult member has a credit card"
capture label var n_cc        "Number of adult members with a credit card"
capture label var any_kcc     "Any adult member has a Kisan credit card"
capture label var n_kcc       "Number of adult members with a Kisan credit card"
capture label var any_lic     "Any adult member has an LIC policy"
capture label var n_lic       "Number of adult members with an LIC policy"
capture label var any_hins    "Any adult member has health insurance"
capture label var n_hins      "Number of adult members with health insurance"
capture label var any_mobile  "Any adult member has a mobile phone"
capture label var n_mobile    "Number of adult members with a mobile phone"
capture label var any_hosp    "Any adult member hospitalised"
capture label var n_hosp      "Number of adult members hospitalised"
capture label var any_healthy "Any adult member reported healthy"
capture label var n_healthy   "Number of adult members reported healthy"
capture label var any_medic   "Any adult member on regular medication"
capture label var n_medic     "Number of adult members on regular medication"
* any_<v> is a yes/no variable: attach the "yesno" value label
foreach v in bank cc kcc lic hins mobile hosp healthy medic {
    capture label values any_`v' yesno
}

* Labels of nm_<v> and sh_<v>, written in one loop instead of 18 lines.
* d_<v> holds the words that describe each variable, e.g. d_bank = "a bank
* account", so the loop builds "Share (0-1) of adult members with a bank account".
local d_bank    "a bank account"
local d_cc      "a credit card"
local d_kcc     "a Kisan credit card"
local d_lic     "an LIC policy"
local d_hins    "health insurance"
local d_mobile  "a mobile phone"
local d_hosp    "hospitalised"
local d_healthy "reported healthy"
local d_medic   "on regular medication"
foreach v in bank cc kcc lic hins mobile hosp healthy medic {
    * health variables read better with "who are" ("... who are hospitalised")
    local verb "with"
    if inlist("`v'", "hosp", "healthy", "medic") local verb "who are"
    capture label var nm_`v' "Number of adult members with information on: `d_`v''"
    capture label var sh_`v' "Share (0-1) of adult members `verb' `d_`v''"
}

di as result "Labels applied. Run  describe  or  codebook, compact  to view the dictionary."
