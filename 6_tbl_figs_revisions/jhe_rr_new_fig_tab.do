cap log close
log using "$log_path/jhe_rr_new_fig_tab_log.log", replace

/* Create requested figures and tables for JHE R&R

Zach Templeton
*/



********************************************************************************
// Within-ZIP variation in distances over time (Appendix Figure 2) //
********************************************************************************
use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
keep if ffs_ma_combo == 1
keep bene_zip bene_zip_num snf_admsn_year mi_to_snf1 mi_to_snf2 mi_to_snf3 mi_to_snf4 ///
	log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4
duplicates drop
xtset bene_zip_num snf_admsn_year, yearly
foreach var of varlist mi_to_snf1 mi_to_snf2 mi_to_snf3 mi_to_snf4 log_mi_to_snf1 log_mi_to_snf2 log_mi_to_snf3 log_mi_to_snf4 {
	gen diff_`var' = `var' - L.`var'
}
kdensity diff_log_mi_to_snf1, xtitle("Within-ZIP changes in log distance to nearest Q1 SNF") ///
	ylabel(0(.2)1, angle(0)) xlabel(-6(2)6) graphregion(color(white))
graph export "$graph_path/chg_dist_quart1_$date.png", as(png) width(1200) replace
kdensity diff_log_mi_to_snf2, xtitle("Within-ZIP changes in log distance to nearest Q2 SNF") ///
	ylabel(0(.2)1, angle(0)) xlabel(-6(2)6) graphregion(color(white))
graph export "$graph_path/chg_dist_quart2_$date.png", as(png) width(1200) replace
kdensity diff_log_mi_to_snf3, xtitle("Within-ZIP changes in log distance to nearest Q3 SNF") ///
	ylabel(0(.2)1, angle(0)) xlabel(-6(2)6) graphregion(color(white))
graph export "$graph_path/chg_dist_quart3_$date.png", as(png) width(1200) replace
kdensity diff_log_mi_to_snf4, xtitle("Within-ZIP changes in log distance to nearest Q4 SNF")	///
	ylabel(0(.2)1, angle(0)) xlabel(-6(2)6) graphregion(color(white))
graph export "$graph_path/chg_dist_quart4_$date.png", as(png) width(1200) replace



********************************************************************************
// Mean % Medicare over time and distribution of changes in % Medicare (Figure 1)
********************************************************************************
use "$temp_path/ltcfocus.dta", clear
drop if missing(snf_pct_medicare_cat)
tab year
summ snf_pct_medicare_adj, d
gen chg_pct_medicare = snf_pct_medicare_adj - snf_pct_medicare_lag
summ chg_pct_medicare
count if (chg_pct_medicare > 50 | chg_pct_medicare < -50) & !missing(chg_pct_medicare)
kdensity chg_pct_medicare if inrange(chg_pct_medicare, -50, 50), ///
	xtitle("Within-SNF changes in % Medicare") xlabel(-50(10)50) ///
	ylabel(, angle(0)) graphregion(color(white))
graph export "$graph_path/chg_pct_medicare_$date.png", as(png) width(1200) replace

collapse (mean) mean_pct_med = snf_pct_medicare_adj, by(year)
format %9.1fc mean_pct_med
twoway connected mean_pct_med year, ylabel(, angle(0)) lcolor(blue) mcolor(blue) ///
	ylabel(10(2)20) xlabel(2011(1)2018) xtitle("Year") ytitle("Mean % Medicare") ///
	graphregion(color(white)) mlabel(mean_pct_med) mlabposition(6)
graph export "$graph_path/pct_med_over_time_$date.png", as(png) width(1200) replace



********************************************************************************
// Create figures analogous to Figure 2 //
********************************************************************************
/* Calculate ZIP code share of SNF PAC (# going to SNF / # hospital discharges) */
use "PATH_TO_ALL_PAC_DTA", clear
gen one = 1
summ HOME PAC SNF IRF HHA
codebook SNF
keep BENE_ZIP dschrg_year SNF one
rename BENE_ZIP bene_zip
rename SNF snf
keep if inrange(dschrg_year, 2011, 2018)
collapse (sum) tot_dschrg = one tot_dschrg_to_snf = snf, by(bene_zip dschrg_year)
tab dschrg_year
gen pct_snf_dschrg = tot_dschrg_to_snf / tot_dschrg * 100
tabstat pct_snf_dschrg, by(dschrg_year) stat(mean sd min max count)
rename dschrg_year snf_admsn_year
save "$temp_path/snf_dschrg_zip_year.dta", replace

use "$proc_data_path/final_data_snfclaims_analysis_file.dta", clear
merge m:1 bene_zip snf_admsn_year using "$temp_path/ma_pen_zip_year.dta"
keep if _merge == 3
drop _merge
merge m:1 bene_zip snf_admsn_year using "$temp_path/snf_dschrg_zip_year.dta"
keep if _merge == 3
drop _merge

keep if ffs_ma_combo == 1
keep bene_zip med_log_mi_to_snf4 iv_group ma_pct pct_snf_dschrg
duplicates drop
export delimited using "$graph_path/mapen_snfdschrg_fig2.csv", replace


********************************************************************************
********************************************************************************
log close
