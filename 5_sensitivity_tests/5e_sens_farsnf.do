* Sensitivity Tests - Regressions
* looking for null result for patients admitted to SNFs >100mi from home (Appendix Table 1)
cap log close
log using "$log_path/5e_sens_farsnf_log_final.log", replace

********************************************************************************
// Initialize locals for use in regressions //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
keep if ffs_ma_combo==1

local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc"
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"

gen farsnf100=0
replace farsnf100=1 if hosp_dist>=100

* admissions >100mi from home
* first stage only
reghdfe snf_pct_medicare_adj `instr' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 if farsnf100==1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
test `instr'
	

log close

