cap log close
log using "$log_path/1_process_data_log.log", replace

/* This do-file further processes the merged Medicare claims and LTC Focus dataset.
Importantly, it defines our endogenous variable for Medicare specialization among SNFs */



********************************************************************************
// Create variables in admission-year dataset //
********************************************************************************
* Analytical dataset that spans 2010-2018
use "BASE_DATA_FILE_PATH", clear
rename SNF snf
tab snf
keep if snf == 1		// only keep hospital discharges to SNF
rename PRVDRNUM_SNF snf_prvdr_num

* remove prvdr nums that don't have 3rd and 4th characters with 50* thru 64*
* https://resdac.org/sites/datadocumentation.resdac.org/files/Provider%20Number%20Table.txt
gen strtst = substr(snf_prvdr_num,3,2)
gen strtst_5064 = .
replace strtst_5064 = 1 if strtst=="50" | strtst=="51" | strtst=="52" | strtst=="53" | strtst=="54" | strtst=="55" | strtst=="56" | strtst=="57" | strtst=="58" | strtst=="59" | strtst=="60" | strtst=="61" | strtst=="62" | strtst=="63" | strtst=="64"
tab strtst_5064
drop if missing(strtst_5064)

rename ADMSNDT_SNF snf_admsndt
gen year = year(snf_admsndt)
drop if year==2010
gen snf_admsn_year = year
tab snf_admsn_year

* FFS vs. MA vs. Combo flag
gen ffs_ma_combo=.
replace ffs_ma_combo=1 if FFS_enrollment_elig==1
replace ffs_ma_combo=2 if MA_enrollment_elig==1
replace ffs_ma_combo=3 if Combo_FFS_MA==1
label var ffs_ma_combo "Bene cts enroll in FFS(1) MA(2) or combo(3)"
label define ffs_ma_combolbl 1 "FFS cts" 2 "MA cts" 3 "FFS-MA Combo"
label values ffs_ma_combo ffs_ma_combolbl
drop if ffs_ma_combo==3
tab ffs_ma_combo

* Drop FFS claims with missing MedPAR ID
gen missing_medpar=cond(missing(medpar_id_snf),1,0)
tab ffs_ma_combo missing_medpar
drop if missing_medpar==1 & ffs_ma_combo==1
tab ffs_ma_combo missing_medpar

* merge in SNF geocode data from LTC Focus
merge m:1 snf_prvdr_num year using "$raw_data_path/PATH", gen(snf_geo_merge)
keep if snf_geo_merge == 1 | snf_geo_merge == 3
rename fips5 snf_county

* merge in ZIP-code centroids
merge m:1 snf_zipcd year using "$raw_data_path/PATH", gen(zip_geo_merge)
keep if zip_geo_merge == 1 | zip_geo_merge == 3
rename zip_lat snf_zip_lat 
rename zip_lon snf_zip_long
rename snf_lat snf_geo_lat 
rename snf_long snf_geo_long
replace snf_geo_lat = snf_zip_lat if missing(snf_geo_lat)
replace snf_geo_long = snf_zip_long if missing(snf_geo_long)
label var snf_geo_lat "Latitude of SNF - Street or Zip"
label var snf_geo_long "Longitude of SNF - Street or Zip"

gen snf_lat_missing=0
replace snf_lat_missing=1 if missing(snf_geo_lat)
gen snf_long_missing=0
replace snf_long_missing=1 if missing(snf_geo_long)
drop if snf_lat_missing==1|snf_long_missing==1

* Merge in beneficiary ZIP code centroids
drop bene_zip
rename BENE_ZIP bene_zip
merge m:1 bene_zip year using "$raw_data_path/PATH", gen(bene_geo_merge)
keep if bene_geo_merge == 1 | bene_geo_merge==3
rename zip_lat bene_zip_lat
rename zip_lon bene_zip_long

rename SEX RACE, lower
gen female = sex == "2"
replace female = . if sex == "0"
label var female "Beneficiary is female"
gen white = 1 if race == "1"
replace white = 0 if missing(white)
replace white = . if race == "0"
gen black = 1 if race == "2"
replace black = 0 if missing(black)
replace black = . if race == "0"
gen hispanic = 1 if race == "5"
replace hispanic = 0 if missing(hispanic)
replace hispanic = . if race == "0"
gen other = 1 if race == "3" | race == "4" | race == "6"
replace other = 0 if missing(other)
replace other = . if race == "0"

gen snf_admsn_moyr = mofd(snf_admsndt)
format snf_admsn_moyr %tm
egen bene_zip_num = group(bene_zip), label

rename ADMSNDT DSCHRGDT, lower
gen hosp_dsch_missing = 0
replace hosp_dsch_missing = 1 if missing(dschrgdt)
tab year hosp_dsch_missing
rename dschrgdt hosp_dschrgdt
rename admsndt hosp_admsndt
rename DSCHRGDT_SNF snf_dschrgdt
/* 
- Subtracting -1 from the RHS for consistency with other time bound
variables; assume LOS = discharge date - admission date + 1
- snf_dschrgdt is frequently missing in the raw MedPAR data. I'll
infer using snf_admsndt and UTIL_DAY_SNF 
*/ 
replace snf_dschrgdt = snf_admsndt + UTIL_DAY_SNF - 1 if missing(snf_dschrgdt)
ds hosp_dschrgdt hosp_admsndt snf_dschrgdt snf_admsndt, has(type string)
assert "`r(varlist)'" == ""
gen hosp_los = hosp_dschrgdt - hosp_admsndt + 1

summarize UTIL_DAY_SNF
gen snf_los = UTIL_DAY_SNF
replace snf_los = . if ffs_ma_combo != 1
label var hosp_los "Hospital length of stay"
label var snf_los "SNF length of stay"
save "$proc_data_path/final_data_snfclaims.dta", replace

/* Calculates the # of Medicare admissions per SNF for later merge into LTC Focus
Includes both FFS and MA patients
*/
tab year
gen n = 1
collapse (count) snf_med_admns = n, by(snf_prvdr_num year)
label var snf_med_admns "\# SNF admissions per year"
egen snf_prvdr_num2 = group(snf_prvdr_num)
xtset snf_prvdr_num2 year, yearly
gen snf_med_admns_lag = L.snf_med_admns
save "$temp_path/snf_med_admns.dta", replace
tab year



********************************************************************************
// Add in additional variables from LTC Focus //
********************************************************************************
* LTC Focus dataset that spans 2010-2018
use "$raw_data_path/PATH", clear

/* Merge in LTC Focus ID for SNFs (accpt_id) using CMS ID for SNFs (PROV1680) 
NOTE: There are 22 NHs that don't have an accpt_id in the crosswalk. They are only 
present in the dataset once. Missing accpt_ids have been replaced with CMS ID */
tempfile crosswalk
preserve
	import excel "$raw_data_path/PATH", sheet("ACCPT_ID_CROSSWALK") firstrow case(lower) clear
	rename prov1680 snf_prvdr_num
	save `crosswalk'
restore
merge m:1 snf_prvdr_num using `crosswalk'
keep if _merge == 1 | _merge == 3
drop _merge
replace accpt_id = snf_prvdr_num if missing(accpt_id)
gen snf_pct_medicare_adj = paymcare
bysort accpt_id: egen first_year = min(year)
bysort accpt_id: egen last_year = max(year)
gen first_year_z = 1 if paymcare == 0 & year == first_year
bysort accpt_id: egen first_year_zero = min(first_year_z)
gen second_year_z = 1 if paymcare == 0 & year == first_year + 1
bysort accpt_id: egen second_year_zero = min(second_year_z)
gen second_year_t = 1 if paymcare > .10 & year == first_year + 1 & first_year_zero == 1
bysort accpt_id: egen second_year_th = min(second_year_t)
replace snf_pct_medicare_adj = . if year == first_year & second_year_th == 1
egen snf_prvdr_num3 = group(snf_prvdr_num)
xtset snf_prvdr_num3 year, yearly
save "$temp_path/ltcfocus.dta", replace

gen snf_pct_medicare_lag = L.snf_pct_medicare_adj
label var snf_pct_medicare_adj "Pct Medicare (cleaned)"
label var snf_pct_medicare_lag "Pct Medicare of prior year"
label var first_year_z "1 if NH has 0% Medicare in 1st year"
label var first_year_zero "1 if NH has 0% Medicare in 1st year (NH level)"
label var second_year_z "1 if NH has 0% Medicare in 2nd year"
label var second_year_zero "1 if NH has 0% Medicare in 2nd year (NH level)"
label var accpt_id "LTC Focus ID for SNFs"
label var first_year "First year in dataset for SNF"
label var last_year "Last year in dataset for SNF"
label var second_year_t "1 if NH has 0% Med in 1st year & >10% Med in 2nd year"
label var second_year_th "1 if NH has 0% Med in 1st year & >10% Med in 2nd year (NH level)"
label var adm_bed "Admissions (all payers) per bed"

* Merge # Medicare admissions (SNF level)
merge 1:1 snf_prvdr_num year using "$temp_path/PATH"
keep if _merge == 1 | _merge == 3
drop _merge
gen snf_bed_cnt = totbeds
gen snf_admsn_perbed = snf_med_admns / snf_bed_cnt
save "$temp_path/ltcfocus.dta", replace

* Add in new, staying, and exiting NH definitions
egen first_year_global = min(year)
egen last_year_global = max(year)
gen new_nh = 1 if first_year != first_year_global
gen exiting_nh = 1 if last_year != last_year_global
gen staying_nh = 1 if new_nh != 1 & exiting_nh != 1
bysort accpt_id: egen num_years = count(year)
replace new_nh = 0 if num_years >= (last_year_global - first_year_global) / 2 & new_nh == 1 & exiting_nh == 1
replace exiting_nh = 0 if num_years < (last_year_global - first_year_global) / 2 & new_nh == 1 & exiting_nh == 1
foreach x of varlist new_nh exiting_nh staying_nh {
	replace `x' = 0 if missing(`x')
}
gen nh_status = .
replace nh_status = 1 if new_nh == 1	// new nursing homes
replace nh_status = 2 if staying_nh == 1	// staying nursing homes
replace nh_status = 3 if exiting_nh == 1	// exiting nursing homes
label define nh_statusl 1 "New" 2 "Staying" 3 "Exiting"
label values nh_status nh_statusl
label var nh_status "Type of nursing home"
gen snf_admsn_year = year 
drop if year == 2010
save "$temp_path/ltcfocus.dta", replace

/* Merge additional LTC Focus variables back into admission-level dataset */
use "$proc_data_path/final_data_snfclaims.dta", clear
merge m:1 snf_prvdr_num snf_admsn_year using "$temp_path/ltcfocus.dta", ///
	update replace
keep if inlist(_merge, 1, 3, 4, 5)
drop _merge
egen accpt_id_num = group(accpt_id)
save "$proc_data_path/final_data_snfclaims.dta", replace



********************************************************************************
// Add in ZIP rurality data to claims //
********************************************************************************
/*
- the ZIP file includes only rural ZIPs - so any matches (3) are rural ZIPs
- non-matches (1) are non-rural ZIPs
*/
merge m:1 bene_zip using "$raw_data_path/PATH.dta"
keep if _merge == 1 | _merge == 3
gen rural = cond(_merge == 3,1,0)
tab rural
drop _merge



********************************************************************************
// Add in ZIP-year SES data //
********************************************************************************
merge m:1 bene_zip snf_admsn_year using "$raw_data_path/PATH", ///
	generate(ses_merge)
keep if ses_merge == 1 | ses_merge == 3



********************************************************************************
// Finalize outcome and censoring variables //
********************************************************************************
rename DEATH_DT death_dt
gen days_to_death = death_dt - hosp_dschrgdt + 1
drop if days_to_death < 1

* For PAC 90-day payment variable regressions
gen obs_days_90 = .
replace obs_days_90 = 89 if days_to_death >= 89 | days_to_death == .
replace obs_days_90 = days_to_death if days_to_death < 89

* For 30-day readmission regression
gen obs_days_30 = .
replace obs_days_30 = 29 if days_to_death >= 29 | days_to_death == .
replace obs_days_30 = days_to_death if days_to_death < 29

gen daysbtw_hosp_snf = snf_admsndt - hosp_dschrgdt + 1
summ daysbtw_hosp_snf
gen died_in_snf = 0
replace died_in_snf = 1 if days_to_death <= snf_los + daysbtw_hosp_snf
tab died_in_snf if ffs_ma_combo == 1
label variable obs_days_90 "#days post-hosp disch & pre-death the bene is observed; 89 if >89d"
label variable obs_days_30 "#days post-hosp disch & pre-death the bene is observed; 29 if >29d"
label variable died_in_snf "bene died in SNF 0/1"

gen age_cnt = age_adm
label var age_cnt "Age"
label var female "Female"
label var white "White"
label var black "Black"
label var hispanic "Hispanic"
label var other "Other"
gen dual_elig = dual_stus
label var dual_elig "Dual Eligible"
label var pct_pov "\% below poverty"
label var med_hshld_inc "Med hshld income"
label var rural "Rural ZIP"
label var unemp_rate "Unemployment rate"
gen prior_part_a_pmt = total_pmt_amt_prior_yr
label var prior_part_a_pmt "Prior Part A payment"
label var hosp_los "Hospital LOS"
gen snf_in_chain=cond(multifac=="Yes",1,0)
label var snf_in_chain "Part of a chain"
gen snf_for_profit=cond(profit=="Yes",1,0)
label var snf_for_profit "For-profit"
gen snf_hosp_based=cond(hospbase=="Yes",1,0)
label var snf_hosp_based "hospital-based SNF"
label var snf_bed_cnt "\# SNF beds"
gen hosp_drgcd = DRG_CD

/* Revised payment outcomes

90-day index SNF payment - index_snf_pay_90
90-day subsequent PAC payment (combo of subsequent SNF + HHA + IRF) - subseq_pac_90
90-day rehospitalization payment - Pmt_After_Hosp_90_sum_new_Acute
90-day total Part A payment - Pmt_After_Hosp_90_sum_new
*/
count if ffs_ma_combo == 1
count if ffs_ma_combo == 1 & missing(snf_admsndt)
count if ffs_ma_combo == 1 & missing(snf_dschrgdt)
* Prorate index SNF payment to be within 90 days of hospital discharge (doesn't include day 90)
gen index_snf_pay_90 = PMT_AMT_SNF if snf_dschrgdt - hosp_dschrgdt + 1 <= 89
replace index_snf_pay_90 = PMT_AMT_SNF / (snf_dschrgdt - snf_admsndt + 1) * (hosp_dschrgdt + 89 - snf_admsndt + 1) ///
	if snf_dschrgdt - hosp_dschrgdt + 1 > 89
replace index_snf_pay_90 = 0 if PMT_AMT_SNF < 0
gen subseq_snf_90 = Pmt_After_Hosp_90_sum_new_SNF - index_snf_pay_90
replace subseq_snf_90 = 0 if UTIL_DAY_SNF > 89 & ffs_ma_combo == 1
summ subseq_snf_90 if ffs_ma_combo == 1, d
gen subseq_snf_90_neg = cond(subseq_snf_90 < 0, 1, 0)
summ subseq_snf_90_neg if ffs_ma_combo == 1
* Change negative subsequent SNF payment values to 0
replace subseq_snf_90 = 0 if subseq_snf_90 < 0
egen subseq_pac_90 = rowtotal(subseq_snf_90 Pmt_After_Hosp_90_sum_new_HHA Pmt_After_Hosp_90_sum_new_IRF)
/* Change missings for 90-day payment variables to 0s for FFS patients
Confirmed that this is correct */
foreach var of varlist Pmt_After_Hosp_90_sum_new_IRF Pmt_After_Hosp_90_sum_new_HHA ///
	Pmt_After_Hosp_90_sum_new_Other Pmt_After_Hosp_90_sum_new_Acute {
	replace `var' = 0 if missing(`var') & ffs_ma_combo == 1
}

* Old mortality outcome
gen death_30_hosp=DeadIn30Days
label var death_30_hosp "Death within 30 days of hospital discharge"

* New mortality outcome; consistent with other time bound outcomes and doesn't include day 30
gen death_30_hosp_new = 0
replace death_30_hosp_new = 1 if death_dt - hosp_dschrgdt + 1 < 30 & ///
	death_dt - hosp_dschrgdt + 1 > 0

gen losgr90d=cond(snf_los>=90,1,0)
tab losgr90d

gen radm30 = cond(readm_30d_indi_v1_partofdxpr_29d == 1, 1, 0)
label var radm30 "Readmission w/in 30 days of hospital discharge"

* rename comorbidity fields
rename Sum_CHF_all25ICD chf
rename Sum_VALVE_all25ICD valve
rename Sum_PULMCIRC_all25ICD pulmcirc
rename Sum_PERIVASC_all25ICD perivasc
rename Sum_PARA_all25ICD para
rename Sum_NEURO_all25ICD neuro
rename Sum_CHRNLUNG_all25ICD chrnlung
rename Sum_DM_all25ICD dm
rename Sum_DMCX_all25ICD dmcx
rename Sum_HYPOTHY_all25ICD hypothy
rename Sum_RENLFAIL_all25ICD renlfail
rename Sum_LIVER_all25ICD liver
rename Sum_ULCER_all25ICD ulcer
rename Sum_AIDS_all25ICD aids
rename Sum_LYMPH_all25ICD lymph
rename Sum_METS_all25ICD mets
rename Sum_TUMOR_all25ICD tumor
rename Sum_ARTH_all25ICD arth
rename Sum_COAG_all25ICD coag
rename Sum_OBESE_all25ICD obese
rename Sum_WGHTLOSS_all25ICD wgthloss
rename Sum_LYTES_all25ICD lytes
rename Sum_BLDLOSS_all25ICD bldloss
rename Sum_ANEMDEF_all25ICD anemdef
rename Sum_ALCOHOL_all25ICD alcohol
rename Sum_DRUG_all25ICD drug
rename Sum_PSYCH_all25ICD psych
rename Sum_DEPRESS_all25ICD depress
rename Sum_HTN_C_all25ICD htnc

tabstat snf_pct_medicare_adj snf_los death_30_hosp radm30, stat(mean median sd n) by(year) 
tabstat snf_pct_medicare_adj snf_los death_30_hosp radm30, stat(mean median n) by(ffs_ma_combo) 
gen missing_pct_mcr=cond(missing(snf_pct_medicare_adj),1,0)
tab missing_pct_mcr
label var index_snf_pay_90 "90-day index SNF payment"
label var subseq_pac_90 "90-day subsequent PAC payment"
label var Pmt_After_Hosp_90_sum_new_Acute "90-day rehospitalization payment"
label var Pmt_After_Hosp_90_sum_new "90-day total Part A payment"
save "$proc_data_path/final_data_snfclaims.dta", replace



********************************************************************************
// Remove obs with missing variables to obtain final regression sample //
********************************************************************************
* drop claims missing pct_medicare from LTC Focus
drop if missing_pct_mcr==1

gen miss_benezipcoord=cond(missing(bene_zip_lat),1,0)
tab miss_benezipcoord
gen miss_race=cond(missing(white),1,0)
gen miss_comorb=cond(missing(chf),1,0)
gen miss_dual=cond(missing(dual_elig),1,0)
drop if miss_benezipcoord==1
drop if miss_race==1
drop if miss_comorb==1
drop if miss_dual==1

* now find singletons that will drop out of the regressions
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

/* Create categorical variable containing quartiles of % Medicare beneficiaries based 
on pooled distribution across sample years */
tab snf_admsn_year ffs_ma_combo
summ snf_pct_medicare_adj, d
gen snf_pct_medicare_cat = .
replace snf_pct_medicare_cat = 1 if snf_pct_medicare_adj <= `r(p25)'
replace snf_pct_medicare_cat = 2 if snf_pct_medicare_adj > `r(p25)' & snf_pct_medicare_adj <= `r(p50)'
replace snf_pct_medicare_cat = 3 if snf_pct_medicare_adj > `r(p50)' & snf_pct_medicare_adj <= `r(p75)'
replace snf_pct_medicare_cat = 4 if snf_pct_medicare_adj > `r(p75)' & !missing(snf_pct_medicare_adj)
save "$proc_data_path/final_data_snfclaims_analysis_file.dta", replace



********************************************************************************
// Merge snf pct medicare categories back to LTC Focus for use in geonear //
********************************************************************************
keep snf_admsn_year snf_prvdr_num snf_geo_lat snf_geo_long snf_pct_medicare_cat
duplicates drop
merge 1:1 snf_admsn_year snf_prvdr_num using "$temp_path/ltcfocus.dta"
keep if _merge == 2 | _merge == 3
save "$temp_path/ltcfocus.dta", replace


********************************************************************************
********************************************************************************
log close


