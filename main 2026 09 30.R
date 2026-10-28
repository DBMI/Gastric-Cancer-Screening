# this is less of an actual main that runs all code and more of a documentation 
# to the work sheets of this project at least the first 6 sheets can be run separately in this order
#
# Set up environment.
#
rm(list=ls())
library(renv)
library(tidyverse)
root_path <- this.path::this.dir()
path <- str_replace(root_path, "Code$", "Tables/")
setwd(root_path)
#
# Import results of SQL query.
#
df1 <- readxl::read_xlsx(paste0(path, "results.xlsx"))

# Convert string like
df1 <- df1 %>% mutate(across(where(is.character), ~na_if(., "NULL")))

# removing original lab values since we will import from long formatted lab table 
lab_val <- colnames(df1)[str_detect(colnames(df1), "_VALUE$")]
lab_val <- lab_val[!lab_val %in% c("GENDER_SOURCE_VALUE",
                                   "RACE_SOURCE_VALUE",
                                   "ETHNICITY_SOURCE_VALUE")]

lab_vars <- str_remove(lab_val, "_VALUE")
pattern <- paste(lab_vars, collapse = "|")
lab_cols <- colnames(df1)[str_detect(colnames(df1), pattern) & ! str_detect(colnames(df1), "GAST")]

df1 <- df1 %>% select(-all_of(lab_cols))

df1 <- df1 %>% 
  rename(age=AGE_AT_DX_MINUS_1YR) %>% 
  mutate(BMI=coalesce(BMI, BMI_CALCULATED),
         age=as.numeric(age)) %>% 
  select(-ends_with("_DT"), -BMI_CALCULATED) %>% 
  filter(between(as.numeric(age), 40, 75))
#
# Import lab history.
#
dflab <- read.csv(paste0(path, "lab_history.csv"), fileEncoding = "UTF-8-BOM")
lab_dic <- readxl::read_xlsx(paste0(path, "lab_completeness_filtered_ccf_matched.xlsx"))
dfx <- df1 %>% 
  select(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX) %>% 
  left_join(dflab, by = "STUDY_PAT_ID") %>% 
  filter(PCP_DT_PRIOR_TO_DX>=LAB_DT) %>% 
  mutate(lab_age=difftime(PCP_DT_PRIOR_TO_DX, LAB_DT, units = 'days')) %>% 
  filter(lab_age<=1826) %>% 
  inner_join(lab_dic %>% 
               select(LAB_GROUP, MEASUREMENT_CONCEPT_ID), 
             by = "MEASUREMENT_CONCEPT_ID")

# longitudinal lab processing .... 
dflong <- dfx %>% 
  select(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX, LAB_DT, LAB_GROUP, LAB_VALUE) %>% 
  group_by(STUDY_PAT_ID, LAB_GROUP) %>% 
  mutate(lab_first_dt=min(LAB_DT), 
         lab_last_dt=max(LAB_DT), 
         dif_year= as.numeric(difftime(lab_last_dt, lab_first_dt, units = 'days'))/365,
         first_VALUE_SOURCE_VALUE=ifelse(LAB_DT==lab_first_dt, LAB_VALUE, NA),
         last_VALUE_SOURCE_VALUE=ifelse(LAB_DT==lab_last_dt, LAB_VALUE, NA), 
         first_VALUE_SOURCE_VALUE=ifelse(any(!is.na(first_VALUE_SOURCE_VALUE)), first_VALUE_SOURCE_VALUE[!is.na(first_VALUE_SOURCE_VALUE)], NA),
         last_VALUE_SOURCE_VALUE=ifelse(any(!is.na(last_VALUE_SOURCE_VALUE)), last_VALUE_SOURCE_VALUE[!is.na(last_VALUE_SOURCE_VALUE)], NA)) %>% 
  slice_head(n=1) %>% 
  ungroup() %>% 
  mutate(perc_chng_per_yr=((as.numeric(last_VALUE_SOURCE_VALUE)-as.numeric(first_VALUE_SOURCE_VALUE))/as.numeric(first_VALUE_SOURCE_VALUE)/dif_year)*100) %>% 
  filter(lab_first_dt!=lab_last_dt, 
         dif_year >=0.25) 

dfwide <- dflong %>% 
  select(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX, LAB_GROUP, perc_chng_per_yr) %>% 
  pivot_wider(id_cols = c(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX), names_from = LAB_GROUP, 
              values_from = perc_chng_per_yr, names_prefix = 'lab_perc_chng_')


### combining last and per change labs into main 
dflast <- dfx %>% 
  group_by(STUDY_PAT_ID, LAB_GROUP) %>% 
  slice_max(LAB_DT, with_ties = FALSE) %>% 
  pivot_wider(id_cols =c(STUDY_PAT_ID, PCP_DT_PRIOR_TO_DX), 
              names_from = LAB_GROUP, values_from = LAB_VALUE, 
              names_prefix = "lab_last_")


df1 <- df1 %>% 
  left_join(dflast) %>% 
  left_join(dfwide)


epis<- unique(df1$STUDY_PAT_ID)
## getting patient state ----

lab_vars <- colnames(df1)[str_detect(colnames(df1), "^lab_")]
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
    Cohort=as.factor(COHORT)) %>% 
  select(Cohort, STUDY_PAT_ID, STUDY_STATE, 
         all_of(c(dem_vars, dx_vars, med_vars, lab_vars)))

df1 <- df1 %>% 
  mutate(across(all_of(lab_vars), as.numeric))

## need to regroup some vars ------
df1$GENDER <- ifelse(is.na(df1$GENDER) | df1$GENDER =="No matching concept", 
                     names(which.max(table(df1$GENDER))), # R doesn't have statistic mode !!! 
                     df1$GENDER )
df1$GENDER <- toupper(df1$GENDER)
df1$ETHNICITY <- ifelse(is.na(df1$ETHNICITY)| 
                          df1$ETHNICITY %in% c("Declined", "Unavailable", "Unreported (Patient refused or chose not to discl*"),
                        "Unknown", ifelse(df1$ETHNICITY %in% c("Other Hispanic, Latino(a) or Spanish origin",
                                                                "Mexican, Mexican American, Chicano(a)"), "Hispanic",
                                          ifelse(df1$ETHNICITY %in% c("Not Hispanic, Latino(a), or Spanish origin"), "Not Hispanic", NA)))
df1$RACE <- case_when(is.na(df1$RACE)| df1$RACE=="No matching concept" ~ "Unknown", 
                      .default = df1$RACE)
df1$RACE <- case_when(df1$RACE %in% c("Other Race or Mixed Race",
                                      "Multirace")~"Unknown",
                      .default = df1$RACE)
df1$ALCOHOL <- case_when(df1$ALCOHOL %in% c("Monthly or less", "2-3 times a week", "1 or 2", "2-4 times a month",
                                            "4 or more times a week", "Monthly")~1,
                         df1$ALCOHOL %in% c("NULL", "Not asked", "Patient declined")~NA,
                         df1$ALCOHOL == "Never"~0,
                         .default = NA)

df1$TOBACCO <- ifelse(is.na(df1$TOBACCO), 0, 1)

### dropping vars with one level 
dfx <- apply(df1, MARGIN = 2, function(x){length(unique(x))}) 
not_catching <- names(dfx[dfx==1])
print(not_catching)

df1 <- df1 %>% 
  select(-all_of(not_catching), -STUDY_PAT_ID, -STUDY_STATE)

df1 <- df1 %>% # these variables were dropped (not catching) from the first version 
  # John re ran and now catching, however, CMUC don't have them in their data so we drop for now
  select(-any_of(c("HEREDITARY_CANCER_SYNDROMES",
                   "PANCREATIC_DISORDERS","CHRONIC_PANCREATITIS",
                   "JAUNDICE","HORMONE")))
#
# Exporting output files.
#
dictionary <- readxl::read_xlsx("E:\\DBMI Research\\Gastric-Cancer-Screening\\R Tables\\data_dictonary_v2.xlsx")
dictionary_names <- dictionary$col_names
df1 <- df1 %>% select(all_of(dictionary_names)) %>% relocate(all_of(dictionary_names))
writexl::write_xlsx(df1, paste0(path, "ucsd_cohort.xlsx"))
write.csv(df1, paste0(path, "ucsd_cohort.csv"), row.names = FALSE)
# exporting structure / dictionary 

dfx <- lapply(df1, function(x){ifelse(is.factor(x) | is.character(x)|
                                        length(unique(x))==2, 
                                      paste(unique(x[!is.na(x)]), collapse = "--"), "NUMERIC")})
dfx <- do.call(rbind, dfx) %>% as.data.frame() %>%  
  rownames_to_column(var = 'col_names') %>% 
  relocate(col_names)
writexl::write_xlsx(dfx, paste0(path, "ucsd_dictionary.xlsx"))
