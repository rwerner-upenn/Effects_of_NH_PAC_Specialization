## Tables and Figures for JHE Submission
library(tidyverse)
library(readr)
library(dplyr)
library(ggplot2)

##snf-year level data derived from admissions dataset
snf_yr_cats <- read_csv("SNF_YEAR_CATEGORY_DATA_PATH")

## Appendix Figure 1a. Share of Nursing Homes by Year and Quartile of PAC Specialization
snf_yr_cats %>%
  group_by(snf_admsn_year,snf_pct_medicare_cat) %>%
  summarize(n_snfs=n_distinct(snf_prvdr_num)) %>%
  group_by(snf_admsn_year) %>%
  mutate(pct_snfs=n_snfs/sum(n_snfs),
         cat2=factor(snf_pct_medicare_cat,levels = c(4,3,2,1),labels = c("Top (Q4)","3rd","2nd","Bottom (Q1)"))) %>%
  ggplot(aes(x=snf_admsn_year,y=pct_snfs)) +
  geom_col(aes(fill=factor(cat2)),
           position = position_stack(),
           show.legend = T) +
  geom_label(aes(label=paste0(round(pct_snfs*100,1),"%")),
            position = position_stack(vjust = 0.5),show.legend = F) +
  theme_bw() +
  scale_x_continuous(breaks = c(2011:2018))+
  scale_y_continuous(labels = scales::label_percent()) +
  scale_fill_grey() +
  labs(x=NULL,y="% of Nursing Homes",fill="Nursing Home\nSpecialization\nQuartile")

## Appendix Figure 1b. Share of Nursing Home Traditional Medicare Admissions by Year and Quartile of PAC Specialization
fig2dat <- read_csv("PCT_ADM_YR_SPEC_DATA_PATH")
fig2dat %>% group_by(snf_pct_medicare_cat) %>% summarize(adms=sum(admcount)) %>% ungroup() %>% mutate(tot=sum(adms))

fig2dat %>%
  group_by(snf_admsn_year) %>%
  mutate(pct_adm=admcount/sum(admcount),
         cat2=factor(snf_pct_medicare_cat,levels = c(4,3,2,1),labels = c("Top (Q4)","3rd","2nd","Bottom (Q1)"))) %>%
  ggplot(aes(x=snf_admsn_year,y=pct_adm)) +
  geom_col(aes(fill=factor(cat2)),
           position = position_stack(),
           show.legend = T) +
  geom_label(aes(label=paste0(round(pct_adm*100,1),"%")),
             position = position_stack(vjust = 0.5),show.legend = F) +
  theme_bw() +
  scale_x_continuous(breaks = c(2011:2018))+
  scale_y_continuous(labels = scales::label_percent()) +
  scale_fill_grey() +
  labs(x=NULL,y="% of FFS Admissions",fill="Nursing Home\nSpecialization\nQuartile")

## Figure 2. Test of the First Stage: Proportion of Admissions to Highly Specialized Nursing Homes by Within-ZIP Distances
fig3dat <- read_csv("IV_FIG_DATA_PATH")
quantile(fig3dat$med_log_mi_to_snf4,0.95)

fig3dat %>%
  filter(med_log_mi_to_snf4<quantile(med_log_mi_to_snf4,0.95)) %>%
  mutate(grplbl=case_when(iv_group=="< log dist"~"a. Patients with distance to nearest Q4 nursing home < ZIP-level median",
                          iv_group=="> log dist"~"c. Patients with distance to nearest Q4 nursing home > ZIP-level median",
                          iv_group=="Med log dist"~"b. Patients with distance to nearest Q4 nursing home = ZIP-level median")) %>%
  ggplot() +
  geom_smooth(aes(x=med_log_mi_to_snf4,y=prop_adm_cat4,
                  group=grplbl,
                  linetype=grplbl),
              color="black",
              size=1,
              se=T) +
  #coord_cartesian(xlim=c(0,5)) +
  scale_y_continuous(labels = scales::label_percent()) +
  #scale_color_grey() +
  scale_linetype_manual(values=c("solid","dashed","dotted")) +
  theme_bw() +
  theme(legend.position = c(0.65,0.75),
        legend.text = element_text(size=12)) +
  guides(color="none") +
  labs(caption="Note: Plot excludes ZIPs with median log distance to Q4 nursing home >= 95th percentile (4.48)",
       x="Median log distance to nearest quartile 4 (highly specialized) nursing home",
       y="% of admissions to quartile 4 (highly specialized) nursing home",
       linetype="Patient group")


## ZIP code MA penetration by Within-ZIP Distances to Highly Specialized Nursing Homes
appdxfigs <- read_csv("MA_PENETRATION_DATA_PATH")
quantile(appdxfigs$med_log_mi_to_snf4,0.95)

appdxfigs %>%
  filter(med_log_mi_to_snf4<quantile(med_log_mi_to_snf4,0.95)) %>%
  mutate(grplbl=case_when(iv_group=="< log dist"~"a. Patients with distance to nearest Q4 nursing home < ZIP-level median",
                          iv_group=="> log dist"~"c. Patients with distance to nearest Q4 nursing home > ZIP-level median",
                          iv_group=="Med log dist"~"b. Patients with distance to nearest Q4 nursing home = ZIP-level median")) %>%
  ggplot() +
  geom_smooth(aes(x=med_log_mi_to_snf4,y=ma_pct,
                  group=grplbl,
                  linetype=grplbl),
              color="black",
              size=1,
              se=T) +
  #coord_cartesian(xlim=c(0,5)) +
  scale_y_continuous(labels = waiver()) +
  #scale_color_grey() +
  scale_linetype_manual(values=c("solid","dashed","dotted")) +
  theme_bw() +
  theme(legend.position = c(0.4,0.25),
        legend.text = element_text(size=10)) +
  guides(color="none") +
  labs(x="Median log distance to nearest quartile 4 (highly specialized) nursing home",
       y="ZIP code MA penetration (%)",
       linetype="Patient group")


## ZIP code share of SNF PAC by Within-ZIP Distances to Highly Specialized Nursing Homes
appdxfigs %>%
  filter(med_log_mi_to_snf4<quantile(med_log_mi_to_snf4,0.95)) %>%
  mutate(grplbl=case_when(iv_group=="< log dist"~"a. Patients with distance to nearest Q4 nursing home < ZIP-level median",
                          iv_group=="> log dist"~"c. Patients with distance to nearest Q4 nursing home > ZIP-level median",
                          iv_group=="Med log dist"~"b. Patients with distance to nearest Q4 nursing home = ZIP-level median")) %>%
  ggplot() +
  geom_smooth(aes(x=med_log_mi_to_snf4,y=pct_snf_dschrg,
                  group=grplbl,
                  linetype=grplbl),
              color="black",
              size=1,
              se=T) +
  #coord_cartesian(xlim=c(0,5)) +
  scale_y_continuous(labels = waiver()) +
  #scale_color_grey() +
  scale_linetype_manual(values=c("solid","dashed","dotted")) +
  theme_bw() +
  theme(legend.position = c(0.6,0.85),
        legend.text = element_text(size=10)) +
  guides(color="none") +
  labs(x="Median log distance to nearest quartile 4 (highly specialized) nursing home",
       y="Share of hospital discharges to SNF",
       linetype="Patient group")
