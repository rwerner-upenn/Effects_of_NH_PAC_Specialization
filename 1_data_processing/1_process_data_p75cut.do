cap log close
log using "$log_path/1_process_data_p75cut_log.log", replace

/* This do-file defines specialization as a binary cutoff at the 75th percentile, but preserves the continuout treatment var, pct medicare */

use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
drop snf_pct_medicare_cat
summ snf_pct_medicare_adj, d

gen snf_pct_medicare_cat = .
replace snf_pct_medicare_cat = 1 if snf_pct_medicare_adj <= `r(p75)'
replace snf_pct_medicare_cat = 2 if snf_pct_medicare_adj > `r(p75)' & !missing(snf_pct_medicare_adj)

* Drop existing variables and instruments from main analysis geonear step
drop id snf1_id snf2_id snf3_id snf4_id mi_to_snf1 mi_to_snf2 mi_to_snf4 mi_to_snf3 log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4
save "$proc_data_path/final_data_snfclaims_analysis_file_p75cut.dta", replace



********************************************************************************
// Merge snf pct medicare categories back to LTC Focus for use in geonear //
********************************************************************************
keep snf_admsn_year snf_prvdr_num snf_geo_lat snf_geo_long snf_pct_medicare_cat
duplicates drop
merge 1:1 snf_admsn_year snf_prvdr_num using "$temp_path/ltcfocus.dta", gen(p75_merge)
keep if p75_merge == 2 | p75_merge == 3
* save a new file just for the 75th percentile cutoff version of snf_pct_medicare_cat
save "$temp_path/ltcfocus_p75cut.dta", replace


********************************************************************************
********************************************************************************
log close
