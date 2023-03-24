* Sensitivity Tests - Regressions
* SNFs close to or farther from nearest hospital (Table 7, columns 2 and 3)
cap log close
log using "$log_path/5h_sens_near_hosp_log_final.log", replace

********************************************************************************
// Initialize locals for use in regressions //
********************************************************************************
use "$raw_data_path/09_nearest_hospital/snfs_min_dist.dta", clear
summ min_dist_mi, d
local median = `r(p50)'

use "$proc_data_path/final_data_snfclaims_analysis_file_copyC.dta", clear
* snf_county is the 5-char FIPS for the SNF as a string
keep if ffs_ma_combo==1

local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc"
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"

* need to bring in measure of each SNFs distance to the nearest hospital
* merge in hospital distance data
merge m:1 snf_prvdr_num snf_admsn_year using "$raw_data_path/09_nearest_hospital/snfs_min_dist.dta", gen(near_hosp_merge)
gen near_hospital = min_dist_mi <= `median'
replace near_hospital = . if missing(min_dist_mi)	
	
********************************************************************************
// SNFs closer to the nearest hospital //
********************************************************************************
* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (snf_pct_medicare_adj = `instr') if near_hospital == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (snf_pct_medicare_adj = `instr') if near_hospital == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (snf_pct_medicare_adj = `instr') if near_hospital == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* 90-day payment outcomes, FFS sample
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (snf_pct_medicare_adj = `instr') if near_hospital == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
}


********************************************************************************
// SNFs farther away from the nearest hospital //
********************************************************************************
* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (snf_pct_medicare_adj = `instr') if near_hospital == 0, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (snf_pct_medicare_adj = `instr') if near_hospital == 0, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (snf_pct_medicare_adj = `instr') if near_hospital == 0, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* 90-day payment outcomes, FFS sample
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (snf_pct_medicare_adj = `instr') if near_hospital == 0, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
}


********************************************************************************
********************************************************************************
log close
