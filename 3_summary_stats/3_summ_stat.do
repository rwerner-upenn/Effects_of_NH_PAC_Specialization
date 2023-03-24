cap log close
log using "$log_path/3_summ_stat_log.log", replace

/* This do-file generates summary statistics for the SNF claims sample
and tests for balance of covariates across the instrument */



********************************************************************************
// Descriptive statistics //
********************************************************************************
local ptdemo_no_ses "age_cnt female white black hispanic other dual_elig"
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based"
local dxs1 "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph"
local dxs2 "mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc"
local dist "mi_to_snf1 mi_to_snf2 mi_to_snf3 mi_to_snf4"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"
local ivdv "snf_pct_medicare_adj snf_los snf_pmt_pseudo pac_pmt_90 tot_pmt_90 death_30_hosp radm30"


use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
egen comorb_count = rowtotal(chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc)
replace radm30 = radm30 * 100
replace death_30_hosp = death_30_hosp * 100
replace death_30_hosp_new = death_30_hosp_new * 100
gen pct_med = snf_pct_medicare_adj

* Table 1 - sample descriptive statistics
tabstat snf_pct_medicare_adj, by(snf_pct_medicare_cat) stat(min max) col(stat)
tabstat snf_in_chain snf_for_profit snf_hosp_based snf_bed_cnt `ptdemo_no_ses' ///
	hosp_los comorb_count obs_days_30 obs_days_90 died_in_snf ///
	if ffs_ma_combo == 1, by(snf_pct_medicare_cat) stat(mean sd count) col(stat) nototal
* Number of unique nursing homes in each % Medicare category
forval i = 1/4 {
	distinct snf_prvdr_num if snf_pct_medicare_cat == `i' & ffs_ma_combo == 1
}
* Number of unique nursing homes overall
distinct snf_prvdr_num if ffs_ma_combo == 1
	
* Table 2 - outcome descriptive statistics
tabstat radm30 death_30_hosp_new snf_los index_snf_pay_90 subseq_pac_90 ///
	Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new if ffs_ma_combo == 1, ///
	by(snf_pct_medicare_cat) stat(mean sd) col(stat)


	
********************************************************************************
// IV statistics, including balance of covariates //
********************************************************************************
* Table 3 - instrument descriptive statistics
tabstat mi_to_snf1 mi_to_snf2 mi_to_snf3 mi_to_snf4 if ffs_ma_combo == 1, ///
	c(statistics) stat(mean sd)

* Table 5 - balance of covariates
bysort bene_zip: egen med_log_mi_to_snf4 = median(log_mi_to_snf4)
gen iv_group = 1 if log_mi_to_snf4 < med_log_mi_to_snf4 & !missing(log_mi_to_snf4)
replace iv_group = 2 if log_mi_to_snf4 == med_log_mi_to_snf4 & !missing(log_mi_to_snf4)
replace iv_group = 3 if log_mi_to_snf4 > med_log_mi_to_snf4 & !missing(log_mi_to_snf4)
label define iv_groupL 1 "< log dist" 2 "Med log dist" 3 "> log dist"
label values iv_group iv_groupL

local nh_char "snf_in_chain snf_for_profit snf_hosp_based snf_bed_cnt"
local pt_char "age_cnt female white black hispanic other dual_elig hosp_los comorb_count obs_days_30 obs_days_90 died_in_snf"
tabstat `nh_char' `pt_char' if ffs_ma_combo == 1, c(statistics) stat(mean sd count) by(iv_group) nototal
save "$proc_data_path/final_data_snfclaims_analysis_file.dta", replace

* Save copies of smaller analytic file for sensitivity tests running in parallel
keep snf_prvdr_num   renlfail             lytes                black                unemp_rate           Pmt_After_Hosp_90_sum_new ///
chf                  liver                bldloss              hispanic             obs_days_90          radm30 ///
valve                ulcer                anemdef              other                obs_days_30          log_mi_to_snf1 ///
pulmcirc             aids                 alcohol              bene_zip_num         age_cnt              log_mi_to_snf2 ///
perivasc             lymph                drug                 hosp_los             snf_in_chain         log_mi_to_snf3 ///
para                 mets                 psych                snf_los              snf_for_profit        log_mi_to_snf4 ///
neuro                tumor                depress              dual_elig            snf_pct_medicare_adj snf_hosp_based  ///
chrnlung             arth                 htnc                 snf_bed_cnt          hosp_drgcd		 died_in_snf ///
dm                   coag                 snf_admsn_year       rural                Pmt_After_Hosp_90_sum_new_Acute	white ///
dmcx                 obese                ffs_ma_combo          pct_pov              death_30_hosp	 snf_pct_medicare_cat ///
hypothy              wgthloss             female               med_hshld_inc        subseq_pac_90	 index_snf_pay_90 ///
death_30_hosp_new
compress
save "$proc_data_path/final_data_snfclaims_analysis_file_copyA.dta", replace
save "$proc_data_path/final_data_snfclaims_analysis_file_copyB.dta", replace
save "$proc_data_path/final_data_snfclaims_analysis_file_copyC.dta", replace
save "$proc_data_path/final_data_snfclaims_analysis_file_copyD.dta", replace
save "$proc_data_path/final_data_snfclaims_analysis_file_copyE.dta", replace
save "$proc_data_path/final_data_snfclaims_analysis_file_copyF.dta", replace



********************************************************************************
// Create datasets for manuscript figures //
********************************************************************************
* Data for Figure 2 - % of Patients Admitted to Most Specialized SNF by Distance to SNF
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
keep if ffs_ma_combo == 1
gen spec_snf_adm_flag = cond(snf_pct_medicare_cat==4,1,0)
bysort bene_zip iv_group: egen prop_adm_cat4=mean(spec_snf_adm_flag)
keep bene_zip med_log_mi_to_snf4 iv_group prop_adm_cat4
duplicates drop
export delimited using "$graph_path/iv_figure_data.csv", replace

* Data for Appendix Figure 1a - share of nursing homes by year and quartile of PAC specialization
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
keep snf_prvdr_num snf_admsn_year snf_pct_medicare_cat
duplicates drop
gen cat1 = snf_pct_medicare_cat == 1
gen cat2 = snf_pct_medicare_cat == 2
gen cat3 = snf_pct_medicare_cat == 3
gen cat4 = snf_pct_medicare_cat == 4
tabstat cat1 cat2 cat3 cat4, by(snf_admsn_year) stat(mean) col(stat) nototal
export delimited using "$table_path/ffs_samp_snf_prvdr_nums.csv", replace

* Data for Appendix Figure 1b - share of nursing home TM admissions by year and quartile of PAC specialization
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
keep if ffs_ma_combo==1
bysort snf_admsn_year snf_pct_medicare_cat: gen admcount=_N
keep snf_admsn_year snf_pct_medicare_cat admcount
duplicates drop
sort snf_admsn_year snf_pct_medicare_cat
by snf_admsn_year: egen admtot = total(admcount)
gen admshare = 100 * admcount / admtot
list snf_admsn_year snf_pct_medicare_cat admshare
export delimited using "$graph_path/yr_qrt_ffs_adm_counts.csv", replace



********************************************************************************
// Misc statistics for manuscript //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear

* Number of unique SNFs that change specialization quartile at least once
keep snf_prvdr_num snf_admsn_year snf_pct_medicare_cat snf_pct_medicare_adj
duplicates drop
sort snf_prvdr_num snf_admsn_year
tab snf_admsn_year
by snf_prvdr_num: egen quart_min = min(snf_pct_medicare_cat)
by snf_prvdr_num: egen quart_max = max(snf_pct_medicare_cat)
distinct snf_prvdr_num
distinct snf_prvdr_num if quart_min != quart_max

/* Number of nursing homes that enter and exit during 2011-2018 */
by snf_prvdr_num: egen first_year = min(snf_admsn_year)
by snf_prvdr_num: egen last_year = max(snf_admsn_year)
gen new_nh = cond(first_year != 2011, 1, 0)
gen exiting_nh = cond(last_year != 2018, 1, 0)
gen staying_nh = new_nh != 1 & exiting_nh != 1
by snf_prvdr_num: egen num_years = count(snf_admsn_year)
* Sample period of 8 years
replace new_nh = 0 if num_years >= 4 & new_nh == 1 & exiting_nh == 1
replace exiting_nh = 0 if num_years < 4 & new_nh == 1 & exiting_nh == 1
egen check = rowtotal(new_nh staying_nh exiting_nh)
* All values of check should be equal to 1
summ check
distinct snf_prvdr_num if new_nh == 1
distinct snf_prvdr_num if exiting_nh == 1


********************************************************************************
********************************************************************************
log close
