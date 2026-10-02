/*
	READ LAB CONCEPT IDs.
*/
DROP TABLE IF EXISTS #LABS_LIST;
CREATE TABLE #LABS_LIST
	(CONCEPT_ID varchar(12),
	 LAB_NAME varchar(100),
	 LAB_GROUP varchar(20))
:setvar path "E:\DBMI Research\Gastric-Cancer-Screening\data\"
:r $(path)\labs_edited_list.sql

CREATE NONCLUSTERED INDEX IX ON #LABS_LIST (CONCEPT_ID);
/*
	READ MEDICATION CONCEPT IDs.
*/
DROP TABLE IF EXISTS #MEDICATIONS_LIST;
CREATE TABLE #MEDICATIONS_LIST
	(ROUTE_CONCEPT_ID varchar(12),
	 DRUG_CONCEPT_ID varchar(12),
	 DRUG_CLASS varchar(20))
:setvar path "E:\DBMI Research\Gastric-Cancer-Screening\data\"
:r $(path)\OMOP_MEDICATIONS_list.sql

CREATE NONCLUSTERED INDEX IX ON #MEDICATIONS_LIST (DRUG_CONCEPT_ID);
SELECT COUNT(DISTINCT DRUG_CONCEPT_ID) AS "Num medication concept IDs imported" FROM #MEDICATIONS_LIST;

-- Augment with the "official" lab concept name.
DROP TABLE IF EXISTS #MEDICATIONS_LIST_AUGMENTED;
SELECT
	ml.ROUTE_CONCEPT_ID,
	ml.DRUG_CONCEPT_ID,
	ml.DRUG_CLASS,
	c.concept_name
INTO #MEDICATIONS_LIST_AUGMENTED
FROM #MEDICATIONS_LIST ml
JOIN concept c
	ON ml.DRUG_CONCEPT_ID = c.concept_id;

CREATE NONCLUSTERED INDEX IX ON #MEDICATIONS_LIST_AUGMENTED (DRUG_CONCEPT_ID);
/*
	READ COMORBIDITY CONCEPT IDs.
*/
DROP TABLE IF EXISTS #COMORBIDITIES_LIST;
CREATE TABLE #COMORBIDITIES_LIST
	(CONDITION_SOURCE_VALUE varchar(12),
	 CONDITION_CONCEPT_ID varchar(12),
	 CONDITION_NAME varchar(50))
:setvar path "E:\DBMI Research\Gastric-Cancer-Screening\data\"
:r $(path)\OMOP_CCF_COMORBIDITIES_ICD10_list.sql

CREATE NONCLUSTERED INDEX IX ON #COMORBIDITIES_LIST (CONDITION_CONCEPT_ID);
SELECT COUNT(DISTINCT CONDITION_CONCEPT_ID) AS "Num comorbidity concept IDs imported" FROM #COMORBIDITIES_LIST;

DROP TABLE IF EXISTS #OMOP_STUDY;

WITH PATIENT_GC_LIST AS
  (SELECT *
   FROM
     (SELECT a.Person_id AS STUDY_PAT_ID,
             CONCEPT_NAME,
             CONCEPT_CODE,
             condition_start_date INITIAL_DX_DT,
             BIRTH_DATETIME,
             GENDER_SOURCE_VALUE,
             race_source_value,
             ethnicity_source_value,
			 c.state AS "STUDY STATE",
             row_number() OVER (PARTITION BY a.Person_id
                                ORDER BY condition_start_date ASC) AS rn
      FROM dbo.CONDITION_OCCURRENCE a
      INNER JOIN dbo.CONCEPT b ON a.condition_concept_id = b.concept_id
      INNER JOIN dbo.PERSON c ON c.person_id = a.person_id
		WHERE (a.condition_source_value LIKE '%C16.9%'
			OR a.condition_source_value LIKE '%C16.1%'
			OR a.condition_source_value LIKE '%C16.2%'
			OR a.condition_source_value LIKE '%C16.3%'
			OR a.condition_source_value LIKE '%C16.4%'
			OR a.condition_source_value LIKE '%C16.5%'
			OR a.condition_source_value LIKE '%C16.6%'
			OR a.condition_source_value LIKE '%C16.7%'
			OR a.condition_source_value LIKE '%C16.8%')
			  AND condition_source_value NOT LIKE '%C49.A2%'
	) x
   WHERE rn = 1),
FIRST_ENC AS
  (SELECT *
   FROM
     (SELECT A.PERSON_ID,
             a.visit_start_date AS FIRST_ENC_DT,
             row_number () OVER (PARTITION BY a.PERSON_ID
                                 ORDER BY a.visit_start_date ASC) AS rn3
      FROM dbo.VISIT_OCCURRENCE a
      INNER JOIN PATIENT_GC_LIST b ON a.PERSON_ID = b.STUDY_PAT_ID) x
   WHERE rn3 = 1)
SELECT * INTO #OMOP_STUDY
FROM
  (SELECT c.*,
          FIRST_ENC_DT,
          a.visit_start_date PCP_DT_PRIOR_TO_DX,
          a.visit_source_value AS study_visit_source,
          b.specialty_source_value AS study_Specialty,
          row_number() OVER (PARTITION BY a.person_id
                             ORDER BY a.visit_start_date DESC) AS rn2
   FROM dbo.VISIT_OCCURRENCE a
   INNER JOIN dbo.PROVIDER b ON a.provider_id = b.provider_id
   INNER JOIN PATIENT_GC_LIST c ON c.STUDY_PAT_ID = a.person_id
   LEFT OUTER JOIN FIRST_ENC d ON d.person_id = a.person_id
   WHERE CAST(a.VISIT_START_DATE AS DATE) < dateadd(YEAR, -1, c.INITIAL_DX_DT)) x
WHERE rn2 = 1
  AND INITIAL_DX_DT >= '2010-01-01';

CREATE NONCLUSTERED INDEX IX ON #OMOP_STUDY (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients in #OMOP_STUDY" FROM #OMOP_STUDY;
/*****************************************************************/
/************************** CONTROLS *****************************/
/*****************************************************************/

DROP TABLE IF EXISTS #GASTRIC_CA_STUDY_CONTROL;
WITH CONTROLS AS
    (SELECT *
     FROM
       (SELECT top 1000000 
			c.person_id AS Study_Person_ID,
            c.GENDER_SOURCE_VALUE AS CONTROL_GENDER,
            c.race_source_value AS CONTROL_RACE,
            c.ethnicity_source_value AS CONTROL_ETHNICITY,
            c.state AS CONTROL_STATE,
            a.visit_start_date,
            a.visit_source_value,
            b.specialty_source_value AS CONTROL_SPECIALTY,
            c.BIRTH_DATETIME AS CONTROL_DOB,
            RAND() AS Random1,
            row_number() OVER (PARTITION BY a.person_id
                                ORDER BY a.visit_start_date ASC) AS rn3
        FROM dbo.VISIT_OCCURRENCE a
        INNER JOIN dbo.PROVIDER b ON a.provider_id = b.provider_id
        INNER JOIN dbo.PERSON c ON c.person_id = a.person_id
        WHERE datediff(YEAR, c.BIRTH_DATETIME, a.visit_start_date) BETWEEN 40 AND 80
		) x
	)
SELECT * INTO #GASTRIC_CA_STUDY_CONTROL
FROM #OMOP_STUDY A
INNER JOIN CONTROLS b 
	ON CAST(b.visit_start_date AS DATE) BETWEEN dateadd(DAY, -60, PCP_DT_PRIOR_TO_DX) AND dateadd(DAY, 60, PCP_DT_PRIOR_TO_DX);

DROP TABLE #OMOP_STUDY;
CREATE NONCLUSTERED INDEX IX ON #GASTRIC_CA_STUDY_CONTROL (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients in #GASTRIC_CA_STUDY_CONTROL" FROM #GASTRIC_CA_STUDY_CONTROL;

DROP TABLE IF EXISTS #OMOP_COHORT;
WITH GASTRIC_CA_COHORT1 AS
    (SELECT y.*
     FROM
       (SELECT x.*,
               row_number() OVER (PARTITION BY STUDY_PAT_ID
                                  ORDER BY Random_Seed ASC) AS rn5
        FROM
          (SELECT a.*,
                  row_number() OVER (PARTITION BY a.STUDY_PERSON_ID
                                     ORDER BY a.Random1 ASC) AS rn4,
                  RAND() AS Random_Seed
           FROM #GASTRIC_CA_STUDY_CONTROL a
		  ) x
        WHERE rn4 = 1)y
     WHERE rn5 <= 5)
  SELECT * INTO #OMOP_COHORT
  FROM
    (SELECT STUDY_PAT_ID,
            PCP_DT_PRIOR_TO_DX,
            GENDER_SOURCE_VALUE,
            race_source_value,
            ethnicity_source_value,
            [STUDY STATE],
            'STUDY' AS "Cohort",
            row_number() OVER (PARTITION BY STUDY_PAT_ID
                               ORDER BY INITIAL_DX_DT ASC) AS rn
     FROM GASTRIC_CA_COHORT1
	 ) x WHERE rn = 1

	UNION

	SELECT Study_person_id,
		   visit_start_date,
		   CONTROL_GENDER,
		   CONTROL_RACE,
		   CONTROL_ETHNICITY,
		   CONTROL_STATE,
		   'CONTROL' AS "Cohort",
		   '1'
	FROM GASTRIC_CA_COHORT1;

SELECT Cohort, COUNT(*) AS "Num in group" FROM #OMOP_COHORT GROUP BY Cohort ORDER BY Cohort;

DROP TABLE #GASTRIC_CA_STUDY_CONTROL;
CREATE NONCLUSTERED INDEX IX ON #OMOP_COHORT (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients in #OMOP_COHORT" FROM #OMOP_COHORT;
/*****************************************************************/
/************************** COMORBIDITIES ************************/
/*****************************************************************/
DROP TABLE IF EXISTS #COMORBIDITIES;
WITH BMI AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS BMI_DT,
             b.value_as_number AS BMI,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b 
		ON a.study_pat_id = b.person_id
	  INNER JOIN dbo.concept c
		ON b.measurement_concept_id = c.concept_id
		AND concept_name LIKE '%Body mass index%'
		AND	(concept_class_id IN ('Clinical Observation', 'LOINC Component', 'LOINC Hierarchy')
		     OR domain_id = 'Measurement')
      WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_as_number IS NOT NULL
	) x
   WHERE rn = 1),
HEIGHT AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS HEIGHT_DT,
             b.value_as_number AS HEIGHT,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN dbo.concept c
		ON b.measurement_concept_id = c.concept_id
		AND concept_name LIKE '%Height%'
		AND	(concept_class_id IN ('Clinical Observation', 'LOINC Component', 'LOINC Hierarchy')
		     OR domain_id = 'Measurement')
	  WHERE 
		  CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_as_number IS NOT NULL) x
   WHERE rn = 1),
WEIGHT AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS WEIGHT_DT,
             b.value_as_number AS WEIGHT,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN dbo.concept c
		ON b.measurement_concept_id = c.concept_id
		AND concept_name LIKE '%Weight%'
		AND	(concept_class_id IN ('Clinical Observation', 'LOINC Component', 'LOINC Hierarchy')
		     OR domain_id = 'Measurement')
	  WHERE 
		  CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_as_number IS NOT NULL) x
   WHERE rn = 1),
ALCOHOL AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.observation_date AS ALCOHOL_DT,
             observation_source_value AS ALCOHOL,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.observation_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.OBSERVATION b ON a.study_pat_id = b.person_id
      WHERE observation_source_value LIKE '%ALCOHOL%'
        AND value_as_string = 'Yes'
        AND CAST(b.observation_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
TOBACCO AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.observation_date AS TOBACCO_DT,
             observation_source_value AS TOBACCO,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.observation_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.OBSERVATION b ON a.study_pat_id = b.person_id
      WHERE observation_source_value LIKE '%TOBACCO%'
        AND value_as_string = 'Yes'
        AND CAST(b.observation_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
FAM_HX_CA AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS FAM_HX_CA_DT,
             condition_source_value AS FAM_HX_CA,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date ASC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value BETWEEN 'C1' AND 'C99'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
PERSONAL_HX_CA_ICD AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS PERSONAL_HX_CA_ICD_DT,
             b.condition_source_value AS PERSONAL_HX_CA_ICD,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date ASC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE (condition_source_value BETWEEN 'C1' AND 'C99'
             OR condition_source_value BETWEEN 'D1' AND 'D49')
        AND NOT (condition_source_value LIKE 'C25%'
			  OR condition_source_value LIKE 'C16')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Diabetes AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Diabetes_DT,
             b.condition_source_value Diabetes,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date ASC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE (   condition_source_value LIKE 'E10%'
             OR condition_source_value LIKE 'E11%'
			 OR condition_source_value LIKE 'E13%')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Hypertension AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Hypertension_DT,
             b.condition_source_value AS Hypertension,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'I10%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Hypercholesterolemia AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Hypercholesterolemia_DT,
             b.condition_source_value AS Hypercholesterolemia,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value = 'E78.5'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Coronary_artery_disease AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Coronary_artery_disease_DT,
             b.condition_source_value AS Coronary_artery_disease,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'I25%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Cirrhosis AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Cirrhosis_DT,
             b.condition_source_value AS Cirrhosis,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'K74%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Emphysema AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Emphysema_DT,
             b.condition_source_value AS Emphysema,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'J43%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Stroke AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Stroke_DT,
             b.condition_source_value AS Stroke,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'I63%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	) x
   WHERE rn = 1),
Gastric_Ulcer AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Gastric_Ulcer_DT,
             b.condition_source_value AS Gastric_Ulcer,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'K25%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	) x
   WHERE rn = 1),
Viral_hepatitis AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Viral_hepatitis_DT,
             b.condition_source_value AS Viral_hepatitis,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'B19%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Depression AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Depression_DT,
             b.condition_source_value AS Depression,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'F32%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
IBD AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS IBD_DT,
             b.condition_source_value AS IBD,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE (condition_source_value LIKE 'K50%'
          OR condition_source_value LIKE 'K51%')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Chronic_respiratory_disease AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Chronic_respiratory_disease_DT,
             b.condition_source_value AS Chronic_respiratory_disease,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'J44.9%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Chronic_renal_disease AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Chronic_renal_disease_DT,
             b.condition_source_value AS Chronic_renal_disease,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'N18%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Upper_Gastrointestinal_Disease AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Upper_Gastrointestinal_Disease_DT,
             b.condition_source_value AS Upper_Gastrointestinal_Disease,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value BETWEEN 'K20' AND 'K31.9'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Lower_Gastrointestinal_Disease AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Lower_Gastrointestinal_Disease_DT,
             b.condition_source_value AS Lower_Gastrointestinal_Disease,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value BETWEEN 'K50' AND 'K52.9'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1)
SELECT 
	   a.STUDY_PAT_ID,
       BMI_DT,
       BMI,
       HEIGHT_DT,
       HEIGHT,
       WEIGHT_DT,
       WEIGHT,
       ALCOHOL_DT,
       ALCOHOL,
       TOBACCO_DT,
       TOBACCO,
       FAM_HX_CA_DT,
       FAM_HX_CA,
       PERSONAL_HX_CA_ICD_DT,
       PERSONAL_HX_CA_ICD,
       Diabetes_DT,
       Diabetes,
       Hypertension_DT,
       Hypertension,
       Hypercholesterolemia_DT,
       Hypercholesterolemia,
       Coronary_artery_disease_DT,
       Coronary_artery_disease,
       Cirrhosis_DT,
       Cirrhosis,
       Emphysema_DT,
       Emphysema,
       Stroke_DT,
       Stroke,
       Gastric_Ulcer_DT,
       Gastric_Ulcer,
       Viral_hepatitis_DT,
       Viral_hepatitis,
       Depression_DT,
       Depression,
       IBD_DT,
       IBD,
       Chronic_respiratory_disease_DT,
       Chronic_respiratory_disease,
       Chronic_renal_disease_DT,
       Chronic_renal_disease,
       Upper_Gastrointestinal_Disease_DT,
       Upper_Gastrointestinal_Disease,
       Lower_Gastrointestinal_Disease_DT,
       Lower_Gastrointestinal_Disease
INTO #COMORBIDITIES
FROM #OMOP_COHORT a
LEFT OUTER JOIN BMI b ON a.study_pat_id = b.study_pat_id
LEFT OUTER JOIN HEIGHT c ON a.study_pat_id = c.study_pat_id
LEFT OUTER JOIN WEIGHT d ON a.study_pat_id = d.study_pat_id
LEFT OUTER JOIN ALCOHOL e ON a.study_pat_id = e.study_pat_id
LEFT OUTER JOIN TOBACCO f ON a.study_pat_id = f.study_pat_id
LEFT OUTER JOIN FAM_HX_CA g ON a.study_pat_id = g.study_pat_id
LEFT OUTER JOIN PERSONAL_HX_CA_ICD h ON a.study_pat_id = h.study_pat_id
LEFT OUTER JOIN Diabetes i ON a.study_pat_id = i.study_pat_id
LEFT OUTER JOIN Hypertension j ON a.study_pat_id = j.study_pat_id
LEFT OUTER JOIN Hypercholesterolemia k ON a.study_pat_id = k.study_pat_id
LEFT OUTER JOIN Coronary_artery_disease l ON a.study_pat_id = l.study_pat_id
LEFT OUTER JOIN Cirrhosis m ON a.study_pat_id = m.study_pat_id
LEFT OUTER JOIN Emphysema n ON a.study_pat_id = n.study_pat_id
LEFT OUTER JOIN Stroke o ON a.study_pat_id = o.study_pat_id
LEFT OUTER JOIN Gastric_Ulcer p ON a.study_pat_id = p.study_pat_id
LEFT OUTER JOIN Viral_hepatitis q ON a.study_pat_id = q.study_pat_id
LEFT OUTER JOIN Depression r ON a.study_pat_id = r.study_pat_id
LEFT OUTER JOIN IBD s ON a.study_pat_id = s.study_pat_id
LEFT OUTER JOIN Chronic_respiratory_disease t ON a.study_pat_id = t.study_pat_id
LEFT OUTER JOIN Chronic_renal_disease u ON a.study_pat_id = u.study_pat_id
LEFT OUTER JOIN Upper_Gastrointestinal_Disease v ON a.study_pat_id = v.study_pat_id
LEFT OUTER JOIN Lower_Gastrointestinal_Disease w ON a.study_pat_id = w.study_pat_id;

CREATE NONCLUSTERED INDEX IX ON #COMORBIDITIES (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients in #COMORBIDITIES" FROM #COMORBIDITIES;
/*****************************************************************/
/************************ DIAGNOSES ******************************/
/*****************************************************************/
DROP TABLE IF EXISTS #DIAGNOSES;
WITH Gallstone_disorders AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Gallstone_disorders_DT,
             b.condition_source_value AS Gallstone_disorders,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'K80%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Hereditary_cancer_syndromes AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Hereditary_cancer_syndromes_DT,
             b.condition_source_value AS Hereditary_cancer_syndromes,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'Z15.0%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Peptic_ulcer AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Peptic_ulcer_DT,
             b.condition_source_value AS Peptic_ulcer,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'K27%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Deep_vein_thrombosis AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Deep_vein_thrombosis_DT,
             b.condition_source_value AS Deep_vein_thrombosis,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('I82.40',
                                       'I82.401',
                                       'I82.402',
                                       'I82.403',
                                       'I82.50',
                                       'I82.501',
                                       'I82.502',
                                       'I82.503')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Pulmonary_Embolism AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Pulmonary_Embolism_DT,
             b.condition_source_value AS Pulmonary_Embolism,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'I26%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
PERSONAL_HX_Gallstones AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS PERSONAL_HX_Gallstones_DT,
             b.condition_source_value AS PERSONAL_HX_Gallstones,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value = 'Z87.79'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
PERSONAL_HX_cholecystectomy AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS PERSONAL_HX_cholecystectomy_DT,
             b.condition_source_value AS PERSONAL_HX_cholecystectomy,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE 'Z90.5%'
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Vitamin_D_deficiency AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Vitamin_D_deficiency_DT,
             b.condition_source_value AS Vitamin_D_deficiency,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('E55.0',
                                       'E55.9',
                                       'E64.3')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Pancreatic_Disorders AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Pancreatic_Disorders_DT,
             b.condition_source_value AS Pancreatic_Disorders,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('K86.81')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Chronic_pancreatitis AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Chronic_pancreatitis_DT,
             b.condition_source_value AS Chronic_pancreatitis,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('K86.1')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Acute_pancreatitis AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Acute_pancreatitis_DT,
             b.condition_source_value AS Acute_pancreatitis,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('K85.0',
                                       'K85.1',
                                       'K85.2',
                                       'K85.3',
                                       'K85.8',
                                       'K85.9',
                                       'K85.90',
                                       'K85.91')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Pseudocyst AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Pseudocyst_DT,
             b.condition_source_value AS Pseudocyst,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE ('K83%')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Biliary_tract_disease AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Biliary_tract_disease_DT,
             b.condition_source_value AS Biliary_tract_disease,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE ('K83%')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Abdominal_pain AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Abdominal_pain_DT,
             b.condition_source_value AS Abdominal_pain,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE ('R10%')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Jaundice AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Jaundice_DT,
             b.condition_source_value AS Jaundice,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE ('R17%')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Dyspepsia AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Dyspepsia_DT,
             b.condition_source_value AS Dyspepsia,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value LIKE ('K30%')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Nausea_and_vomiting AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Nausea_and_vomiting_DT,
             b.condition_source_value AS Nausea_and_vomiting,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('R11.0',
                                       'R11.1',
                                       'R11.10',
                                       'R11.11',
                                       'R11.12',
                                       'R11.2')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Weight_loss AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Weight_loss_DT,
             b.condition_source_value AS Weight_loss,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('R63.4')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Back_pain AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Back_pain_DT,
             b.condition_source_value AS Back_pain,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('M54.50',
                                       'M54.51',
                                       'M54.59',
                                       'M54.4',
                                       'M54.8',
                                       'M54.89')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Constipation AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Constipation_DT,
             b.condition_source_value AS Constipation,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('K59.00',
                                       'K59.01',
                                       'K59.02',
                                       'K59.03',
                                       'K59.04',
                                       'K59.09')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Diarrhea AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Diarrhea_DT,
             b.condition_source_value AS Diarrhea,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('K52.9',
                                       'K59.1',
                                       'R19.7')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1),
Malaise_fatigue AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.condition_start_date AS Malaise_fatigue_DT,
             b.condition_source_value AS Malaise_fatigue,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.condition_start_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.CONDITION_OCCURRENCE b ON a.study_pat_id = b.person_id
      WHERE condition_source_value IN ('R53',
                                       'R53.9',
                                       'R53.81',
                                       'R53.82',
                                       'R53.83')
        AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)) x
   WHERE rn = 1)
SELECT a.STUDY_PAT_ID,
       Gallstone_disorders_DT,
       Gallstone_disorders,
       Hereditary_cancer_syndromes_DT,
       Hereditary_cancer_syndromes,
       Peptic_ulcer_DT,
       Peptic_ulcer,
       Deep_vein_thrombosis_DT,
       Deep_vein_thrombosis,
       Pulmonary_Embolism_DT,
       Pulmonary_Embolism,
       PERSONAL_HX_Gallstones_DT,
       PERSONAL_HX_Gallstones,
       PERSONAL_HX_cholecystectomy_DT,
       PERSONAL_HX_cholecystectomy,
       Vitamin_D_deficiency_DT,
       Vitamin_D_deficiency,
       Pancreatic_Disorders_DT,
       Pancreatic_Disorders,
       Chronic_pancreatitis_DT,
       Chronic_pancreatitis,
       Acute_pancreatitis_DT,
       Acute_pancreatitis,
       Pseudocyst_DT,
       Pseudocyst,
       Biliary_tract_disease_DT,
       Biliary_tract_disease,
       Abdominal_pain_DT,
       Abdominal_pain,
       Jaundice_DT,
       Jaundice,
       Dyspepsia_DT,
       Dyspepsia,
       Nausea_and_vomiting_DT,
       Nausea_and_vomiting,
       Weight_loss_DT,
       Weight_loss,
       Back_pain_DT,
       Back_pain,
       Constipation_DT,
       Constipation,
       Diarrhea_DT,
       Diarrhea,
       Malaise_fatigue_DT,
       Malaise_fatigue
INTO #DIAGNOSES
FROM #OMOP_COHORT a
LEFT OUTER JOIN Gallstone_disorders b ON a.study_pat_id = b.study_pat_id
LEFT OUTER JOIN Hereditary_cancer_syndromes c ON a.study_pat_id = c.study_pat_id
LEFT OUTER JOIN Peptic_ulcer d ON a.study_pat_id = d.study_pat_id
LEFT OUTER JOIN Deep_vein_thrombosis e ON a.study_pat_id = e.study_pat_id
LEFT OUTER JOIN Pulmonary_Embolism f ON a.study_pat_id = f.study_pat_id
LEFT OUTER JOIN PERSONAL_HX_Gallstones g ON a.study_pat_id = g.study_pat_id
LEFT OUTER JOIN PERSONAL_HX_cholecystectomy h ON a.study_pat_id = h.study_pat_id
LEFT OUTER JOIN Vitamin_D_deficiency i ON a.study_pat_id = i.study_pat_id
LEFT OUTER JOIN Pancreatic_Disorders j ON a.study_pat_id = j.study_pat_id
LEFT OUTER JOIN Chronic_pancreatitis k ON a.study_pat_id = k.study_pat_id
LEFT OUTER JOIN Acute_pancreatitis l ON a.study_pat_id = l.study_pat_id
LEFT OUTER JOIN Pseudocyst m ON a.study_pat_id = m.study_pat_id
LEFT OUTER JOIN Biliary_tract_disease n ON a.study_pat_id = n.study_pat_id
LEFT OUTER JOIN Abdominal_pain o ON a.study_pat_id = o.study_pat_id
LEFT OUTER JOIN Jaundice p ON a.study_pat_id = p.study_pat_id
LEFT OUTER JOIN Dyspepsia q ON a.study_pat_id = q.study_pat_id
LEFT OUTER JOIN Nausea_and_vomiting r ON a.study_pat_id = r.study_pat_id
LEFT OUTER JOIN Weight_loss s ON a.study_pat_id = s.study_pat_id
LEFT OUTER JOIN Back_pain t ON a.study_pat_id = t.study_pat_id
LEFT OUTER JOIN Constipation u ON a.study_pat_id = u.study_pat_id
LEFT OUTER JOIN Diarrhea v ON a.study_pat_id = v.study_pat_id
LEFT OUTER JOIN Malaise_fatigue w ON a.study_pat_id = w.study_pat_id;

CREATE NONCLUSTERED INDEX IX ON #DIAGNOSES (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients in #DIAGNOSES" FROM #DIAGNOSES;
/*****************************************************************/
/*********************** MEDICATIONS *****************************/ 
/*****************************************************************/
DROP TABLE IF EXISTS #MEDICATIONS;
WITH Metformin_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
			 mli.concept_name AS Metformin,
             a.drug_exposure_start_date AS Metformin_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
		AND mli.DRUG_CLASS = 'Metformin'
      WHERE a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1),
Insulin_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS Insulin,
             a.drug_exposure_start_date AS Insulin_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
		AND mli.DRUG_CLASS = 'Insulin'
      WHERE 
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND	a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1),
Aspirin_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS Aspirin,
             a.drug_exposure_start_date AS Aspirin_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
		AND mli.DRUG_CLASS = 'Aspirin'
	  WHERE
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1),
NSAID_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS NSAID,
             a.drug_exposure_start_date AS NSAID_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
		AND mli.DRUG_CLASS = 'NSAID'
      WHERE 
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1),
Beta_Blocker_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS Beta_Blocker,
             a.drug_exposure_start_date AS Beta_Blocker_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
	   AND mli.DRUG_CLASS = 'BETA_BLOCKER'
      WHERE
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1),
Statin_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS Statin,
             a.drug_exposure_start_date AS Statin_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
	   AND mli.DRUG_CLASS = 'Statin'
      WHERE 
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1),
PPI_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS PPI,
             a.drug_exposure_start_date AS PPI_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN dbo.CONCEPT d ON a.drug_concept_id = d.concept_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
	   AND mli.DRUG_CLASS = 'PPI'
      WHERE 
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1),
Sulfonylurea_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS Sulfonylurea,
             a.drug_exposure_start_date AS Sulfonylurea_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
	   AND mli.DRUG_CLASS = 'Sulfonylurea'
		WHERE 
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1),
Diuretics_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS Diuretics,
             a.drug_exposure_start_date AS Diuretics_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
      AND mli.DRUG_CLASS = 'Diuretic'
		WHERE
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		 AND a.route_source_value LIKE 'Oral%'
		) x
   WHERE rn = 1),
Antipsychotics_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS Antipsychotics,
             a.drug_exposure_start_date AS Antipsychotics_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
      AND mli.DRUG_CLASS = 'Antipsychotic'
		WHERE 
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1),
Hormone_Start AS
  (SELECT *
   FROM
     (SELECT b.study_pat_id,
             mli.concept_name AS Hormone,
             a.drug_exposure_start_date AS Hormone_DT,
             row_number() OVER (PARTITION BY b.study_pat_id
                                ORDER BY a.drug_exposure_start_date ASC) AS rn
      FROM dbo.DRUG_EXPOSURE a
      INNER JOIN #OMOP_COHORT b ON a.person_id = b.study_pat_id
      INNER JOIN #MEDICATIONS_LIST_AUGMENTED mli
		ON a.drug_concept_id = mli.DRUG_CONCEPT_ID
      AND mli.DRUG_CLASS = 'Hormone'
		WHERE
			CAST(a.drug_exposure_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND a.route_source_value LIKE 'Oral%'
	) x
   WHERE rn = 1)
SELECT a.STUDY_PAT_ID,
       Metformin,
       Metformin_DT,
       Insulin,
       Insulin_DT,
       Aspirin,
       Aspirin_DT,
       NSAID,
       NSAID_DT,
       Beta_Blocker,
       Beta_Blocker_DT,
       Statin,
       Statin_DT,
       PPI,
       PPI_DT,
       Sulfonylurea,
       Sulfonylurea_DT,
       Diuretics,
       Diuretics_DT,
       Antipsychotics,
       Antipsychotics_DT,
       Hormone,
       Hormone_DT
INTO #MEDICATIONS
FROM #OMOP_COHORT a
LEFT OUTER JOIN Metformin_Start b ON a.study_pat_id = b.study_pat_id
LEFT OUTER JOIN Insulin_Start c ON a.study_pat_id = c.study_pat_id
LEFT OUTER JOIN Aspirin_Start d ON a.study_pat_id = d.study_pat_id
LEFT OUTER JOIN NSAID_Start e ON a.study_pat_id = e.study_pat_id
LEFT OUTER JOIN Beta_Blocker_Start f ON a.study_pat_id = f.study_pat_id
LEFT OUTER JOIN Statin_Start g ON a.study_pat_id = g.study_pat_id
LEFT OUTER JOIN PPI_Start h ON a.study_pat_id = h.study_pat_id
LEFT OUTER JOIN Sulfonylurea_Start i ON a.study_pat_id = i.study_pat_id
LEFT OUTER JOIN Diuretics_Start j ON a.study_pat_id = j.study_pat_id
LEFT OUTER JOIN Antipsychotics_Start k ON a.study_pat_id = k.study_pat_id
LEFT OUTER JOIN Hormone_Start l ON a.study_pat_id = l.study_pat_id;

CREATE NONCLUSTERED INDEX IX ON #MEDICATIONS (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients in #MEDICATIONS" FROM #MEDICATIONS;

/**********************************************************************/ 
/******************************** LABS ********************************/
/**********************************************************************/ 
DROP TABLE IF EXISTS #LABS;
WITH hgba1c AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS hgba1c_DT,
             b.value_source_value AS hgba1c_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
      INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
		AND labs.LAB_GROUP = 'HBA1C'
	  WHERE 
		CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
ALP AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS ALP_DT,
             b.value_source_value AS ALP_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
      INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
		AND labs.LAB_GROUP = 'ALP'
	WHERE 
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL) x
   WHERE rn = 1),
bilirubin AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS bilirubin_DT,
             b.value_source_value AS bilirubin_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
		AND labs.LAB_GROUP = 'Bili'
	  WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
ALT AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS ALT_DT,
             b.value_source_value AS ALT_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
      AND labs.LAB_GROUP = 'ALT'
		WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
AST AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS AST_DT,
             b.value_source_value AS AST_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'AST'
		WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
lipase AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS lipase_DT,
             b.value_source_value AS lipase_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Lipase'
	   WHERE 
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
creatinine AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS creatinine_DT,
             b.value_source_value AS creatinine_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
      INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Creatinine'
	   WHERE 
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
mcv AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS mcv_DT,
             b.value_source_value AS mcv_VALUE,
             measurement_source_value,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'MCV'
	   WHERE 
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
rdw AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS rdw_DT,
             b.value_source_value AS rdw_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'RDW'
	   WHERE 
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
wbc AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS wbc_DT,
             b.value_source_value AS wbc_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'WBC'
	   WHERE 
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
lymphocytes AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS lymphocytes_DT,
             b.value_source_value AS lymphocytes_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Lymp_perc'
	   WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
bun AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS bun_DT,
             b.value_source_value AS bun_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'BUN'
	   WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
calcium AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS calcium_DT,
             b.value_source_value AS calcium_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Calcium'
	   WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
platelet AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS platelet_DT,
             b.value_source_value AS platelet_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'PLT'
	   WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
sodium AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS sodium_DT,
             b.value_source_value AS sodium_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Sodium'
	   WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
phosphorus AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS phosphorus_DT,
             b.value_source_value AS phosphorus_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Phs'
	   WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
hdl AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS hdl_DT,
             b.value_source_value AS hdl_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'HDL'
	   WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
ldl AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS ldl_DT,
             b.value_source_value AS ldl_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'LDL'
	   WHERE 
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
total_cholesterol AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS total_cholesterol_DT,
             b.value_source_value AS total_cholesterol_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Cholestrol'
	   WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
triglycerides AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS triglycerides_DT,
             b.value_source_value AS triglycerides_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
      INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Triglyceride'
	WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
glucose AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS glucose_DT,
             b.value_source_value AS glucose_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Glucose'
      WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
hematocrit AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS hematocrit_DT,
             b.value_source_value AS hematocrit_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Hct'
      WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
hemoglobin AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS hemoglobin_DT,
             b.value_source_value AS hemoglobin_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
      INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Hgb'
	WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1),
albumin AS
  (SELECT *
   FROM
     (SELECT a.study_pat_id,
             b.measurement_date AS albumin_DT,
             b.value_source_value AS albumin_VALUE,
             labs.LAB_NAME,
             row_number() OVER (PARTITION BY a.study_pat_id
                                ORDER BY b.measurement_date DESC) AS rn
      FROM #OMOP_COHORT a
      INNER JOIN dbo.MEASUREMENT b ON a.study_pat_id = b.person_id
	  INNER JOIN #LABS_LIST labs
		ON b.measurement_concept_id = labs.CONCEPT_ID
       AND labs.LAB_GROUP = 'Albumin'
      WHERE
			CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
        AND b.value_source_value IS NOT NULL
	) x
   WHERE rn = 1)
SELECT a.STUDY_PAT_ID,
       hgba1c_DT,
       hgba1c_VALUE,
       ALP_DT,
       ALP_VALUE,
       Bilirubin_DT,
       Bilirubin_VALUE,
       ALT_DT,
       ALT_VALUE,
       AST_DT,
       AST_VALUE,
       Lipase_DT,
       Lipase_VALUE,
       Creatinine_DT,
       Creatinine_VALUE,
       Mcv_DT,
       Mcv_VALUE,
       Rdw_DT,
       Rdw_VALUE,
       Wbc_DT,
       Wbc_VALUE,
       Lymphocytes_DT,
       Lymphocytes_VALUE,
       Bun_DT,
       Bun_VALUE,
       Calcium_DT,
       Calcium_VALUE,
       Platelet_DT,
       Platelet_VALUE,
       Sodium_DT,
       Sodium_VALUE,
       Phosphorus_DT,
       Phosphorus_VALUE,
       Hdl_DT,
       Hdl_VALUE,
       Ldl_DT,
       Ldl_VALUE,
       total_cholesterol_DT,
       total_cholesterol_VALUE,
       triglycerides_DT,
       triglycerides_VALUE,
       glucose_DT,
       glucose_VALUE,
       hematocrit_DT,
       hematocrit_VALUE,
       hemoglobin_DT,
       hemoglobin_VALUE,
       albumin_DT,
       albumin_VALUE
INTO #LABS
FROM #OMOP_COHORT a
LEFT OUTER JOIN hgba1c b ON a.study_pat_id = b.study_pat_id
LEFT OUTER JOIN ALP c ON a.study_pat_id = c.study_pat_id
LEFT OUTER JOIN Bilirubin d ON a.study_pat_id = d.study_pat_id
LEFT OUTER JOIN ALT e ON a.study_pat_id = e.study_pat_id
LEFT OUTER JOIN AST f ON a.study_pat_id = f.study_pat_id
LEFT OUTER JOIN Lipase g ON a.study_pat_id = g.study_pat_id
LEFT OUTER JOIN Creatinine h ON a.study_pat_id = h.study_pat_id
LEFT OUTER JOIN Mcv i ON a.study_pat_id = i.study_pat_id
LEFT OUTER JOIN Rdw j ON a.study_pat_id = j.study_pat_id
LEFT OUTER JOIN Wbc k ON a.study_pat_id = k.study_pat_id
LEFT OUTER JOIN Lymphocytes l ON a.study_pat_id = l.study_pat_id
LEFT OUTER JOIN Bun m ON a.study_pat_id = m.study_pat_id
LEFT OUTER JOIN Calcium n ON a.study_pat_id = n.study_pat_id
LEFT OUTER JOIN Platelet o ON a.study_pat_id = o.study_pat_id
LEFT OUTER JOIN Sodium p ON a.study_pat_id = p.study_pat_id
LEFT OUTER JOIN Phosphorus q ON a.study_pat_id = q.study_pat_id
LEFT OUTER JOIN Hdl r ON a.study_pat_id = r.study_pat_id
LEFT OUTER JOIN Ldl s ON a.study_pat_id = s.study_pat_id
LEFT OUTER JOIN total_cholesterol t ON a.study_pat_id = t.study_pat_id
LEFT OUTER JOIN triglycerides u ON a.study_pat_id = u.study_pat_id
LEFT OUTER JOIN glucose v ON a.study_pat_id = v.study_pat_id
LEFT OUTER JOIN hematocrit w ON a.study_pat_id = w.study_pat_id
LEFT OUTER JOIN hemoglobin x ON a.study_pat_id = x.study_pat_id
LEFT OUTER JOIN albumin y ON a.study_pat_id = y.study_pat_id;

CREATE NONCLUSTERED INDEX IX ON #LABS (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients in #LABS" FROM #LABS;


SELECT * 
FROM #OMOP_COHORT cohort
LEFT JOIN #COMORBIDITIES comor
	ON cohort.STUDY_PAT_ID = comor.STUDY_PAT_ID
LEFT JOIN #LABS labs
	ON cohort.STUDY_PAT_ID = labs.STUDY_PAT_ID
LEFT JOIN #MEDICATIONS meds
	ON cohort.STUDY_PAT_ID = meds.STUDY_PAT_ID;
