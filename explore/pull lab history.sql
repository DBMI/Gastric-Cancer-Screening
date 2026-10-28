/*
** pull lab history.sql
** PI: Dr. Shailja Shah, MD, MPH , s6shah@health.ucsd.edu
** Author: John McMichael, Associate Chief Medical Information Officer, Cleveland Clinic, McMichJ2@ccf.org
** Adapted by: Kevin J. Delaney, kjdelaney@ucsd.edu
** Database: OMOP
*/
USE [OMOP];

DROP TABLE IF EXISTS #LAB_HISTORY;

select 
	a.study_pat_id, 
	b.measurement_date as LAB_DT,
	b.value_source_value as LAB_VALUE, 
	measurement_source_value, 
	measurement_source_concept_id,
	measurement_concept_id,
	ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
INTO #LAB_HISTORY
FROM #OMOP_COHORT a 
INNER JOIN measurement b 
	ON a.study_pat_id = b.person_id
   AND CAST(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
   AND b.value_source_value IS NOT NULL;

CREATE NONCLUSTERED INDEX IX ON #LAB_HISTORY (study_pat_id);
