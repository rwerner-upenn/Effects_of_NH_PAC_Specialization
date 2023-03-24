********************************************************************************
********************************************************************************
********************************************************************************

/* Nate Apathy and Zach Templeton

Run do file for The Effects of Nursing Home Specialization in Post-Acute Care
*/



********************************************************************************
// Set file paths //
********************************************************************************
* Base directory for project
cd "PROJECT_PATH"

* Directory containing raw datasets
global raw_data_path "01_data"

* Directory containing all do-files
global script_path "02_script/SCRIPT_PATH"

* Directory containing analytic dataset
global proc_data_path "03_output/01_analytic_data"

* Directory containing log files
global log_path "02_script/LOG_PATH"

* Directory containing temporary datasets
global temp_path "03_output/06_temp"

* Directory containing tables
global table_path "02_script/TABLES_PATH"

* Directory containing graphs
global graph_path "03_output/03_graphs"



********************************************************************************
// Use Stata packages //
********************************************************************************
cap adopath - SITE
cap adopath - PERSONAL
cap adopath - OLDPLACE
cap adopath - "PACKAGE_PATH"
sysdir set PLUS "PLUS_PATH"



********************************************************************************
// Prepare Stata //
********************************************************************************
version 16
cap log close
clear all

* Set date
global date = subinstr("$S_DATE", " ", "_", .)

* Specify screen width for log files
set linesize 255

set more off
set varabbrev off
set seed 1000

* Drop everything in Mata
matrix drop _all



********************************************************************************
// Run do-files //
** workflow:
* uncomment the do files you want to run, save
* submit this run script to batch server
********************************************************************************
/* Main analysis */
// do "$script_path/1_process_data.do"
// do "$script_path/2_run_geonear.do"
// do "$script_path/3_summ_stat.do"
// do "$script_path/4_run_regressions.do"
// do "$script_path/sample.do"
do "$script_path/revisions.do"
// do "$script_path/jhe_rr_new_fig_tab.do"


/* Specification tests and appendix analyses */
// do "$script_path/5a_sens_nonlin.do"
// do "$script_path/5b_sens_hospsnf.do"
// do "$script_path/5e_sens_farsnf.do"
// do "$script_path/5h_sens_near_hosp.do"
// do "$script_path/5j_sens_hosp_fe.do"


/* Specification test - 1-year lagged % Medicare */
// do "$script_path/1_process_data_lagtrt.do"
// do "$script_path/2_run_geonear_lagtrt.do"
// do "$script_path/4_run_regressions_lagtrt.do"


/* Specification test - two log distance instruments based on a binary classification 
of specialization at the 75th percentile */
// do "$script_path/1_process_data_p75cut.do"
// do "$script_path/2_run_geonear_p75cut.do"
// do "$script_path/4_run_regressions_p75cut.do"


