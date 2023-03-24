* Sensitivity Tests - Regressions
* Non-linear operationalization of the endogenous treatment variable (Appendix Table 5)
cap log close
log using "$log_path/5a_sens_nonlin_log_final.log", replace

********************************************************************************
// Initialize locals for use in regressions //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file_copyA.dta", clear

* create squared pct_medicare_adj variable
gen snf_pct_medicare_adj2 = snf_pct_medicare_adj^2
label var snf_pct_medicare_adj2 "Pct Medicare Squared"
summ snf_pct_medicare_adj2

local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc"
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"


********************************************************************************
// 2SLS regressions with beneficiary ZIP & DRG FEs //
********************************************************************************
// LOS & payment outcomes //

eststo clear
foreach y of varlist snf_los {
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (snf_pct_medicare_adj snf_pct_medicare_adj2 = `instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
}

* 90d payment outcomes (adds obs_days_90)
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (snf_pct_medicare_adj snf_pct_medicare_adj2 = `instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
}


// mortality and readmission //

** FFS sample (ffs_ma_combo==1)
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (snf_pct_medicare_adj snf_pct_medicare_adj2 = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first

ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (snf_pct_medicare_adj snf_pct_medicare_adj2 = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first

log close
