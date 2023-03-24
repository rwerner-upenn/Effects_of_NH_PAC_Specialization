* sensitivity tests
* including discharging hospital FEs (Table 8, column 3)
cap log close
log using "$log_path/5j_sens_hosp_fe_log_final.log", replace

********************************************************************************
// Initialize locals for use in regressions //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
* adds in hospital FEs
keep if ffs_ma_combo==1 

local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc"
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"

egen hospid_num=group(HOSP_PRVDRNUM), label
* FEs for discharging hospital

* SNF LOS and 90d payment outcomes
eststo clear
foreach y of varlist snf_los {
	eststo: ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (snf_pct_medicare_adj = `instr'), ///
		absorb(hosp_drgcd bene_zip_num hospid_num) cluster(hospid_num) ///
		first savefirst savefprefix(st1_)
}

foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	eststo: ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (snf_pct_medicare_adj = `instr'), ///
		absorb(hosp_drgcd bene_zip_num hospid_num) cluster(hospid_num) ///
		first savefirst savefprefix(st1_)
}

estadd scalar F_stat = `e(widstat)': st1_snf_pct_medicare_adj

///mortality and readmission //

eststo: ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (snf_pct_medicare_adj = `instr'), ///
	absorb(hosp_drgcd bene_zip_num hospid_num) cluster(hospid_num) ///
	first savefirst savefprefix(st1pmtffs_)
// estadd scalar F_statpmt = `e(widstat)': st1pmt_snf_pct_medicare_adj

eststo: ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (snf_pct_medicare_adj = `instr'), ///
	absorb(hosp_drgcd bene_zip_num hospid_num) cluster(hospid_num) ///
	first savefirst savefprefix(st1radmffs_)
// estadd scalar F_statradm = `e(widstat)': st1radm_snf_pct_medicare_adj

log close


