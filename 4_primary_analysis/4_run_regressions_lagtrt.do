cap log close
log using "$log_path/4_run_regressions_lagtrt_log.log", replace

/* This do-file runs a specification check using one-year lagged % Medicare (Table 8, column 7) */



use "$proc_data_path/final_data_snfclaims_analysis_file_lagtrt.dta", clear

* Double check lagging of % Medicare
tabstat snf_pct_medicare_adj, by(snf_admsn_year) stat(mean sd n)
local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc"
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"

* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* 90-day payment outcomes, FFS sample
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (snf_pct_medicare_adj = `instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
}


********************************************************************************
********************************************************************************
log close


