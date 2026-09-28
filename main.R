# this is less of an actual main that runs all code and more of a documentation 
# to the work sheets of this project at least the first 6 sheets can be run separately in this order
rm(list=ls())
library(tidyverse)
source("H:/R functions/SF_connection.R")
root_path <- this.path::this.dir()
path <- str_replace(root_path, "Code$", "Tables/")
setwd(root_path)

df1 <- readxl::read_xlsx(paste0(path, "OMOP_CCF_GASTRIC_CANCER_QUERY_08072026.docx.xlsx" ))

# removing original lab values since we will import from long formated lab table 
lab_val <- colnames(df1)[str_detect(colnames(df1), "_VALUE$")]
lab_val <- lab_val[!lab_val %in% c("GENDER_SOURCE_VALUE",
                                   "RACE_SOURCE_VALUE",
                                   "ETHNICITY_SOURCE_VALUE")]

lab_vars <- str_remove(lab_val, "_VALUE")
pattern <- paste(lab_vars, collapse = "|")
lab_cols <- colnames(df1)[str_detect(colnames(df1), pattern) & ! str_detect(colnames(df1), "GAST")]

df1 <- df1 %>% select(-all_of(lab_cols))

lab_dic <- readxl::read_xlsx(paste0(path, "lab_completeness_filtered_ccf_matched.xlsx"))

df1 <- df1 %>% 
  rename(age=AGE_AT_DX_MINUS_1YR, Cohort="'STUDY'") %>% 
  mutate(BMI=coalesce(BMI, BMI_CALCULATED)) %>% 
  select(-ends_with("_DT"), -BMI_CALCULATED) %>% 
  filter(between(age, 40, 75))

# labs 
dflab <- tbl(connection, sql('SELECT * FROM INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_LABS')) %>% 
  collect()
dfx <- df1 %>% 
  select(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX) %>% 
  left_join(dflab, by = "STUDY_PAT_ID") %>% 
  filter(PCP_DT_PRIOR_TO_DX>=MEASUREMENT_DATE) %>% 
  mutate(lab_age=difftime(PCP_DT_PRIOR_TO_DX, MEASUREMENT_DATE, units = 'days')) %>% 
  filter(lab_age<=1826) %>% 
  inner_join(lab_dic %>% 
               select(lab_group, measurement_concept_id), 
             by = c("MEASUREMENT_CONCEPT_ID"="measurement_concept_id"))

# longitudinal lab processing .... 
dflong <- dfx %>% 
  select(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX, MEASUREMENT_DATE, lab_group, VALUE_SOURCE_VALUE) %>% 
  group_by(STUDY_PAT_ID, lab_group) %>% 
  mutate(lab_first_dt=min(MEASUREMENT_DATE), 
         lab_last_dt=max(MEASUREMENT_DATE), 
         dif_year= as.numeric(difftime(lab_last_dt, lab_first_dt, units = 'days'))/365,
         first_VALUE_SOURCE_VALUE=ifelse(MEASUREMENT_DATE==lab_first_dt, VALUE_SOURCE_VALUE,NA),
         last_VALUE_SOURCE_VALUE=ifelse(MEASUREMENT_DATE==lab_last_dt, VALUE_SOURCE_VALUE, NA), 
         first_VALUE_SOURCE_VALUE=ifelse(any(!is.na(first_VALUE_SOURCE_VALUE)), first_VALUE_SOURCE_VALUE[!is.na(first_VALUE_SOURCE_VALUE)], NA),
         last_VALUE_SOURCE_VALUE=ifelse(any(!is.na(last_VALUE_SOURCE_VALUE)), last_VALUE_SOURCE_VALUE[!is.na(last_VALUE_SOURCE_VALUE)], NA)) %>% 
  slice_head(n=1) %>% 
  ungroup() %>% 
  mutate(perc_chng_per_yr=((as.numeric(last_VALUE_SOURCE_VALUE)-as.numeric(first_VALUE_SOURCE_VALUE))/as.numeric(first_VALUE_SOURCE_VALUE)/dif_year)*100) %>% 
  filter(lab_first_dt!=lab_last_dt, 
         dif_year >=0.25) 

dfwide <- dflong %>% 
  select(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX, lab_group, perc_chng_per_yr) %>% 
  pivot_wider(id_cols = c(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX), names_from = lab_group, 
              values_from = perc_chng_per_yr, names_prefix = 'lab_perc_chng_')


### combining last and per change labs into main 

dflast <- dfx %>% 
  group_by(STUDY_PAT_ID, lab_group) %>% 
  slice_max(MEASUREMENT_DATE, with_ties = FALSE) %>% 
  pivot_wider(id_cols =c(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX), 
              names_from = lab_group, values_from = VALUE_SOURCE_VALUE, 
              names_prefix = "lab_last_")


df1 <- df1 %>% 
  left_join(dflast) %>% 
  left_join(dfwide)


epis<- unique(df1$STUDY_PAT_ID)
## getting patient state ----

lab_vars <- colnames(df1)[str_detect(colnames(df1), "^lab_")]
# lab_val <- lab_val[!lab_val %in% c("GENDER_SOURCE_VALUE",
#                                       "RACE_SOURCE_VALUE",
#                                       "ETHNICITY_SOURCE_VALUE")]

# other_dt <- colnames(df1)[which(str_detect(colnames(df1), "_DT$")& 
#                                   !str_detect(colnames(df1), paste0(labs_tx, collapse = "|")))]


dx_vars <- c("FAM_HX_CA","PERSONAL_HX_CA_ICD","DIABETES",
             "HYPERTENSION", "HYPERCHOLESTEROLEMIA", "CORONARY_ARTERY_DISEASE",
             "CIRRHOSIS", "EMPHYSEMA","STROKE", "GASTRIC_ULCER",
             "VIRAL_HEPATITIS", "DEPRESSION","IBD", "CHRONIC_RESPIRATORY_DISEASE",
             "CHRONIC_RENAL_DISEASE", "UPPER_GASTROINTESTINAL_DISEASE",
             "LOWER_GASTROINTESTINAL_DISEASE", "GALLSTONE_DISORDERS",
             "HEREDITARY_CANCER_SYNDROMES", "PEPTIC_ULCER",
             "DEEP_VEIN_THROMBOSIS", "PULMONARY_EMBOLISM",
             "PERSONAL_HX_GALLSTONES", "PERSONAL_HX_CHOLECYSTECTOMY",
             "VITAMIN_D_DEFICIENCY", "PANCREATIC_DISORDERS",
             "CHRONIC_PANCREATITIS", "ACUTE_PANCREATITIS",
             "PSEUDOCYST", "BILIARY_TRACT_DISEASE","ABDOMINAL_PAIN", 
             "JAUNDICE","DYSPEPSIA", "NAUSEA_AND_VOMITING",
             "WEIGHT_LOSS", "BACK_PAIN","CONSTIPATION", "DIARRHEA",
             "MALAISE_FATIGUE")
med_vars <- c( "ASPIRIN","NSAID","BETA_BLOCKER",
               "METFORMIN","INSULIN",
               "STATIN","PPI",
               "SULFONYLUREA","DIURETICS",
               "ANTIPSYCHOTICS","HORMONE")
yn_vars <- c(dx_vars, med_vars)
df1 <- df1 %>% 
  mutate(across(all_of(yn_vars), ~ifelse(!is.na(.x), 1, 0)))
dem_vars <- c( "ETHNICITY"="ETHNICITY_SOURCE_VALUE","GENDER",
               "RACE","age","BMI","ALCOHOL","TOBACCO")


df1 <- df1 %>% 
  mutate(
    Cohort=as.factor(Cohort)) %>% 
  select(Cohort,  STUDY_PAT_ID ,STUDY_STATE, 
         all_of(c(dem_vars, dx_vars, med_vars, lab_vars)))

df1 <- df1 %>% 
  mutate(across(all_of(lab_vars), as.numeric))

## need to regroup some vars ------

df1$GENDER <- ifelse(is.na(df1$GENDER) | df1$GENDER =="No matching concept", 
                     names(which.max(table(df1$GENDER))), # R doesn't have statistic mode !!! 
                     df1$GENDER )
df1$ETHNICITY <- ifelse(is.na(df1$ETHNICITY)| 
                          df1$ETHNICITY %in% c("Declined", "Unavailable"),
                        "Unknown", df1$ETHNICITY)
df1$RACE <- case_when(is.na(df1$RACE)| df1$RACE=="No matching concept" ~ "Unknown", 
                      .default = df1$RACE)
df1$ALCOHOL <- ifelse(is.na(df1$ALCOHOL), 0, 1)
df1$TOBACCO <- ifelse(is.na(df1$TOBACCO), 0, 1)

### dropping vars with one level 
dfx <- apply(df1, MARGIN = 2, function(x){length(unique(x))}) 
not_catching <- names(dfx[dfx==1])
print(not_catching)

df1 <- df1 %>% 
  select(-all_of(not_catching), -STUDY_PAT_ID, -STUDY_STATE)

writexl::write_xlsx(df1, paste0(path, "cchs_cohort.xlsx"))
write.csv(df1, paste0(path, "cchs_cohort.csv"))
# exporting structure / dictionary 

dfx <- lapply(df1, function(x){ifelse(is.factor(x) | is.character(x)|
                                        length(unique(x))==2, 
                                      paste(unique(x[!is.na(x)]), collapse = "--"), "NUMERIC")})
dfx <- do.call(rbind, dfx) %>% as.data.frame() %>%  
  rownames_to_column(var = 'col_names') %>% 
  relocate(col_names)
writexl::write_xlsx(dfx, paste0(path, "data_dictonary.xlsx"))



# source("H:/R functions/auto_uni.R")
# stat_table <- auto_uni(df1 %>% 
#                          select(-STUDY_PAT_ID, -STUDY_STATE), dep_var= "Cohort")
# #writexl::write_xlsx(stat_table, paste0(path, "stat_tabel_with_missing_v4.xlsx"))
# 
# 
# dfmiss <- apply(df1, MARGIN = 2, function(x){mean(is.na(x))}) %>% as.data.frame() %>% 
#   rownames_to_column(var = 'variable')

#"Fam_HX_Cancer","PERSONAL_HX_Cancer_ICD","PERSONAL_HX_Cancer_MH",
#  "Diabetes","Hypertension","Hypercholesterolemia",
#  "Coronary_artery_disease","Cirrhosis","Emphysema",
#  "Stroke","Gastric_Ulcer","Viral_hepatitis",
#  "Depression","IBD","Chronic_respiratory_disease",
#  "Chronic_renal_disease","Upper_Gastrointestinal_Disease",
#  "Lower_Gastrointestinal_Disease","Gallstone_disorders",
#  "Hereditary_cancer_syndromes","Peptic_ulcer",
#  "Deep_vein_thrombosis","Pulmonary_Embolism",
#  "PERSONAL_HX_Gallstones","PERSONAL_HX_cholecystectomy_ICD",
#  "PERSONAL_HX_cholecystectomy_MH","Vitamin_D_deficiency",
#  "Pancreatic_Disorders","Chronic_pancreatitis",
#  "Acute_pancreatitis","Pseudocyst",
#  "Biliary_tract_disease","Abdominal_pain",
#  "Jaundice","Dyspepsia","Nausea_and_vomiting",
#  "Weight_loss","Back_pain","Constipation",
#  "Diarrhea","Malaise_fatigue")

#med_vars <- names(df1)[str_detect(tolower(names(df1)), "_start")] # no meds ? 
