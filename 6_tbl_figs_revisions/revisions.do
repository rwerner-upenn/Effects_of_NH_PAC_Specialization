cap log close
log using "$log_path/revisions_log_$date.log", replace

/* This do-file addresses editor and reviewer revisions

*/


/*
********************************************************************************
// Load Nursing Home Compare data (provider info files) //
********************************************************************************
/* NOTE: Used monthly files from July for 2014-2018. 2013 data is only available
at the quarter level; I will use Q3 data */
forval yr = 2014/2018 {
	import delimited "$raw_data_path/11_nhc_data/nhc_provinfo_`yr'.csv", ///
		stringcols(1) clear
	keep provnum overall_rating survey_rating quality_rating staffing_rating ///
		adj_aide adj_lpn adj_rn adj_total weighted_all_cycles_score
	gen snf_admsn_year = `yr'
	rename provnum snf_prvdr_num
	tempfile nhc_`yr'
	save `nhc_`yr''
}
import delimited "$raw_data_path/11_nhc_data/nhc_provinfo_2013.csv", stringcols(1) clear
keep if quarter == "2013Q3"
keep provnum overall_rating survey_rating quality_rating staffing_rating ///
	adj_aide adj_lpn adj_rn adj_total weighted_all_cycles_score
gen snf_admsn_year = 2013
rename provnum snf_prvdr_num
tempfile nhc_2013
save `nhc_2013'

clear
forval yr = 2013/2018 {
	append using `nhc_`yr''
}
egen snf_prvdr_num2 = group(snf_prvdr_num)
xtset snf_prvdr_num2 snf_admsn_year, yearly
sort snf_prvdr_num2 snf_admsn_year
foreach var of varlist overall_rating survey_rating quality_rating staffing_rating adj_aide adj_lpn adj_rn adj_total weighted_all_cycles_score {
	gen chg_`var' = `var' - L.`var'
	gen `var'_lag = L.`var'
}
save "$temp_path/nhc_data.dta", replace



********************************************************************************
// Load Nursing Home Compare data (MDS quality files) //
********************************************************************************
/* 2014 and 2015 files only provide 3-quarter averages. I'll average Q2-Q4 in the 
2016-2018 files */
forval yr = 2014/2018 {
	import delimited "$raw_data_path/11_nhc_data/nhc_qualitymds_`yr'.csv", stringcols(1) clear
	keep if stay_type == "Long Stay" & five_star_msr == "Y"
	tab1 msr_cd msr_descr
	preserve
		keep msr_cd msr_descr
		duplicates drop
		list
	restore
	if inrange(`yr', 2016, 2018) {
		egen avg_score_ = rowmean(q2_measure_score q3_measure_score q4_measure_score)
		keep provnum msr_cd avg_score_
	}
	else {
		keep provnum msr_cd measure_score_3qtr_avg
		rename measure_score_3qtr_avg avg_score_
	}
	rename provnum snf_prvdr_num
	reshape wide avg_score_, i(snf_prvdr_num) j(msr_cd)
	gen snf_admsn_year = `yr'
	tempfile mds_qual_`yr'
	save `mds_qual_`yr''
}
clear
forval yr = 2014/2018 {
	append using `mds_qual_`yr''
}
order snf_prvdr_num snf_admsn_year, first
foreach var of varlist avg_score_401 avg_score_402 avg_score_403 avg_score_406 avg_score_407 avg_score_409 avg_score_410 avg_score_419 {
	tabstat `var', by(snf_admsn_year) stat(mean sd min max n)
}
save "$temp_path/long_stay_qual_data.dta", replace


use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
keep if ffs_ma_combo == 1
keep snf_prvdr_num snf_admsn_year pct_med snf_pct_medicare_cat ///
	snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based
duplicates drop
merge 1:1 snf_prvdr_num snf_admsn_year using "$temp_path/long_stay_qual_data.dta", ///
	nogen keep(match)
egen snf_prvdr_num2 = group(snf_prvdr_num)
summ pct_med avg_score_401 avg_score_402 avg_score_403 avg_score_406 avg_score_407 avg_score_409 avg_score_410

* Association between long-stay outcomes and % Medicare, SNF FEs
mat define ltc_regs = J(5, 7, .)
mat colnames ltc_regs = avg_score_401 avg_score_402 avg_score_403 avg_score_406 avg_score_407 avg_score_409 avg_score_410
local col = 1
foreach var of varlist avg_score_401 avg_score_402 avg_score_403 avg_score_406 avg_score_407 avg_score_409 avg_score_410 {
	reghdfe `var' pct_med i.snf_admsn_year, absorb(snf_prvdr_num2) cluster(snf_prvdr_num2)
	mat ltc_regs[1, `col'] = _b[pct_med]
	mat ltc_regs[2, `col'] = _se[pct_med]
	mat ltc_regs[3, `col'] = e(N)
	
	summ `var'
	mat ltc_regs[5, `col'] = `r(mean)'
	
	local col = `col' + 1
}

clear
mat list ltc_regs
svmat ltc_regs, names(col)
gen row_label = ""
replace row_label = "% Medicare" if _n == 1
replace row_label = "N of SNF-years" if _n == 3
replace row_label = "Mean outcome" if _n == 5

* Add parentheses for SEs
foreach var of varlist avg_score_401 avg_score_402 avg_score_403 avg_score_406 avg_score_407 avg_score_409 avg_score_410 {
	gen `var'_2 = string(`var', "%12.3fc")
	replace `var'_2 = "(" + `var'_2 + ")" if _n == 2
	replace `var'_2 = subinstr(`var'_2, ".000", "", .) if _n == 3
	replace `var'_2 = "" if _n == 4
	drop `var'
	rename `var'_2 `var'
}

order row_label avg_score_401 avg_score_402 avg_score_403 avg_score_406 avg_score_407 avg_score_409 avg_score_410
label var row_label " "
label var avg_score_401 "Need for ADL help increased"
label var avg_score_402 "Self-report moderate/severe pain"
label var avg_score_403 "Pressure ulcers"
label var avg_score_406 "Catheter inserted/left in bladder"
label var avg_score_407 "Urinary tract infection"
label var avg_score_409 "Physically restrained"
label var avg_score_410 "One or more falls"
export excel using "$table_path/ltc_regs", firstrow(varlabels) replace



********************************************************************************
// Association between quality variables and % Medicare (Appendix Table 3) //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
keep if ffs_ma_combo == 1
keep snf_prvdr_num snf_admsn_year pct_med snf_pct_medicare_cat ///
	snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based
duplicates drop
tab snf_admsn_year
egen snf_prvdr_num2 = group(snf_prvdr_num)
xtset snf_prvdr_num2 snf_admsn_year, yearly
sort snf_prvdr_num2 snf_admsn_year
gen chg_pct_medicare = pct_med - L.pct_med
drop if snf_admsn_year == 2011 | snf_admsn_year == 2012
merge 1:1 snf_prvdr_num snf_admsn_year using "$temp_path/nhc_data.dta"
keep if _merge == 3
drop _merge
* NOTE: <1% of obs from claims file don't merge with NHC data

tab snf_admsn_year
summ pct_med overall_rating survey_rating quality_rating staffing_rating adj_aide adj_lpn adj_rn adj_total weighted_all_cycles_score
summ chg_pct_medicare chg_overall_rating chg_survey_rating chg_quality_rating chg_staffing_rating chg_adj_aide chg_adj_lpn chg_adj_rn chg_adj_total chg_weighted_all_cycles_score


/* Drop observations that are missing at least one of the outcome variables so that
all regressions have the same number of obs */
drop if missing(pct_med, overall_rating, survey_rating, quality_rating, staffing_rating, adj_aide, adj_lpn, adj_rn, adj_total, weighted_all_cycles_score)

mat define assoc_qual_pctmed = J(19, 3, .)
mat colnames assoc_qual_pctmed = no_cntrl cntrl mean

local row = 1
foreach var of varlist overall_rating survey_rating quality_rating staffing_rating weighted_all_cycles_score adj_aide adj_lpn adj_rn adj_total {
	local next_row = `row' + 1
	
	reghdfe `var' pct_med, absorb(snf_prvdr_num) cluster(snf_prvdr_num)
	mat assoc_qual_pctmed[`row', 1] = _b[pct_med]
	mat assoc_qual_pctmed[`next_row', 1] = _se[pct_med]
	if `row' == 17 {
		mat assoc_qual_pctmed[19, 1] = e(N)
	}
	
	reghdfe `var' pct_med snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year, absorb(snf_prvdr_num) cluster(snf_prvdr_num)
	mat assoc_qual_pctmed[`row', 2] = _b[pct_med]
	mat assoc_qual_pctmed[`next_row', 2] = _se[pct_med]
	if `row' == 17 {
		mat assoc_qual_pctmed[19, 2] = e(N)
	}
	
	local row = `row' + 2
}

local row = 1
foreach var of varlist overall_rating survey_rating quality_rating staffing_rating weighted_all_cycles_score adj_aide adj_lpn adj_rn adj_total {
	summ `var'
	mat assoc_qual_pctmed[`row', 3] = `r(mean)'
	local row = `row' + 2
}
summ pct_med chg_pct_medicare

clear
mat list assoc_qual_pctmed
svmat assoc_qual_pctmed, names(col)
gen outcome = ""
replace outcome = "Overall star rating" if _n == 1
replace outcome = "Health inspection rating" if _n == 3
replace outcome = "Quality rating" if _n == 5
replace outcome = "Staffing rating" if _n == 7
replace outcome = "Health inspection score" if _n == 9
replace outcome = "Adj aide HPRPD" if _n == 11
replace outcome = "Adj LPN HPRPD" if _n == 13
replace outcome = "Adj RN HPRPD" if _n == 15
replace outcome = "Adj total HPRPD" if _n == 17
replace outcome = "N of SNF-years" if _n == 19

foreach var of varlist no_cntrl cntrl mean {
	gen `var'_2 = string(`var', "%12.3fc")
	replace `var'_2 = "(" + `var'_2 + ")" if inlist(_n, 2, 4, 6, 8, 10, 12, 14, 16, 18)
	
	replace `var'_2 = subinstr(`var'_2, ".000", "", .) if _n == 19
	
	if "`var'" == "mean" {
		replace `var'_2 = "" if inlist(_n, 2, 4, 6, 8, 10, 12, 14, 16, 18, 19)
	}
	
	drop `var'
	rename `var'_2 `var'
}

order outcome no_cntrl cntrl mean
label var outcome " "
label var no_cntrl "No covariates"
label var cntrl "Covariates"
label var mean "Mean outcome"
export excel using "$table_path/assoc_qual_pctmed_$date", firstrow(varlabels) replace



********************************************************************************
// 2SLS with lagged quality variables as controls (Table 8, column 5) //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
drop if snf_admsn_year == 2011 | snf_admsn_year == 2012

local qual_cntrl overall_rating_lag survey_rating_lag quality_rating_lag staffing_rating_lag weighted_all_cycles_score_lag adj_aide_lag adj_lpn_lag adj_rn_lag
merge m:1 snf_prvdr_num snf_admsn_year using "$temp_path/nhc_data.dta", keepusing(`qual_cntrl')
keep if _merge == 3
drop _merge

* Balance of quality variables across IV groups (Table 5, last panel)
tabstat `qual_cntrl' if ffs_ma_combo == 1, c(statistics) stat(mean sd count) by(iv_group) nototal

* 2013 is the first year of NHC data, so can't include lagged quality variables for 2013 claims data
drop if snf_admsn_year == 2013
foreach var of varlist `qual_cntrl' {
	drop if missing(`var')
}
count

local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc" 
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"

mat define rev_analyses = J(15, 10, .)
mat colnames rev_analyses = lag_qual lag_vol bel_med_vol ab_med_vol mono1 mono2 mono3 mono4 new_se new_fs

* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' `qual_cntrl' obs_days_30 (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
mat rev_analyses[1, 1] = _b[pct_med]
mat rev_analyses[2, 1] = _se[pct_med]

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' `qual_cntrl' (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
mat rev_analyses[3, 1] = _b[pct_med]
mat rev_analyses[4, 1] = _se[pct_med]

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' `qual_cntrl' died_in_snf (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
mat rev_analyses[5, 1] = _b[pct_med]
mat rev_analyses[6, 1] = _se[pct_med]

* 90-day payment outcomes, FFS sample
local count = 7
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	local count2 = `count' + 1
	
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' `qual_cntrl' obs_days_90 (pct_med = `instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
	mat rev_analyses[`count', 1] = _b[pct_med]
	mat rev_analyses[`count2', 1] = _se[pct_med]
	
	local count = `count' + 2
}
mat rev_analyses[15, 1] = e(N)



********************************************************************************
// 2SLS with lagged volume (Table 8, column 6) //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear

* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' snf_med_admns_lag obs_days_30 (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
mat rev_analyses[1, 2] = _b[pct_med]
mat rev_analyses[2, 2] = _se[pct_med]

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' snf_med_admns_lag (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
mat rev_analyses[3, 2] = _b[pct_med]
mat rev_analyses[4, 2] = _se[pct_med]

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' snf_med_admns_lag died_in_snf (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
mat rev_analyses[5, 2] = _b[pct_med]
mat rev_analyses[6, 2] = _se[pct_med]

* 90-day payment outcomes, FFS sample
local count = 7
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	local count2 = `count' + 1
	
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' snf_med_admns_lag obs_days_90 (pct_med = `instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
	mat rev_analyses[`count', 2] = _b[pct_med]
	mat rev_analyses[`count2', 2] = _se[pct_med]
	
	local count = `count' + 2
}
mat rev_analyses[15, 2] = e(N)



********************************************************************************
// 2SLS with lagged volume (Table 7, columns 6 and 7) //
********************************************************************************
* Calculate median at the SNF-year level
keep snf_prvdr_num snf_admsn_year snf_med_admns_lag
drop if missing(snf_med_admns_lag)
duplicates drop
summ snf_med_admns_lag, d
local lag_admns_med = `r(p50)'

use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
gen ab_med_vol = snf_med_admns_lag > `lag_admns_med'
replace ab_med_vol = . if missing(snf_med_admns_lag)

local col = 3
forval i = 0/1 {
	* 30-day readmissions, FFS sample
	ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (pct_med = `instr') ///
		if ffs_ma_combo == 1 & ab_med_vol == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat rev_analyses[1, `col'] = _b[pct_med]
	mat rev_analyses[2, `col'] = _se[pct_med]

	* 30-day mortality, FFS sample
	ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (pct_med = `instr') ///
		if ffs_ma_combo == 1 & ab_med_vol == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat rev_analyses[3, `col'] = _b[pct_med]
	mat rev_analyses[4, `col'] = _se[pct_med]

	* Length of stay, FFS sample
	ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (pct_med = `instr') ///
		if ffs_ma_combo == 1 & ab_med_vol == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat rev_analyses[5, `col'] = _b[pct_med]
	mat rev_analyses[6, `col'] = _se[pct_med]

	* 90-day payment outcomes, FFS sample
	local count = 7
	foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
		local count2 = `count' + 1
		
		ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (pct_med = `instr') ///
			if ffs_ma_combo == 1 & ab_med_vol == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
		mat rev_analyses[`count', `col'] = _b[pct_med]
		mat rev_analyses[`count2', `col'] = _se[pct_med]
		
		local count = `count' + 2
	}
	mat rev_analyses[15, `col'] = e(N)
	
	local col = `col' + 1
}
*/

/*
********************************************************************************
// 2SLS using 1 instrument and conditioning on the others (Appendix Table 4) //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc"
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4

local col = 5
foreach var of varlist log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4 {
	local sing_instr `var'
	local rem_instr : list instr - sing_instr

	* 30-day readmissions, FFS sample
	ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 `rem_instr' (pct_med = `sing_instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
// 	mat rev_analyses[1, `col'] = _b[pct_med]
// 	mat rev_analyses[2, `col'] = _se[pct_med]

	* 30-day mortality, FFS sample
	ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' `rem_instr' (pct_med = `sing_instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
// 	mat rev_analyses[3, `col'] = _b[pct_med]
// 	mat rev_analyses[4, `col'] = _se[pct_med]

	* Length of stay, FFS sample
	ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf `rem_instr' (pct_med = `sing_instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
// 	mat rev_analyses[5, `col'] = _b[pct_med]
// 	mat rev_analyses[6, `col'] = _se[pct_med]

	* 90-day payment outcomes, FFS sample
	local count = 7
	foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
		local count2 = `count' + 1
		
		ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 `rem_instr' (pct_med = `sing_instr') if ffs_ma_combo == 1, ///
			absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
// 		mat rev_analyses[`count', `col'] = _b[pct_med]
// 		mat rev_analyses[`count2', `col'] = _se[pct_med]
		
		local count = `count' + 2
	}
// 	mat rev_analyses[15, `col'] = e(N)
	
	local col = `col' + 1
}



********************************************************************************
// 2SLS, SEs clustered by facility //
********************************************************************************
* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(snf_prvdr_num)
// mat rev_analyses[1, 9] = _b[pct_med]
// mat rev_analyses[2, 9] = _se[pct_med]

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(snf_prvdr_num)
// mat rev_analyses[3, 9] = _b[pct_med]
// mat rev_analyses[4, 9] = _se[pct_med]

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(snf_prvdr_num)
// mat rev_analyses[5, 9] = _b[pct_med]
// mat rev_analyses[6, 9] = _se[pct_med]

* 90-day payment outcomes, FFS sample
local count = 7
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	local count2 = `count' + 1
	
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (pct_med = `instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(snf_prvdr_num)
// 	mat rev_analyses[`count', 9] = _b[pct_med]
// 	mat rev_analyses[`count2', 9] = _se[pct_med]
	
	local count = `count' + 2
}
// mat rev_analyses[15, 9] = e(N)



********************************************************************************
// 2SLS, all pairwise interactions between instruments //
********************************************************************************
* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (pct_med = `instr' c.log_mi_to_snf1#c.log_mi_to_snf2 c.log_mi_to_snf1#c.log_mi_to_snf3 c.log_mi_to_snf1#c.log_mi_to_snf4 c.log_mi_to_snf2#c.log_mi_to_snf3 c.log_mi_to_snf2#c.log_mi_to_snf4 c.log_mi_to_snf3#c.log_mi_to_snf4) if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
// mat rev_analyses[1, 10] = _b[pct_med]
// mat rev_analyses[2, 10] = _se[pct_med]

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (pct_med = `instr' c.log_mi_to_snf1#c.log_mi_to_snf2 c.log_mi_to_snf1#c.log_mi_to_snf3 c.log_mi_to_snf1#c.log_mi_to_snf4 c.log_mi_to_snf2#c.log_mi_to_snf3 c.log_mi_to_snf2#c.log_mi_to_snf4 c.log_mi_to_snf3#c.log_mi_to_snf4) if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
// mat rev_analyses[3, 10] = _b[pct_med]
// mat rev_analyses[4, 10] = _se[pct_med]

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (pct_med = `instr' c.log_mi_to_snf1#c.log_mi_to_snf2 c.log_mi_to_snf1#c.log_mi_to_snf3 c.log_mi_to_snf1#c.log_mi_to_snf4 c.log_mi_to_snf2#c.log_mi_to_snf3 c.log_mi_to_snf2#c.log_mi_to_snf4 c.log_mi_to_snf3#c.log_mi_to_snf4) if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
// mat rev_analyses[5, 10] = _b[pct_med]
// mat rev_analyses[6, 10] = _se[pct_med]

* 90-day payment outcomes, FFS sample
local count = 7
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	local count2 = `count' + 1
	
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (pct_med = `instr' c.log_mi_to_snf1#c.log_mi_to_snf2 c.log_mi_to_snf1#c.log_mi_to_snf3 c.log_mi_to_snf1#c.log_mi_to_snf4 c.log_mi_to_snf2#c.log_mi_to_snf3 c.log_mi_to_snf2#c.log_mi_to_snf4 c.log_mi_to_snf3#c.log_mi_to_snf4) if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num) first
// 	mat rev_analyses[`count', 10] = _b[pct_med]
// 	mat rev_analyses[`count2', 10] = _se[pct_med]
	
	local count = `count' + 2
}
// mat rev_analyses[15, 10] = e(N)


/* First stage regressions only */
* Using 30-day readmissions controls
reghdfe pct_med `instr' c.log_mi_to_snf1#c.log_mi_to_snf2 c.log_mi_to_snf1#c.log_mi_to_snf3 c.log_mi_to_snf1#c.log_mi_to_snf4 c.log_mi_to_snf2#c.log_mi_to_snf3 c.log_mi_to_snf2#c.log_mi_to_snf4 c.log_mi_to_snf3#c.log_mi_to_snf4 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
test `instr' c.log_mi_to_snf1#c.log_mi_to_snf2 c.log_mi_to_snf1#c.log_mi_to_snf3 c.log_mi_to_snf1#c.log_mi_to_snf4 c.log_mi_to_snf2#c.log_mi_to_snf3 c.log_mi_to_snf2#c.log_mi_to_snf4 c.log_mi_to_snf3#c.log_mi_to_snf4
	
* Using 30-day mortality controls
reghdfe pct_med `instr' c.log_mi_to_snf1#c.log_mi_to_snf2 c.log_mi_to_snf1#c.log_mi_to_snf3 c.log_mi_to_snf1#c.log_mi_to_snf4 c.log_mi_to_snf2#c.log_mi_to_snf3 c.log_mi_to_snf2#c.log_mi_to_snf4 c.log_mi_to_snf3#c.log_mi_to_snf4 `ptdemo_no_ses' `dxs' `ctrls_base' if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
test `instr' c.log_mi_to_snf1#c.log_mi_to_snf2 c.log_mi_to_snf1#c.log_mi_to_snf3 c.log_mi_to_snf1#c.log_mi_to_snf4 c.log_mi_to_snf2#c.log_mi_to_snf3 c.log_mi_to_snf2#c.log_mi_to_snf4 c.log_mi_to_snf3#c.log_mi_to_snf4


/* Export table */
// clear
// mat list rev_analyses
// svmat rev_analyses, names(col)
// gen outcome = ""
// replace outcome = "30d readmission" if _n == 1
// replace outcome = "30d mortality" if _n == 3
// replace outcome = "SNF length of stay" if _n == 5
// replace outcome = "90d index SNF payment" if _n == 7
// replace outcome = "90d subsequent PAC payment" if _n == 9
// replace outcome = "90d rehospitalization payment" if _n == 11
// replace outcome = "90d total Part A payment" if _n == 13
// replace outcome = "N of admissions" if _n == 15
//
// foreach var of varlist lag_qual lag_vol bel_med_vol ab_med_vol mono1 mono2 mono3 mono4 new_se new_fs {
// 	gen `var'_2 = string(`var', "%12.3fc")
// 	replace `var'_2 = "(" + `var'_2 + ")" if inlist(_n, 2, 4, 6, 8, 10, 12, 14)
// 	replace `var'_2 = subinstr(`var'_2, ".000", "", .) if _n == 15
// 	drop `var'
// 	rename `var'_2 `var'
// }
//
// order outcome lag_qual lag_vol bel_med_vol ab_med_vol mono1 mono2 mono3 mono4 new_se new_fs
// label var outcome " "
// label var lag_qual "Lagged quality"
// label var lag_vol "Lagged volume"
// label var bel_med_vol "<= median vol"
// label var ab_med_vol "> median vol"
// label var mono1 "Log dist Q1 SNF"
// label var mono2 "Log dist Q2 SNF"
// label var mono3 "Log dist Q3 SNF"
// label var mono4 "Log dist Q4 SNF"
// label var new_se "Nursing home clustered SEs"
// label var new_fs "First stage w/ pairwise inter"
// export excel using "$table_path/rev_analyses_$date", firstrow(varlabels) replace
*/


********************************************************************************
// Formally test for equality of coefficients (Table 7 stratifications) //
********************************************************************************
* Median of distance to the nearest hospital (SNF-year level)
use "$raw_data_path/09_nearest_hospital/snfs_min_dist.dta", clear
summ min_dist_mi, d
local median = `r(p50)'

use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
merge m:1 snf_prvdr_num snf_admsn_year using "$raw_data_path/09_nearest_hospital/snfs_min_dist.dta", gen(near_hosp_merge)
gen near_hospital = min_dist_mi <= `median'
replace near_hospital = . if missing(min_dist_mi)
save "$proc_data_path/final_data_snfclaims_analysis_file2.dta", replace

* Median of lagged PAC admissions (SNF-year level)
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
keep snf_prvdr_num snf_admsn_year snf_med_admns_lag
drop if missing(snf_med_admns_lag)
duplicates drop
summ snf_med_admns_lag, d
local lag_admns_med = `r(p50)'

use "$proc_data_path/final_data_snfclaims_analysis_file2.dta", clear
gen ab_med_vol = snf_med_admns_lag > `lag_admns_med'
replace ab_med_vol = . if missing(snf_med_admns_lag)
save "$proc_data_path/final_data_snfclaims_analysis_file2.dta", replace


foreach var of varlist near_hospital snf_hosp_based {
	disp "Testing equality of coefficients for `var' stratifications"
	
	local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
	local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc" 
	local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
	local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"
	
	local cntrl_cont "age_cnt hosp_los snf_bed_cnt obs_days_30"
	local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_hosp_based snf_admsn_year"
	if "`var'" == "snf_hosp_based" {
		local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt i.snf_admsn_year"
		local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_admsn_year"
	}
	
	* 30-day readmissions, FFS sample
	quietly {
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 ///
		if ffs_ma_combo == 1 & `var' == 0, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res1)
	predict pct_med_hat if e(sample), xbd

	* 30-day readmissions, FFS sample
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 ///
		if ffs_ma_combo == 1 & `var' == 1, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res2)
	predict pct_med_hat2 if e(sample), xbd
	replace pct_med_hat = pct_med_hat2 if missing(pct_med_hat)
	}

	* 30-day readmissions, second stage, stacking approach	
	reghdfe radm30 c.pct_med_hat#i.`var' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 ///
		c.(`cntrl_cont')#i.`var' i.(`cntrl_dum')#i.`var' if ffs_ma_combo == 1, ///
		absorb(i.hosp_drgcd i.hosp_drgcd#i.`var' i.bene_zip_num i.bene_zip_num#i.`var') ///
		cluster(`var'#bene_zip_num)
	test _b[c.pct_med_hat#0.`var'] = _b[c.pct_med_hat#1.`var']
	drop pct_med_hat pct_med_hat2 res1 res2
	
	
	
	local cntrl_cont "age_cnt hosp_los snf_bed_cnt"
	local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_hosp_based snf_admsn_year"
	if "`var'" == "snf_hosp_based" {
		local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_admsn_year"
	}
	
	* 30-day mortality, FFS sample
	quietly {
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' ///
		if ffs_ma_combo == 1 & `var' == 0, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res1)
	predict pct_med_hat if e(sample), xbd
	
	* 30-day mortality, FFS sample
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' ///
		if ffs_ma_combo == 1 & `var' == 1, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res2)
	predict pct_med_hat2 if e(sample), xbd
	replace pct_med_hat = pct_med_hat2 if missing(pct_med_hat)
	}
	
	* 30-day mortality, second stage, stacking approach
	reghdfe death_30_hosp_new c.pct_med_hat#i.`var' `ptdemo_no_ses' `dxs' `ctrls_base' ///
		c.(`cntrl_cont')#i.`var' i.(`cntrl_dum')#i.`var' if ffs_ma_combo == 1, ///
		absorb(i.hosp_drgcd i.hosp_drgcd#i.`var' i.bene_zip_num i.bene_zip_num#i.`var') ///
		cluster(`var'#bene_zip_num)
	test _b[c.pct_med_hat#0.`var'] = _b[c.pct_med_hat#1.`var']
	drop pct_med_hat pct_med_hat2 res1 res2
	
	
	
	local cntrl_cont "age_cnt hosp_los snf_bed_cnt"
	local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_hosp_based snf_admsn_year died_in_snf"
	if "`var'" == "snf_hosp_based" {
		local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_admsn_year died_in_snf"
	}
	
	* Length of stay, FFS sample
	quietly {
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf ///
		if ffs_ma_combo == 1 & `var' == 0, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res1)
	predict pct_med_hat if e(sample), xbd
	
	* Length of stay, FFS sample
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf ///
		if ffs_ma_combo == 1 & `var' == 1, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res2)
	predict pct_med_hat2 if e(sample), xbd
	replace pct_med_hat = pct_med_hat2 if missing(pct_med_hat)
	}
	
	* Length of stay, second stage, stacking approach
	reghdfe snf_los c.pct_med_hat#i.`var' `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf ///
		c.(`cntrl_cont')#i.`var' i.(`cntrl_dum')#i.`var' if ffs_ma_combo == 1, ///
		absorb(i.hosp_drgcd i.hosp_drgcd#i.`var' i.bene_zip_num i.bene_zip_num#i.`var') ///
		cluster(`var'#bene_zip_num)
	test _b[c.pct_med_hat#0.`var'] = _b[c.pct_med_hat#1.`var']
	drop pct_med_hat pct_med_hat2 res1 res2
	
	
	
	local cntrl_cont "age_cnt hosp_los snf_bed_cnt obs_days_90"
	local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_hosp_based snf_admsn_year"
	if "`var'" == "snf_hosp_based" {
		local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_admsn_year"
	}
	
	* Payment variables, FFS sample
	quietly {
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 ///
		if ffs_ma_combo == 1 & `var' == 0, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res1)
	predict pct_med_hat if e(sample), xbd
	
	* Payment variables, FFS sample
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 ///
		if ffs_ma_combo == 1 & `var' == 1, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res2)
	predict pct_med_hat2 if e(sample), xbd
	replace pct_med_hat = pct_med_hat2 if missing(pct_med_hat)
	}
	
	* Payment variables, second stage, stacking approach
	foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new { 
		reghdfe `y' c.pct_med_hat#i.`var' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 ///
			c.(`cntrl_cont')#i.`var' i.(`cntrl_dum')#i.`var' if ffs_ma_combo == 1, ///
			absorb(i.hosp_drgcd i.hosp_drgcd#i.`var' i.bene_zip_num i.bene_zip_num#i.`var') ///
			cluster(`var'#bene_zip_num)
		test _b[c.pct_med_hat#0.`var'] = _b[c.pct_med_hat#1.`var']
	}
	drop pct_med_hat pct_med_hat2 res1 res2
}


/*
********************************************************************************
// 2SLS w/ contemporaneous staffing from LTCFocus as controls (Table 8, column 4) //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
destring rnhrppd lpnhrppd cnahrppd, replace
preserve
	keep snf_prvdr_num snf_admsn_year snf_pct_medicare_cat rnhrppd lpnhrppd cnahrppd
	duplicates drop
	tabstat rnhrppd lpnhrppd cnahrppd, by(snf_pct_medicare_cat) stat(mean sd min max count)
restore

local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc" 
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"
local staff "rnhrppd lpnhrppd cnahrppd"

* 30-day readmissions, FFS sample
ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 `staff' (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* 30-day mortality, FFS sample
ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' `staff' (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* Length of stay, FFS sample
ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf `staff' (pct_med = `instr') if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)

* 90-day payment outcomes, FFS sample
foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
	ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 `staff' (pct_med = `instr') if ffs_ma_combo == 1, ///
		absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
}



********************************************************************************
// "Reverse causality regression" - Clark and Huckman (2012) //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear

preserve
	keep snf_prvdr_num snf_admsn_year pct_med
	duplicates drop
	egen snf_prvdr_num2 = group(snf_prvdr_num)
	xtset snf_prvdr_num2 snf_admsn_year, yearly
	gen pct_med_lead = F.pct_med
	keep snf_prvdr_num snf_admsn_year pct_med_lead
	tempfile tmp
	save `tmp'
restore
merge m:1 snf_prvdr_num snf_admsn_year using `tmp', nogen

local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc" 
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"

* OLS of % Medicare in t+1 on 30-day mortality in t with SNF FEs
reghdfe pct_med_lead death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' if ffs_ma_combo == 1, ///
	absorb(hosp_drgcd snf_prvdr_num) cluster(snf_prvdr_num)
summ pct_med_lead death_30_hosp_new if e(sample) == 1



********************************************************************************
// Misc calculations //
********************************************************************************
summ radm30 if ffs_ma_combo == 1 & snf_hosp_based == 0
summ radm30 if ffs_ma_combo == 1 & snf_hosp_based == 1



********************************************************************************
// Stratification by neighborhood characteristics //
********************************************************************************
use "$raw_data_path/12_ma_pen_by_zip/ZIP_Year_MA_2011_2018.dta", clear
rename ZIP_CD_BENE bene_zip
rename RFRNC_YR snf_admsn_year
rename ZIP_YEAR_MA_PCT ma_pct
replace ma_pct = ma_pct * 100
save "$temp_path/ma_pen_zip_year.dta", replace

use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
merge m:1 bene_zip snf_admsn_year using "$temp_path/ma_pen_zip_year.dta"
keep if _merge == 1 | _merge == 3
drop _merge
tempfile tmp
save `tmp'

keep bene_zip snf_admsn_year ma_pct
duplicates drop
summ ma_pct, d
local ma_pen_median = `r(p50)'
use `tmp', clear
gen ab_med_ma_pen = ma_pct > `ma_pen_median'
replace ab_med_ma_pen = . if missing(ma_pct)

mat define neigh_strat = J(15, 4, .)
mat colnames neigh_strat = bel_med_ma ab_med_ma bel_med_pov ab_med_pov 
local col = 1
forval i = 0/1 {
	* 30-day readmissions, FFS sample
	ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (pct_med = `instr') ///
		if ffs_ma_combo == 1 & ab_med_ma_pen == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat neigh_strat[1, `col'] = _b[pct_med]
	mat neigh_strat[2, `col'] = _se[pct_med]

	* 30-day mortality, FFS sample
	ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (pct_med = `instr') ///
		if ffs_ma_combo == 1 & ab_med_ma_pen == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat neigh_strat[3, `col'] = _b[pct_med]
	mat neigh_strat[4, `col'] = _se[pct_med]

	* Length of stay, FFS sample
	ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (pct_med = `instr') ///
		if ffs_ma_combo == 1 & ab_med_ma_pen == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat neigh_strat[5, `col'] = _b[pct_med]
	mat neigh_strat[6, `col'] = _se[pct_med]

	* 90-day payment outcomes, FFS sample
	local count = 7
	foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
		local count2 = `count' + 1
		
		ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (pct_med = `instr') ///
			if ffs_ma_combo == 1 & ab_med_ma_pen == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
		mat neigh_strat[`count', `col'] = _b[pct_med]
		mat neigh_strat[`count2', `col'] = _se[pct_med]
		
		local count = `count' + 2
	}
	mat neigh_strat[15, `col'] = e(N)
	
	local col = `col' + 1
}

use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
keep bene_zip pct_pov snf_admsn_year
duplicates drop
summ pct_pov, d
local med_pct_pov = `r(p50)'

use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
gen ab_med_pct_pov = pct_pov > `med_pct_pov'
replace ab_med_pct_pov = . if missing(pct_pov)

forval i = 0/1 {
	* 30-day readmissions, FFS sample
	ivreghdfe radm30 `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 (pct_med = `instr') ///
		if ffs_ma_combo == 1 & ab_med_pct_pov == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat neigh_strat[1, `col'] = _b[pct_med]
	mat neigh_strat[2, `col'] = _se[pct_med]

	* 30-day mortality, FFS sample
	ivreghdfe death_30_hosp_new `ptdemo_no_ses' `dxs' `ctrls_base' (pct_med = `instr') ///
		if ffs_ma_combo == 1 & ab_med_pct_pov == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat neigh_strat[3, `col'] = _b[pct_med]
	mat neigh_strat[4, `col'] = _se[pct_med]

	* Length of stay, FFS sample
	ivreghdfe snf_los `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf (pct_med = `instr') ///
		if ffs_ma_combo == 1 & ab_med_pct_pov == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
	mat neigh_strat[5, `col'] = _b[pct_med]
	mat neigh_strat[6, `col'] = _se[pct_med]

	* 90-day payment outcomes, FFS sample
	local count = 7
	foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new {
		local count2 = `count' + 1
		
		ivreghdfe `y' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 (pct_med = `instr') ///
			if ffs_ma_combo == 1 & ab_med_pct_pov == `i', absorb(hosp_drgcd bene_zip_num) cluster(bene_zip_num)
		mat neigh_strat[`count', `col'] = _b[pct_med]
		mat neigh_strat[`count2', `col'] = _se[pct_med]
		
		local count = `count' + 2
	}
	mat neigh_strat[15, `col'] = e(N)
	
	local col = `col' + 1
}


/* Export table */
clear
mat list neigh_strat
svmat neigh_strat, names(col)
gen outcome = ""
replace outcome = "30d readmission" if _n == 1
replace outcome = "30d mortality" if _n == 3
replace outcome = "SNF length of stay" if _n == 5
replace outcome = "90d index SNF payment" if _n == 7
replace outcome = "90d subsequent PAC payment" if _n == 9
replace outcome = "90d rehospitalization payment" if _n == 11
replace outcome = "90d total Part A payment" if _n == 13
replace outcome = "N of admissions" if _n == 15

* Add parentheses for SEs
foreach var of varlist bel_med_ma ab_med_ma bel_med_pov ab_med_pov {
	gen `var'_2 = string(`var', "%12.3fc")
	replace `var'_2 = "(" + `var'_2 + ")" if inlist(_n, 2, 4, 6, 8, 10, 12, 14)
	replace `var'_2 = subinstr(`var'_2, ".000", "", .) if _n == 15
	drop `var'
	rename `var'_2 `var'
}

order outcome bel_med_ma ab_med_ma bel_med_pov ab_med_pov 
label var outcome " "
label var bel_med_ma "<median MA"
label var ab_med_ma ">median MA"
label var bel_med_pov "<median pov"
label var ab_med_pov ">median pov"
export excel using "$table_path/neigh_strat_$date", firstrow(varlabels) replace



********************************************************************************
// Formally test for equality of coefficients (Appendix Table 2 stratifications) //
********************************************************************************
* Calculate MA penetration median (beneficiary ZIP-year level)
use "$raw_data_path/12_ma_pen_by_zip/ZIP_Year_MA_2011_2018.dta", clear
rename ZIP_CD_BENE bene_zip
rename RFRNC_YR snf_admsn_year
rename ZIP_YEAR_MA_PCT ma_pct
replace ma_pct = ma_pct * 100
save "$temp_path/ma_pen_zip_year.dta", replace

use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
merge m:1 bene_zip snf_admsn_year using "$temp_path/ma_pen_zip_year.dta"
keep if _merge == 1 | _merge == 3
drop _merge
tempfile tmp
save `tmp'

keep bene_zip snf_admsn_year ma_pct
duplicates drop
summ ma_pct, d
local ma_pen_median = `r(p50)'
use `tmp', clear
gen ab_med_ma_pen = ma_pct > `ma_pen_median'
replace ab_med_ma_pen = . if missing(ma_pct)
save "$proc_data_path/final_data_snfclaims_analysis_file3.dta", replace

* Calculate % in poverty median (beneficiary ZIP-year level)
keep bene_zip pct_pov snf_admsn_year
duplicates drop
summ pct_pov, d
local med_pct_pov = `r(p50)'

use "$proc_data_path/final_data_snfclaims_analysis_file3.dta", clear
gen ab_med_pct_pov = pct_pov > `med_pct_pov'
replace ab_med_pct_pov = . if missing(pct_pov)
save "$proc_data_path/final_data_snfclaims_analysis_file3.dta", replace



local ptdemo_no_ses "age_cnt female black hispanic other dual_elig"
local dxs "chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc" 
local ctrls_base "hosp_los snf_in_chain snf_for_profit snf_bed_cnt snf_hosp_based i.snf_admsn_year"
local instr "log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4"

foreach var of varlist ab_med_ma_pen ab_med_pct_pov {
	disp "Testing equality of coefficients for `var' stratifications"
	
	local cntrl_cont "age_cnt hosp_los snf_bed_cnt obs_days_30"
	local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_hosp_based snf_admsn_year"
	
	* 30-day readmissions, FFS sample
	quietly {
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 ///
		if ffs_ma_combo == 1 & `var' == 0, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res1)
	predict pct_med_hat if e(sample), xbd

	* 30-day readmissions, FFS sample
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 ///
		if ffs_ma_combo == 1 & `var' == 1, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res2)
	predict pct_med_hat2 if e(sample), xbd
	replace pct_med_hat = pct_med_hat2 if missing(pct_med_hat)
	}

	* 30-day readmissions, second stage, stacking approach	
	reghdfe radm30 c.pct_med_hat#i.`var' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_30 ///
		c.(`cntrl_cont')#i.`var' i.(`cntrl_dum')#i.`var' if ffs_ma_combo == 1, ///
		absorb(i.hosp_drgcd i.hosp_drgcd#i.`var' i.bene_zip_num i.bene_zip_num#i.`var') ///
		cluster(`var'#bene_zip_num)
	test _b[c.pct_med_hat#0.`var'] = _b[c.pct_med_hat#1.`var']
	drop pct_med_hat pct_med_hat2 res1 res2
	
	
	
	local cntrl_cont "age_cnt hosp_los snf_bed_cnt"
	local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_hosp_based snf_admsn_year"

	* 30-day mortality, FFS sample
	quietly {
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' ///
		if ffs_ma_combo == 1 & `var' == 0, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res1)
	predict pct_med_hat if e(sample), xbd
	
	* 30-day mortality, FFS sample
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' ///
		if ffs_ma_combo == 1 & `var' == 1, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res2)
	predict pct_med_hat2 if e(sample), xbd
	replace pct_med_hat = pct_med_hat2 if missing(pct_med_hat)
	}
	
	* 30-day mortality, second stage, stacking approach
	reghdfe death_30_hosp_new c.pct_med_hat#i.`var' `ptdemo_no_ses' `dxs' `ctrls_base' ///
		c.(`cntrl_cont')#i.`var' i.(`cntrl_dum')#i.`var' if ffs_ma_combo == 1, ///
		absorb(i.hosp_drgcd i.hosp_drgcd#i.`var' i.bene_zip_num i.bene_zip_num#i.`var') ///
		cluster(`var'#bene_zip_num)
	test _b[c.pct_med_hat#0.`var'] = _b[c.pct_med_hat#1.`var']
	drop pct_med_hat pct_med_hat2 res1 res2
	
	
	
	local cntrl_cont "age_cnt hosp_los snf_bed_cnt"
	local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_hosp_based snf_admsn_year died_in_snf"

	* Length of stay, FFS sample
	quietly {
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf ///
		if ffs_ma_combo == 1 & `var' == 0, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res1)
	predict pct_med_hat if e(sample), xbd
	
	* Length of stay, FFS sample
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf ///
		if ffs_ma_combo == 1 & `var' == 1, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res2)
	predict pct_med_hat2 if e(sample), xbd
	replace pct_med_hat = pct_med_hat2 if missing(pct_med_hat)
	}
	
	* Length of stay, second stage, stacking approach
	reghdfe snf_los c.pct_med_hat#i.`var' `ptdemo_no_ses' `dxs' `ctrls_base' died_in_snf ///
		c.(`cntrl_cont')#i.`var' i.(`cntrl_dum')#i.`var' if ffs_ma_combo == 1, ///
		absorb(i.hosp_drgcd i.hosp_drgcd#i.`var' i.bene_zip_num i.bene_zip_num#i.`var') ///
		cluster(`var'#bene_zip_num)
	test _b[c.pct_med_hat#0.`var'] = _b[c.pct_med_hat#1.`var']
	drop pct_med_hat pct_med_hat2 res1 res2
	
	
	
	local cntrl_cont "age_cnt hosp_los snf_bed_cnt obs_days_90"
	local cntrl_dum "female black hispanic other dual_elig chf valve pulmcirc perivasc para neuro chrnlung dm dmcx hypothy renlfail liver ulcer aids lymph mets tumor arth coag obese wgthloss lytes bldloss anemdef alcohol drug psych depress htnc snf_in_chain snf_for_profit snf_hosp_based snf_admsn_year"
	
	* Payment variables, FFS sample
	quietly {
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 ///
		if ffs_ma_combo == 1 & `var' == 0, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res1)
	predict pct_med_hat if e(sample), xbd
	
	* Payment variables, FFS sample
	reghdfe pct_med `instr' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 ///
		if ffs_ma_combo == 1 & `var' == 1, absorb(hosp_drgcd bene_zip_num, savefe) ///
		cluster(bene_zip_num) residuals(res2)
	predict pct_med_hat2 if e(sample), xbd
	replace pct_med_hat = pct_med_hat2 if missing(pct_med_hat)
	}
	
	* Payment variables, second stage, stacking approach
	foreach y of varlist index_snf_pay_90 subseq_pac_90 Pmt_After_Hosp_90_sum_new_Acute Pmt_After_Hosp_90_sum_new { 
		reghdfe `y' c.pct_med_hat#i.`var' `ptdemo_no_ses' `dxs' `ctrls_base' obs_days_90 ///
			c.(`cntrl_cont')#i.`var' i.(`cntrl_dum')#i.`var' if ffs_ma_combo == 1, ///
			absorb(i.hosp_drgcd i.hosp_drgcd#i.`var' i.bene_zip_num i.bene_zip_num#i.`var') ///
			cluster(`var'#bene_zip_num)
		test _b[c.pct_med_hat#0.`var'] = _b[c.pct_med_hat#1.`var']
	}
	drop pct_med_hat pct_med_hat2 res1 res2
}
*/
	
********************************************************************************
********************************************************************************
log close
