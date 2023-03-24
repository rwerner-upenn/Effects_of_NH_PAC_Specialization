cap log close
log using "$log_path/4_run_regressions_log.log", replace

/* This do-file runs our primary regressions */



********************************************************************************
// Initialize locals for use in regressions //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc"
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"



********************************************************************************
// OLS with beneficiary ZIP FEs //
********************************************************************************
mat define main_results = J(14, 2, .)
mat colnames main_results = ols twosls

* 30-day readmissions, FFS sample
reghdfe radm30 snf_pct_medicare_adj `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
mat main_results[1, 1] = round(_b[snf_pct_medicare_adj], 0.001)
mat main_results[2, 1] = round(_se[snf_pct_medicare_adj], 0.001)

* 30-day mortality, FFS sample
reghdfe death_30_hosp_new snf_pct_medicare_adj `ptdemo_no_ses' `dxs' `ctrls_base' if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
mat main_results[3, 1] = round(_b[snf_pct_medicare_adj], 0.001)
mat main_results[4, 1] = round(_se[snf_pct_medicare_adj], 0.001)

* Length of stay, FFS sample
reghdfe snf_los snf_pct_medicare_adj `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
mat main_results[5, 1] = round(_b[snf_pct_medicare_adj], 0.001)
mat main_results[6, 1] = round(_se[snf_pct_medicare_adj], 0.001)
		
* 90-day payment outcomes, FFS sample
local count = 7
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	local count2 = `count' + 1
	reghdfe `y' snf_pct_medicare_adj `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat main_results[`count', 1] = round(_b[snf_pct_medicare_adj], 0.01)
	mat main_results[`count2', 1] = round(_se[snf_pct_medicare_adj], 0.01)
	local count = `count' + 2
}



********************************************************************************
// 2SLS with beneficiary ZIP FEs //
********************************************************************************
* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
mat main_results[1, 2] = round(_b[snf_pct_medicare_adj], 0.001)
mat main_results[2, 2] = round(_se[snf_pct_medicare_adj], 0.001)

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
mat main_results[3, 2] = round(_b[snf_pct_medicare_adj], 0.001)
mat main_results[4, 2] = round(_se[snf_pct_medicare_adj], 0.001)

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
mat main_results[5, 2] = round(_b[snf_pct_medicare_adj], 0.001)
mat main_results[6, 2] = round(_se[snf_pct_medicare_adj], 0.001)

* 90-day payment outcomes, FFS sample
local count = 7
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	local count2 = `count' + 1
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
	mat main_results[`count', 2] = round(_b[snf_pct_medicare_adj], 0.01)
	mat main_results[`count2', 2] = round(_se[snf_pct_medicare_adj], 0.01)
	local count = `count' + 2
}

* Table 6 - main regression results, OLS and 2SLS with ZIP FEs
clear
mat list main_results
svmat main_results, names(col)
gen var_name = ""
replace var_name = "30d readmissions" if _n == 1
replace var_name = "30d mortality" if _n == 3
replace var_name = "SNF length of stay" if _n == 5
replace var_name = "90d index SNF payment" if _n == 7
replace var_name = "90d subsequent PAC payment" if _n == 9
replace var_name = "90d rehospitalization payment" if _n == 11
replace var_name = "90d total Part A payment" if _n == 13

* Add parentheses for SEs
foreach var of varlist ols twosls {
	gen `var'_2 = string(`var')
	replace `var'_2 = `var'_2 + "0" if inrange(_n, 1, 6) & strlen(substr(`var'_2, strpos(`var'_2, "."), .)) == 3
	replace `var'_2 = `var'_2 + "0" if inrange(_n, 7, 14) & strlen(substr(`var'_2, strpos(`var'_2, "."), .)) == 2
	replace `var'_2 = "(" + `var'_2 + ")" if inlist(_n, 2, 4, 6, 8, 10, 12, 14)
	drop `var'
	rename `var'_2 `var'
}

order var_name ols twosls
label var var_name " "
label var ols "OLS"
label var twosls "2SLS"
export excel using "$table_path/table6_mainresults", firstrow(varlabels) replace


	
********************************************************************************
// 2SLS with beneficiary ZIP and SNF FEs (Table 8, column 2) //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear

* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num snf_prvdr_num) cluster(snf_prvdr_num)

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num snf_prvdr_num) cluster(snf_prvdr_num)

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num snf_prvdr_num) cluster(snf_prvdr_num)

* 90-day payment outcomes, FFS sample
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num snf_prvdr_num) cluster(snf_prvdr_num)
}

	
********************************************************************************
********************************************************************************
log close


