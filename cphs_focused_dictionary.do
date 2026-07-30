*===========================================================================
* cphs_focused_dictionary.do

* ---- value label for the 0/1 financial-inclusion flags ----
capture label define yesno 0 "No" 1 "Yes", replace

* ---- keys / identifiers ----
capture label var hh_id        "CPHS household identifier (string, stable over time)"
capture label var hh_panel_id  "Numeric household id for xtset"
capture label var month_date   "Calendar month (Stata monthly date, %tm)"
capture label var wave_no      "CPHS four-month wave number (1=Jan-Apr 2014 ... 37=Jan-Apr 2026)"

* ---- geography ----
capture label var state        "State"
capture label var hr           "Homogeneous region (CMIE)"
capture label var district     "District"
capture label var region_type  "Rural / Urban"
capture label var stratum      "Sampling stratum"
capture label var psu_id       "Primary sampling unit id"

* ---- survey quality / weights (from Monthly Expenses) ----
capture label var response_status "Monthly Expenses response status"
capture label var nr_reason       "Non-response reason"
capture label var r_hh_wgt_ms     "Household monthly survey weight (revised)"
capture label var hh_wgt_ms       "Household monthly survey weight (original)"
capture label var r_hh_wgt_w      "Household wave survey weight (revised)"

* ---- CMIE household classifier groups (based on the household head) ----
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

* ---- household financial inclusion (Aspirational India, wave -> month) ----
capture label var has_borr                  "Household has any borrowing"
capture label var borr_frm_bank             "Borrowed from a bank"
capture label var borr_frm_lender           "Borrowed from a moneylender"
capture label var borr_frm_shg_mfi          "Borrowed from SHG / MFI"
capture label var borr_frm_rel_frnds        "Borrowed from relatives / friends"
capture label var borr_frm_oth_srcs         "Borrowed from other sources"
capture label var has_saving_in_fd          "Has savings in fixed deposit"
capture label var has_saving_in_po          "Has savings in post office"
capture label var has_saving_in_pf          "Has savings in provident fund"
capture label var has_saving_in_life_ins    "Has savings in life insurance"
capture label var has_saving_in_mf          "Has savings in mutual funds"
capture label var has_saving_in_shares      "Has savings in shares"
capture label var has_saving_in_gold        "Has savings in gold"
capture label var has_saving_in_real_estate "Has savings in real estate"
capture label var has_access_to_electricity "Has access to electricity"

foreach v in has_borr borr_frm_bank borr_frm_lender borr_frm_shg_mfi ///
    borr_frm_rel_frnds borr_frm_oth_srcs has_saving_in_fd has_saving_in_po ///
    has_saving_in_pf has_saving_in_life_ins has_saving_in_mf has_saving_in_shares ///
    has_saving_in_gold has_saving_in_real_estate has_access_to_electricity {
    capture label values `v' yesno
}

* ---- per-member columns, slots 1-10 (slot 1 = head, then oldest first) ----
* gender# age# edu# occ# minc_all# minc_wage#  +  bank# cc# kcc# demat# pf# lic# hins# mobile#
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
    foreach v in bank cc kcc demat pf lic hins mobile {
        capture label values `v'`s' yesno
    }
}

di as result "Labels applied. Run  describe  or  codebook, compact  to view the dictionary."
