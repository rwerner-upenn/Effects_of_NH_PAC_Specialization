cap log close
log using "$log_path/2_run_geonear_p75cut_log.log", replace

/* Using the categorization of the endogenous predictor in 1_process_data.do, 
this do-file uses geonear to calculate, for each patient/admission, the nearest SNF
in each category based on SNFs' geocodes and patient ZIP centroid geocodes */


/* Create separate datasets for each year of SNF claims */
forval i = 11/18 {
	local j : display %02.0f `i'
	use "$proc_data_path/final_data_snfclaims_analysis_file_p75cut.dta", clear
	keep if snf_admsn_year == 20`j'
	gen id = _n
	label var id "Unique claim ID (per year) (self-generated)"
	save "$temp_path/snfclaims_20`j'_p75cut.dta", replace
}


/* For each year of LTC Focus, saves 2 separate datasets, one for each of the 
% Medicare benes categories (based on 75th pctile cutoff) */
use "$temp_path/ltcfocus_p75cut.dta", clear
forval i = 11/18 {
	forval k = 1/2 {		
		local j : display %02.0f `i'
		preserve
			keep if snf_pct_medicare_cat == `k' & snf_admsn_year == 20`j'
			save "$temp_path/ltc_nh_days_cat`k'_20`j'_p75cut.dta", replace 
		restore
	}
}


/* For each year of MedPAR, finds the nearest SNF in each % Medicare benes category
(2 total) for each beneficiary */
forval i = 11/18 {
	forval k = 1/2 {
		local j : display %02.0f `i'
		use "$temp_path/snfclaims_20`j'_p75cut.dta", clear
		geonear id bene_zip_lat bene_zip_long using "$temp_path/ltc_nh_days_cat`k'_20`j'_p75cut.dta", ///
			n(snf_prvdr_num snf_geo_lat snf_geo_long) mi
		rename nid snf`k'_id
		rename mi_to_nid mi_to_snf`k'
		save "$temp_path/snfclaims_20`j'_p75cut.dta", replace
	}
}

* Recombine yearly SNF claims datasets into a single panel
clear
forval i = 11/18 {
	local j : display %02.0f `i'
	append using "$temp_path/snfclaims_20`j'_p75cut.dta"
}

* Log distances to nearest SNF for use as instruments
foreach var of varlist mi_to_snf1 mi_to_snf2 {
	gen log_`var' = log(`var' + 1)
}
label var log_mi_to_snf1 "Log dist - nearest nonspec SNF"
label var log_mi_to_snf2 "Log dist - nearest spec SNF"
save "$proc_data_path/final_data_snfclaims_analysis_file_p75cut.dta", replace


********************************************************************************
********************************************************************************
log close


