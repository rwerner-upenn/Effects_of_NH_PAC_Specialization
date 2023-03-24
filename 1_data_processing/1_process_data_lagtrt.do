cap log close
log using "$log_path/1_process_data_lagtrt_log.log", replace

/* This do-file replaces the treatment variable with the lagged % Medicare */



use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
replace snf_pct_medicare_adj = snf_pct_medicare_lag
label var snf_pct_medicare_adj "Pct Medicare (lag)"
gen miss_lag = cond(missing(snf_pct_medicare_adj),1,0)
tab miss_lag
drop if miss_lag==1

* Drop old sampling variables and reidentify singletons that will drop out of the regressions
drop used ma_samp ffs_samp
ivreghdfe radm30 female if ffs_ma_combo==2, ///
	absorb(hosp_drgcd bene_zip_num snf_prvdr_num) cluster(snf_prvdr_num)
gen byte used=e(sample)
tab ffs_ma_combo used
gen ma_samp=1 if used==1 & ffs_ma_combo==2
drop used
ivreghdfe radm30 female if ffs_ma_combo==1, ///
	absorb(hosp_drgcd bene_zip_num snf_prvdr_num) cluster(snf_prvdr_num)
gen byte used=e(sample)
tab ffs_ma_combo used
gen ffs_samp=1 if used==1 & ffs_ma_combo==1
keep if ffs_samp==1 | ma_samp==1

* Recreate categorical variable with lagged % Medicare
drop snf_pct_medicare_cat
summ snf_pct_medicare_adj, d
gen snf_pct_medicare_cat = .
replace snf_pct_medicare_cat = 1 if snf_pct_medicare_adj <= `r(p25)'
replace snf_pct_medicare_cat = 2 if snf_pct_medicare_adj > `r(p25)' & snf_pct_medicare_adj <= `r(p50)'
replace snf_pct_medicare_cat = 3 if snf_pct_medicare_adj > `r(p50)' & snf_pct_medicare_adj <= `r(p75)'
replace snf_pct_medicare_cat = 4 if snf_pct_medicare_adj > `r(p75)' & !missing(snf_pct_medicare_adj)

* Drop variables from main analysis geonear step
drop id snf1_id snf2_id snf3_id snf4_id mi_to_snf1 mi_to_snf2 mi_to_snf4 mi_to_snf3 log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4
save "$proc_data_path/final_data_snfclaims_analysis_file_lagtrt.dta", replace



********************************************************************************
// Merge snf pct medicare categories back to LTC Focus for use in geonear //
********************************************************************************
keep snf_admsn_year snf_prvdr_num snf_geo_lat snf_geo_long snf_pct_medicare_cat
duplicates drop
merge 1:1 snf_admsn_year snf_prvdr_num using "$temp_path/ltcfocus.dta", gen(lagtrtmerge)
keep if lagtrtmerge == 2 | lagtrtmerge == 3
save "$temp_path/ltcfocus_lagtrt.dta", replace


********************************************************************************
********************************************************************************
log close
