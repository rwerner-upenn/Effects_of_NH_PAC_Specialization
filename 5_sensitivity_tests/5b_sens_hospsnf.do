* Sensitivity Tests - Regressions
* Stratifying hospital-based SNFs (Table 7, columns 4 and 5)
cap log close
log using "$log_path/5b_sens_hospsnf_log_final.log", replace

********************************************************************************
// Initialize locals for use in regressions //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file_copyB.dta", clear

local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc"
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local ctrls_strat "hosp_los snf_in_chain snf_for_profit snf_bed_cnt i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"

********************************************************************************
// Stratified Regressions //
********************************************************************************
* hospital-based SNFs only
* SNF LOS and 90d payment variables
eststo clear
foreach y of varlist snf_los {
	eststo: ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_strat' died_in_snf (snf_pct_medicare_adj = `instr') if snf_hosp_based==1 & ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) ///
		first savefirst savefprefix(st1_)
}

* 3 and 4 (adds obs_days_90)
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	eststo: ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_strat' obs_days_90 (snf_pct_medicare_adj = `instr') if snf_hosp_based==1 & ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) ///
		first savefirst savefprefix(st1_)
}

estadd scalar F_stat = `e(widstat)': st1_snf_pct_medicare_adj

// mortality and readmission //

eststo: ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_strat' (snf_pct_medicare_adj = `instr') if snf_hosp_based==1 & ffs_ma_combo==1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) ///
	first savefirst savefprefix(st1pmtffs_)
// estadd scalar F_statpmt = `e(widstat)': st1pmt_snf_pct_medicare_adj

eststo: ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_strat' obs_days_30 (snf_pct_medicare_adj = `instr') if snf_hosp_based==1 & ffs_ma_combo==1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) ///
	first savefirst savefprefix(st1radmffs_)
// estadd scalar F_statradm = `e(widstat)': st1radm_snf_pct_medicare_adj


* non-hospital based SNFs
* SNF LOS and 90d payment outcomes
eststo clear
foreach y of varlist snf_los {
	eststo: ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_strat' died_in_snf (snf_pct_medicare_adj = `instr') if snf_hosp_based==0 & ffs_ma_combo==1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) ///
		first savefirst savefprefix(st1_)
}

foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	eststo: ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_strat' obs_days_90 (snf_pct_medicare_adj = `instr') if snf_hosp_based==0 & ffs_ma_combo==1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) ///
		first savefirst savefprefix(st1_)
}

estadd scalar F_stat = `e(widstat)': st1_snf_pct_medicare_adj

////// mortality and readmissions ///////

eststo: ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_strat' (snf_pct_medicare_adj = `instr') if snf_hosp_based==0 & ffs_ma_combo==1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) ///
	first savefirst savefprefix(st1pmtffs_)
// estadd scalar F_statpmt = `e(widstat)': st1pmt_snf_pct_medicare_adj

eststo: ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_strat' obs_days_30 (snf_pct_medicare_adj = `instr') if snf_hosp_based==0 & ffs_ma_combo==1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) ///
	first savefirst savefprefix(st1radmffs_)
// estadd scalar F_statradm = `e(widstat)': st1radm_snf_pct_medicare_adj

log close

