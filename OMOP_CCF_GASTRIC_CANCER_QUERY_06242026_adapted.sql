
DROP TABLE IF EXISTS #OMOP_STUDY;

WITH PATIENT_GC_LIST AS 
(SELECT *
FROM
	(
		SELECT
			a.Person_id AS STUDY_PAT_ID,  
			CONCEPT_NAME,
			CONCEPT_CODE, 
			condition_start_date AS INITIAL_DX_DT,
			BIRTH_DATETIME,
			GENDER_SOURCE_VALUE,
			race_source_value,
			ethnicity_source_value,
			c.state AS "STUDY STATE",
			c.person_source_value,  --,enterpriseid 
			ROW_NUMBER() OVER (PARTITION BY a.Person_id ORDER BY condition_start_date ASC) AS rn
		FROM dbo.CONDITION_OCCURRENCE a
		INNER JOIN dbo.CONCEPT b 
			ON a.condition_concept_id =  b.concept_id
		INNER JOIN dbo.PERSON c 
			ON c.person_id = a.person_id  
		-- INNER JOIN INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.GASTRIC_CA_ONCOLOG2 g ON g.pat_id = c.person_source_value 
		WHERE (a.condition_source_value LIKE '%C16.9%'
			OR a.condition_source_value LIKE '%C16.1%'
			OR a.condition_source_value LIKE '%C16.2%'
			OR a.condition_source_value LIKE '%C16.3%'
			OR a.condition_source_value LIKE '%C16.4%'
			OR a.condition_source_value LIKE '%C16.5%'
			OR a.condition_source_value LIKE '%C16.6%'
			OR a.condition_source_value LIKE '%C16.7%'
			OR a.condition_source_value LIKE '%C16.8%')
		AND condition_source_value not LIKE '%C49.A2%'
	)x 
	WHERE 
		rn = 1    
	AND INITIAL_DX_DT >= '2010-01-01'        
),
FIRST_ENC AS
(SELECT *
FROM
	(
		SELECT 
			A.PERSON_ID,  
			a.visit_start_date AS FIRST_ENC_DT,
			ROW_NUMBER () OVER (PARTITION BY a.PERSON_ID ORDER BY a.visit_start_date ASC) AS rn3
		FROM dbo.VISIT_OCCURRENCE a
		INNER JOIN PATIENT_GC_LIST b
			ON a.PERSON_ID = b.STUDY_PAT_ID
	)x 
	WHERE rn3 = 1 
),
Diagnosis_CNT AS
(
	SELECT   
		a.Person_id AS STUDY_PAT_ID,  
		count(*) AS COUNT_DX
	FROM dbo.CONDITION_OCCURRENCE a
	INNER JOIN dbo.CONCEPT b 
		ON a.condition_concept_id =  b.concept_id
	INNER JOIN dbo.PERSON c 
		ON c.person_id = a.person_id  
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
	GROUP BY a.Person_id
	)
SELECT * INTO #OMOP_STUDY
FROM
	(
		SELECT
			a.*, 
			FIRST_ENC_DT, 
			visit_start_date AS PCP_DT_PRIOR_TO_DX, 
			visit_source_value AS study_visit_source, 
			specialty_source_value AS study_Specialty,
			COUNT_DX,
			ROW_NUMBER() OVER (PARTITION BY a.STUDY_PAT_ID ORDER BY visit_start_date DESC) AS rn2
		FROM PATIENT_GC_LIST a 
		INNER JOIN dbo.VISIT_OCCURRENCE b 
			ON a.STUDY_PAT_ID = b.person_id
		LEFT OUTER JOIN dbo.PROVIDER c 
			ON b.provider_id = c.provider_id
		LEFT OUTER JOIN FIRST_ENC d 
			ON d.person_id = a.STUDY_PAT_ID
		LEFT OUTER JOIN Diagnosis_CNT e 
			ON e.STUDY_PAT_ID =  a.STUDY_PAT_ID
		WHERE 
			CAST(VISIT_START_DATE AS DATE) < DATEADD(YEAR, -1, CAST(INITIAL_DX_DT AS DATE)) 
	)x  
WHERE COUNT_DX >= 3;

CREATE NONCLUSTERED INDEX IX ON #OMOP_STUDY (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients in OMOP_STUDY" FROM #OMOP_STUDY;

/************************** CONTROLS *****************************/
DROP TABLE IF EXISTS #GASTRIC_CA_STUDY_CONTROL;
WITH CONTROLS AS
(SELECT *
FROM
	(
		SELECT TOP 2000000 
			c.person_id AS Study_Person_ID,
			c.GENDER_SOURCE_VALUE AS CONTROL_GENDER,
			c.race_source_value AS CONTROL_RACE, 
			c.ethnicity_source_value AS CONTROL_ETHNICITY,
			c.state AS STUDY_CNTRL_STATE,
			a.visit_start_date, 
			a.visit_source_value, 
			b.specialty_source_value AS CONTROL_SPECIALTY,
			c.BIRTH_DATETIME AS CONTROL_DOB,
			RAND() AS Random1
--			ROW_NUMBER() OVER (PARTITION BY a.person_id ORDER BY a.visit_start_date ASC) AS rn3
		FROM dbo.VISIT_OCCURRENCE a
		INNER JOIN dbo.PROVIDER b 
			ON a.provider_id = b.provider_id
		INNER JOIN dbo.PERSON c 
			ON c.person_id = a.person_id  
		WHERE DATEDIFF(year, c.BIRTH_DATETIME,a.visit_start_date) BETWEEN 40 AND 80
	)x 
)

SELECT * INTO #GASTRIC_CA_STUDY_CONTROL
FROM #OMOP_STUDY A
INNER JOIN CONTROLS b 
	ON CAST(b.visit_start_date AS DATE) BETWEEN DATEADD(DAY,-30, CAST(PCP_DT_PRIOR_TO_DX AS DATE)) AND DATEADD(DAY, 30, CAST(PCP_DT_PRIOR_TO_DX AS DATE));

DROP TABLE #OMOP_STUDY;
CREATE NONCLUSTERED INDEX IX ON #GASTRIC_CA_STUDY_CONTROL (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients GASTRIC_CA_STUDY_CONTROL" FROM #GASTRIC_CA_STUDY_CONTROL;

--  SELECT * FROM #OMOP_COHORT ORDER BY study_pat_id
DROP TABLE IF EXISTS #OMOP_COHORT;

 WITH GASTRIC_CA_COHORT1 AS
 (SELECT y.*
  FROM
	(
		SELECT 
			x.*,
			ROW_NUMBER() OVER (PARTITION BY STUDY_PAT_ID ORDER BY Random_Seed ASC) AS rn5
		FROM
		(
			SELECT 
				a.*,
				ROW_NUMBER() OVER (PARTITION BY a.STUDY_PERSON_ID ORDER BY a.Random1 ASC) AS rn4,
				RAND() AS Random_Seed
			FROM #GASTRIC_CA_STUDY_CONTROL a
		)x 
		WHERE rn4 = 1
	)y 
	WHERE rn5 <= 5
)

SELECT * INTO #OMOP_COHORT
FROM
	(
		SELECT 
			STUDY_PAT_ID, 
			PCP_DT_PRIOR_TO_DX, 
			GENDER_SOURCE_VALUE, 
			race_source_value, 
			ethnicity_source_value, 
			[STUDY STATE], 
--			'STUDY' AS "Study or control",
			ROW_NUMBER() OVER (PARTITION BY STUDY_PAT_ID ORDER BY INITIAL_DX_DT ASC) AS rn
		FROM GASTRIC_CA_COHORT1
	)x  
WHERE rn = 1

UNION

	SELECT 
		Study_person_id,
		visit_start_date,  
		CONTROL_GENDER,
		CONTROL_RACE, 
		CONTROL_ETHNICITY,
		STUDY_CNTRL_STATE,
--		'CONTROL' AS "Study or control",
		'1' AS rn
	FROM GASTRIC_CA_COHORT1;

DROP TABLE #GASTRIC_CA_STUDY_CONTROL;
CREATE NONCLUSTERED INDEX IX ON #OMOP_COHORT (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients OMOP_COHORT" FROM #OMOP_COHORT;
/***********************************************************************************************************************/
/***********************************************************************************************************************/
/***********************************************************************************************************************/

DROP TABLE IF EXISTS #OMOP_COHORT2;
 
WITH BMI AS
(SELECT *
FROM
	(
		SELECT 
			a.study_pat_id, 
			b.measurement_date AS BMI_DT, 
			b.value_as_number AS BMI, 
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b 
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value like '%BMI%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_as_number IS NOT NULL
	)x 
WHERE rn = 1
),
WEIGHT AS
(SELECT *
FROM
	(
		SELECT 
			a.study_pat_id, 
			b.measurement_date AS WEIGHT_DT, 
			b.value_as_number AS WEIGHT, 
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a
		INNER JOIN dbo.MEASUREMENT b 
			ON a.study_pat_id = b.person_id
		WHERE  
			measurement_source_value like '%WEIGHT%' 
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_as_number IS NOT NULL
	)x 
	WHERE rn = 1
),
ALCOHOL AS
(SELECT *
FROM
	(
		SELECT 
			a.study_pat_id, 
			b.observation_date AS ALCOHOL_DT,
			observation_source_value AS ALCOHOL, 
			VALUE_AS_STRING,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.observation_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.OBSERVATION b 
			ON a.study_pat_id = b.person_id
		WHERE 
			observation_source_value = 'ALCOHOL_USE_C' -- AND value_as_string = 'Yes'
		AND CAST(b.observation_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
TOBACCO AS
(SELECT *
FROM
	(
		SELECT 
			a.study_pat_id, 
			b.observation_date AS TOBACCO_DT,observation_source_value AS TOBACCO, VALUE_AS_STRING,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.observation_date DESC) AS rn2
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.OBSERVATION b 
			ON a.study_pat_id = b.person_id
		WHERE 
			observation_source_value = 'TOBACCO_USER_C' -- AND value_as_string = 'Yes'
		AND CAST(b.observation_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn2 = 1
),
FAM_HX_CA AS
(SELECT *
FROM
	(
		SELECT 
			a.study_pat_id, 
			b.condition_start_date AS FAM_HX_CA_DT,
			condition_source_value AS FAM_HX_CA,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date ASC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b 
			ON a.study_pat_id = b.person_id
		WHERE 
			condition_source_value BETWEEN 'C1' AND 'C99'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
PERSONAL_HX_CA_ICD AS
(SELECT *
FROM
	(
		SELECT 
			a.study_pat_id, 
			b.condition_start_date AS PERSONAL_HX_CA_ICD_DT,
			b.condition_source_value AS PERSONAL_HX_CA_ICD,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date ASC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b 
			ON a.study_pat_id = b.person_id
	WHERE 
		(condition_source_value BETWEEN 'C1' AND 'C99' OR condition_source_value BETWEEN 'D1' AND 'D49')
	AND NOT (condition_source_value LIKE 'C25%' OR condition_source_value LIKE 'C16')
	AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
WHERE rn = 1
),
Diabetes AS
(SELECT *
FROM
	(
		SELECT 
			a.study_pat_id, 
			b.condition_start_date AS Diabetes_DT,
	b.condition_source_value Diabetes,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date ASC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b 
			ON a.study_pat_id = b.person_id
	WHERE
		(condition_source_value LIKE 'E10%'
	  OR condition_source_value LIKE 'E11%'
	  OR condition_source_value LIKE 'E13%')
	AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Hypertension AS
(SELECT *
FROM
	(
		SELECT 
			a.study_pat_id, 
			b.condition_start_date AS Hypertension_DT,
			b.condition_source_value AS Hypertension,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'I10%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Hypercholesterolemia AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Hypercholesterolemia_DT,
			b.condition_source_value AS Hypercholesterolemia,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value = 'E78.5'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Coronary_artery_disease AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Coronary_artery_disease_DT,
			b.condition_source_value AS Coronary_artery_disease
			  ,ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'I25%'
	    AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Cirrhosis AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Cirrhosis_DT,
			b.condition_source_value AS Cirrhosis,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
			FROM #OMOP_COHORT a 
			INNER JOIN dbo.CONDITION_OCCURRENCE b
				ON a.study_pat_id = b.person_id
			WHERE
				condition_source_value LIKE 'K74%'
			AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Emphysema AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Emphysema_DT,
			b.condition_source_value AS Emphysema,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'J43%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Stroke AS
(SELECT *
FROM
	(
		SELECT
		a.study_pat_id,
		b.condition_start_date AS Stroke_DT,
		b.condition_source_value AS Stroke,
		ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'I63%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Gastric_Ulcer AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Gastric_Ulcer_DT,
			b.condition_source_value AS Gastric_Ulcer,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'K25%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Viral_hepatitis AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Viral_hepatitis_DT,
			b.condition_source_value AS Viral_hepatitis,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'B19%'
			AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Depression AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Depression_DT,
			b.condition_source_value AS Depression,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'F32%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
IBD AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS IBD_DT,
			b.condition_source_value AS IBD,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE 
			(condition_source_value LIKE 'K50%'	OR condition_source_value LIKE 'K51%')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Chronic_respiratory_disease AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Chronic_respiratory_disease_DT,
			b.condition_source_value AS Chronic_respiratory_disease,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'J44.9%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Chronic_renal_disease AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Chronic_renal_disease_DT,
			b.condition_source_value AS Chronic_renal_disease,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'N18%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Upper_Gastrointestinal_Disease AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Upper_Gastrointestinal_Disease_DT,
			b.condition_source_value AS Upper_Gastrointestinal_Disease,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value BETWEEN 'K20' AND 'K31.9'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Lower_Gastrointestinal_Disease AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Lower_Gastrointestinal_Disease_DT,
			b.condition_source_value AS Lower_Gastrointestinal_Disease,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value BETWEEN 'K50' AND 'K52.9'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
)

SELECT 
	a.*,
	BMI_DT, 
	BMI,
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
INTO #OMOP_COHORT2
FROM #OMOP_COHORT a
LEFT OUTER JOIN BMI b
	ON a.study_pat_id = b.study_pat_id
LEFT OUTER JOIN WEIGHT c 
	ON a.study_pat_id = c.study_pat_id
LEFT OUTER JOIN ALCOHOL d 
	ON a.study_pat_id = d.study_pat_id
LEFT OUTER JOIN TOBACCO e  
	ON a.study_pat_id = e.study_pat_id
LEFT OUTER JOIN FAM_HX_CA f  
	ON a.study_pat_id = f.study_pat_id
LEFT OUTER JOIN PERSONAL_HX_CA_ICD g  
	ON a.study_pat_id = g.study_pat_id
LEFT OUTER JOIN Diabetes h 
	ON a.study_pat_id = h.study_pat_id
LEFT OUTER JOIN Hypertension i  
	ON a.study_pat_id = i.study_pat_id
LEFT OUTER JOIN Hypercholesterolemia j  
	ON a.study_pat_id = j.study_pat_id
LEFT OUTER JOIN Coronary_artery_disease k  
	ON a.study_pat_id = k.study_pat_id
LEFT OUTER JOIN Cirrhosis l  
	ON a.study_pat_id = l.study_pat_id
LEFT OUTER JOIN Emphysema m  
	ON a.study_pat_id = m.study_pat_id
LEFT OUTER JOIN Stroke n  
	ON a.study_pat_id = n.study_pat_id
LEFT OUTER JOIN Gastric_Ulcer o 
	ON a.study_pat_id = o.study_pat_id
LEFT OUTER JOIN Viral_hepatitis p  
	ON a.study_pat_id = p.study_pat_id
LEFT OUTER JOIN Depression q  
	ON a.study_pat_id = q.study_pat_id
LEFT OUTER JOIN IBD r 
	ON a.study_pat_id = r.study_pat_id
LEFT OUTER JOIN Chronic_respiratory_disease s 
	ON a.study_pat_id = s.study_pat_id
LEFT OUTER JOIN Chronic_renal_disease t  
	ON a.study_pat_id = t.study_pat_id
LEFT OUTER JOIN Upper_Gastrointestinal_Disease u  
	ON a.study_pat_id = u.study_pat_id
LEFT OUTER JOIN Lower_Gastrointestinal_Disease v  
	ON a.study_pat_id = v.study_pat_id;

CREATE NONCLUSTERED INDEX IX ON #OMOP_COHORT2 (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients OMOP_COHORT2" FROM #OMOP_COHORT2;
/***************************************************************************************************/

DROP TABLE IF EXISTS #OMOP_COHORT3;

WITH Gallstone_disorders AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Gallstone_disorders_DT,
			b.condition_source_value AS Gallstone_disorders,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'K80%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Hereditary_cancer_syndromes AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Hereditary_cancer_syndromes_DT,
			b.condition_source_value AS Hereditary_cancer_syndromes,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'Z15.0%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Peptic_ulcer AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Peptic_ulcer_DT,
			b.condition_source_value AS Peptic_ulcer,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'K27%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Deep_vein_thrombosis AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Deep_vein_thrombosis_DT,
			b.condition_source_value AS Deep_vein_thrombosis,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('I82.40','I82.401','I82.402','I82.403','I82.50','I82.501','I82.502','I82.503')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Pulmonary_Embolism AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Pulmonary_Embolism_DT,
			b.condition_source_value AS Pulmonary_Embolism,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'I26%'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
PERSONAL_HX_Gallstones AS
(SELECT *
FROM
	(	
		SELECT
			a.study_pat_id,
			b.condition_start_date AS PERSONAL_HX_Gallstones_DT,
			b.condition_source_value AS PERSONAL_HX_Gallstones,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value = 'Z87.79'
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
PERSONAL_HX_cholecystectomy AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS PERSONAL_HX_cholecystectomy_DT,
			b.condition_source_value AS PERSONAL_HX_cholecystectomy,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE 'Z90.5%' 
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Vitamin_D_deficiency AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Vitamin_D_deficiency_DT,
			b.condition_source_value AS Vitamin_D_deficiency,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('E55.0','E55.9','E64.3')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Pancreatic_Disorders AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Pancreatic_Disorders_DT,
			b.condition_source_value AS Pancreatic_Disorders,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('K86.81')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Chronic_pancreatitis AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Chronic_pancreatitis_DT,
			b.condition_source_value AS Chronic_pancreatitis,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('K86.1')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Acute_pancreatitis AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Acute_pancreatitis_DT,
			b.condition_source_value AS Acute_pancreatitis,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('K85.0','K85.1','K85.2','K85.3','K85.8','K85.9','K85.90','K85.91') 
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Pseudocyst AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Pseudocyst_DT,
			b.condition_source_value AS Pseudocyst,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE ('K83%')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Biliary_tract_disease AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Biliary_tract_disease_DT,
			b.condition_source_value AS Biliary_tract_disease,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE ('K83%')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Abdominal_pain AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Abdominal_pain_DT,
			b.condition_source_value AS Abdominal_pain,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE ('R10%')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Jaundice AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Jaundice_DT,
			b.condition_source_value AS Jaundice,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE  ('R17%')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Dyspepsia AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Dyspepsia_DT,
			b.condition_source_value AS Dyspepsia,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value LIKE ('K30%')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Nausea_and_vomiting AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Nausea_and_vomiting_DT,
			b.condition_source_value AS Nausea_and_vomiting,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('R11.0','R11.1','R11.10','R11.11','R11.12','R11.2')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Weight_loss AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Weight_loss_DT,
			b.condition_source_value AS Weight_loss,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('R63.4')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Back_pain AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Back_pain_DT,
			b.condition_source_value AS Back_pain,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('M54.50','M54.51','M54.59','M54.4','M54.8','M54.89')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Constipation AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Constipation_DT,
			b.condition_source_value AS Constipation,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('K59.00','K59.01','K59.02','K59.03','K59.04','K59.09')
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Diarrhea AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Diarrhea_DT,
			b.condition_source_value AS Diarrhea,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('K52.9','K59.1','R19.7') 
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
),
Malaise_fatigue AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.condition_start_date AS Malaise_fatigue_DT,
			b.condition_source_value AS Malaise_fatigue,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.condition_start_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.CONDITION_OCCURRENCE b
			ON a.study_pat_id = b.person_id
		WHERE
			condition_source_value IN ('R53','R53.9','R53.81','R53.82','R53.83') 
		AND CAST(b.condition_start_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
	)x 
	WHERE rn = 1
)

SELECT 
	a.*,
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
INTO #OMOP_COHORT3
FROM #OMOP_COHORT2 a
LEFT OUTER JOIN Gallstone_disorders b
	ON a.study_pat_id = b.study_pat_id
LEFT OUTER JOIN Hereditary_cancer_syndromes  c  
	ON a.study_pat_id = c.study_pat_id
LEFT OUTER JOIN Peptic_ulcer d 
	ON a.study_pat_id = d.study_pat_id
LEFT OUTER JOIN Deep_vein_thrombosis e 
	ON a.study_pat_id = e.study_pat_id
LEFT OUTER JOIN Pulmonary_Embolism f  
	ON a.study_pat_id = f.study_pat_id
LEFT OUTER JOIN PERSONAL_HX_Gallstones g  
	ON a.study_pat_id = g.study_pat_id
LEFT OUTER JOIN PERSONAL_HX_cholecystectomy h  
	ON a.study_pat_id = h.study_pat_id
LEFT OUTER JOIN Vitamin_D_deficiency i   
	ON a.study_pat_id = i.study_pat_id
LEFT OUTER JOIN Pancreatic_Disorders j  
	ON a.study_pat_id = j.study_pat_id
LEFT OUTER JOIN Chronic_pancreatitis k  
	ON a.study_pat_id = k.study_pat_id
LEFT OUTER JOIN Acute_pancreatitis l  
	ON a.study_pat_id = l.study_pat_id
LEFT OUTER JOIN Pseudocyst m  
	ON a.study_pat_id = m.study_pat_id
LEFT OUTER JOIN Biliary_tract_disease n  
	ON a.study_pat_id = n.study_pat_id
LEFT OUTER JOIN Abdominal_pain o  
	ON a.study_pat_id = o.study_pat_id
LEFT OUTER JOIN Jaundice p  
	ON a.study_pat_id = p.study_pat_id
LEFT OUTER JOIN Dyspepsia q  
	ON a.study_pat_id = q.study_pat_id
LEFT OUTER JOIN Nausea_and_vomiting r  
	ON a.study_pat_id = r.study_pat_id
LEFT OUTER JOIN Weight_loss s  
	ON a.study_pat_id = s.study_pat_id
LEFT OUTER JOIN Back_pain t  
	ON a.study_pat_id = t.study_pat_id
LEFT OUTER JOIN Constipation u  
	ON a.study_pat_id = u.study_pat_id
LEFT OUTER JOIN Diarrhea v  
	ON a.study_pat_id = v.study_pat_id
LEFT OUTER JOIN Malaise_fatigue w  
	ON a.study_pat_id = w.study_pat_id;

DROP TABLE #OMOP_COHORT2;
CREATE NONCLUSTERED INDEX IX ON #OMOP_COHORT3 (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients OMOP_COHORT3" FROM #OMOP_COHORT3;

/********************** MEDICATION QUERY *************************************/
/*****************************************************************************/


DROP TABLE IF EXISTS #OMOP_COHORT4;
 
WITH Metformin_Start AS 
(SELECT *
FROM
	(
		SELECT
			b.study_pat_id,
			a.drug_source_value AS Metformin, 
			a.drug_exposure_start_date AS Metformin_DT,
			ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
		FROM dbo.drug_exposure a
		INNER JOIN #OMOP_COHORT b
			ON a.person_id = b.study_pat_id
		WHERE 
			a.drug_source_value LIKE '%Metformin%'  
		AND a.route_source_value = '1201'
	)x 
	WHERE rn = 1
),
Insulin_Start AS 
(SELECT *
FROM
	(
		SELECT
			b.study_pat_id,
			a.drug_source_value AS Insulin, 
			a.drug_exposure_start_date AS Insulin_DT,
			ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
		FROM dbo.drug_exposure a
        INNER JOIN #OMOP_COHORT b
			ON a.person_id = b.study_pat_id
		WHERE 
			a.drug_source_value LIKE '%Insulin%'  
		AND a.route_source_value = '1201'
	)x 
	WHERE rn = 1
),
Aspirin_Start AS 
(SELECT *
FROM
	(
		SELECT
			b.study_pat_id,
			a.drug_source_value AS Aspirin,
			a.drug_exposure_start_date AS Aspirin_DT,
			ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
		FROM dbo.drug_exposure a
		INNER JOIN #OMOP_COHORT b
			ON a.person_id = b.study_pat_id
		 WHERE
			a.drug_source_value LIKE '%Aspirin%'  
		AND a.route_source_value = '1201'
	)x 
	WHERE rn = 1
),
NSAID_Start AS 
(SELECT *
FROM
	(
		SELECT
			b.study_pat_id,
			a.drug_source_value AS NSAID,
			a.drug_exposure_start_date AS NSAID_DT,
			ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
		FROM dbo.drug_exposure a
		INNER JOIN #OMOP_COHORT b
			ON a.person_id = b.study_pat_id
		WHERE
			(a.drug_source_value LIKE '%ibuprofen%' OR a.drug_source_value LIKE '%naproxen%' 
		  OR a.drug_source_value LIKE '%aspirin%' OR a.drug_source_value LIKE '%diclofenac%'
		  OR a.drug_source_value LIKE '%celecoxib%')
		 AND a.route_source_value = '1201'
	)x 
	WHERE rn = 1
),
Beta_Blocker_Start AS 
(SELECT *
FROM
	(
	SELECT
		b.study_pat_id,
		a.drug_source_value AS Beta_Blocker,
		a.drug_exposure_start_date AS Beta_Blocker_DT,
		ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
FROM dbo.drug_exposure a
        INNER JOIN #OMOP_COHORT b
	ON a.person_id = b.study_pat_id
     WHERE
		(a.drug_source_value LIKE '%Metoprolol%' OR a.drug_source_value LIKE '%Atenolol%'  
      OR a.drug_source_value LIKE '%Carvedilol%' OR a.drug_source_value LIKE '%Propranolol%')
     AND a.route_source_value = '1201'
)x 
	WHERE rn = 1
),
Statin_Start AS 
(SELECT *
FROM
	(
	SELECT
		b.study_pat_id,
		a.drug_source_value AS Statin,
		a.drug_exposure_start_date AS Statin_DT,
		ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
	FROM dbo.drug_exposure a
    INNER JOIN #OMOP_COHORT b
		ON a.person_id = b.study_pat_id
    WHERE
		a.drug_source_value LIKE '%Statin%' AND a.route_source_value = '1201'
	)x 
	WHERE rn = 1
),
PPI_Start AS 
(SELECT *
FROM
	(
		SELECT
			b.study_pat_id,
			a.drug_source_value AS PPI,
			a.drug_exposure_start_date AS PPI_DT,
			ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
		FROM dbo.drug_exposure a
		INNER JOIN #OMOP_COHORT b
			ON a.person_id = b.study_pat_id
		INNER JOIN dbo.CONCEPT d 
			ON a.drug_concept_id = d.concept_id
		 WHERE
			(a.drug_source_value LIKE '%omeprazole%' OR a.drug_source_value LIKE '%esomeprazole%'  
		 OR  a.drug_source_value LIKE '%lansoprazole%' OR a.drug_source_value LIKE '%pantoprazole%'
		 OR  a.drug_source_value LIKE '%rabeprazole%' OR a.drug_source_value LIKE '%dexlansoprazole%')
		 AND a.route_source_value = '1201' 
		 AND DOMAIN_ID = 'Drug'
	)x 
	WHERE rn = 1
),
Sulfonylurea_Start AS 
(SELECT *
FROM
	(
		SELECT b.study_pat_id,
			a.drug_source_value AS Sulfonylurea,
			a.drug_exposure_start_date AS Sulfonylurea_DT,
			ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
		FROM dbo.drug_exposure a
        INNER JOIN #OMOP_COHORT b
			ON a.person_id = b.study_pat_id
		WHERE
			(a.drug_source_value LIKE '%glimepiride%' OR a.drug_source_value LIKE '%glipizide%' 
		  OR a.drug_source_value LIKE '%glyburide%' OR a.drug_source_value LIKE '%Glynase%')
		 AND a.route_source_value = '1201'
	)x 
	WHERE rn = 1
),
Diuretics_Start AS 
(SELECT *
FROM
	(
		SELECT
			b.study_pat_id,
			a.drug_source_value AS Diuretics,
			a.drug_exposure_start_date AS Diuretics_DT,
			ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
		FROM dbo.drug_exposure a
		INNER JOIN #OMOP_COHORT b
			ON a.person_id = b.study_pat_id
		 WHERE
			(a.drug_source_value LIKE '%Furosemide%'
		  OR a.drug_source_value LIKE '%Bumetanide%'
		  OR a.drug_source_value LIKE '%Torsemide%'
		  OR a.drug_source_value LIKE '%Ethacrynic%'
		  OR a.drug_source_value LIKE '%Hydrochlorothiazide%'
		  OR a.drug_source_value LIKE '%Chlorthalidone%'
		  OR a.drug_source_value LIKE '%Indapamide%'        
		  OR a.drug_source_value LIKE '%Metolazone%'
		  OR a.drug_source_value LIKE '%Chlorothiazide%'
		  OR a.drug_source_value LIKE '%Spironolactone%'
		  OR a.drug_source_value LIKE '%Triamterene%'
		  OR a.drug_source_value LIKE '%Amiloride%'
		  OR a.drug_source_value LIKE '%Eplerenone%')
		 AND a.route_source_value = '1201'
	)x 
	WHERE rn = 1
),
Antipsychotics_Start AS 
(SELECT *
FROM
	(
		SELECT
			b.study_pat_id,
			a.drug_source_value AS Antipsychotics,
			a.drug_exposure_start_date AS Antipsychotics_DT,
			ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
		FROM dbo.drug_exposure a
		INNER JOIN #OMOP_COHORT b
			ON a.person_id = b.study_pat_id
		 WHERE
			(a.drug_source_value LIKE '%Aripiprazole%'
		  OR a.drug_source_value LIKE '%Olanzapine%'
		  OR a.drug_source_value LIKE '%Risperidone%'
		  OR a.drug_source_value LIKE '%Haloperidol%'
		  OR a.drug_source_value LIKE '%Chlorpromazine%')
		 AND a.route_source_value = '1201'
	)x 
	WHERE rn = 1
),
Hormone_Start AS 
(SELECT *
FROM
	(
		SELECT
			b.study_pat_id,
			a.drug_source_value AS Hormone,
			a.drug_exposure_start_date AS Hormone_DT,
			ROW_NUMBER() OVER (PARTITION BY b.study_pat_id ORDER BY a.drug_exposure_start_date ASC) AS rn
		FROM dbo.drug_exposure a
		INNER JOIN #OMOP_COHORT b
			ON a.person_id = b.study_pat_id
		 WHERE
			(a.drug_source_value LIKE '%Activella%'
		  OR a.drug_source_value LIKE '%Femhrt%'
		  OR a.drug_source_value LIKE '%Jinteli%'
		  OR a.drug_source_value LIKE '%Prefest%'
		  OR a.drug_source_value LIKE '%Bijuva%'
		  OR a.drug_source_value LIKE '%Angeliq%'
		  OR a.drug_source_value LIKE '%Combipatch%'
  		  OR a.drug_source_value LIKE '%Climara%'
		  OR a.drug_source_value LIKE '%Evorel%'
		  OR a.drug_source_value LIKE '%Femoston Conti%'
		  OR a.drug_source_value LIKE '%Kliovance%'
		  OR a.drug_source_value LIKE '%Kliofem%')
		 AND a.route_source_value = '1201'
	)x 
	WHERE rn = 1
)

SELECT 
	a.*,
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
INTO #OMOP_COHORT4
FROM #OMOP_COHORT3 a
LEFT OUTER JOIN Metformin_Start b
	ON a.study_pat_id = b.study_pat_id
LEFT OUTER JOIN Insulin_Start c
	ON a.study_pat_id = c.study_pat_id
LEFT OUTER JOIN Aspirin_Start d
	ON a.study_pat_id = d.study_pat_id
LEFT OUTER JOIN NSAID_Start e
	ON a.study_pat_id = e.study_pat_id
LEFT OUTER JOIN Beta_Blocker_Start f
	ON a.study_pat_id = f.study_pat_id
LEFT OUTER JOIN Statin_Start g
	ON a.study_pat_id = g.study_pat_id
LEFT OUTER JOIN PPI_Start h  
	ON a.study_pat_id = h.study_pat_id
LEFT OUTER JOIN Sulfonylurea_Start i
	ON a.study_pat_id = i.study_pat_id
LEFT OUTER JOIN Diuretics_Start j
	ON a.study_pat_id = j.study_pat_id
LEFT OUTER JOIN Antipsychotics_Start k
	ON a.study_pat_id = k.study_pat_id
LEFT OUTER JOIN Hormone_Start l
	ON a.study_pat_id = l.study_pat_id;

DROP TABLE #OMOP_COHORT3;
CREATE NONCLUSTERED INDEX IX ON #OMOP_COHORT4 (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients OMOP_COHORT4" FROM #OMOP_COHORT4;
/********************************* LABS QUERY *************************/
/**********************************************************************/

DROP TABLE IF EXISTS #OMOP_COHORT5;
 
WITH hgba1c AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id, 
			b.measurement_date AS hgba1c_DT, 
			b.value_source_value AS hgba1c_VALUE, 
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value LIKE '%HGBA1C%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
ALP AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS ALP_DT,
			b.value_source_value AS ALP_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE 
			measurement_source_value IN ('ALKALINE PHOSPHATASE','ALK PHOS') -- LIKE '%ALK%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
bilirubin AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS bilirubin_DT,
			b.value_source_value AS bilirubin_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			 measurement_source_value = 'BILIRUBIN, TOTAL'  -- LIKE '%bilirubin%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
		)x 
	WHERE rn = 1
),
ALT AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS ALT_DT,
			b.value_source_value AS ALT_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value in ('SGPT (ALT)','ALT')  -- LIKE '%bilirubin%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
AST AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS AST_DT,
			b.value_source_value AS AST_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value in ('SGOT (AST)','AST')  -- LIKE '%bilirubin%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
		)x 
	WHERE rn = 1
),
lipase AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS lipase_DT,
			b.value_source_value AS lipase_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value = 'LIPASE'   -- LIKE '%lipase%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
creatinine AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS creatinine_DT,
			b.value_source_value AS creatinine_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value = 'CREATININE'   --LIKE '%creatinine%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
mcv AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS mcv_DT,
			b.value_source_value AS mcv_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value LIKE 'mcv%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
rdw AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS rdw_DT,
			b.value_source_value AS rdw_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value LIKE 'rdw%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
wbc AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS wbc_DT,
			b.value_source_value AS wbc_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value = 'WBC'  -- LIKE '%wbc%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
lymphocytes AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS lymphocytes_DT,
			b.value_source_value AS lymphocytes_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value IN ('LYMPHOCYTES','LYMPHOCYTES - INTL')  --LIKE '%lymphocytes%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
bun AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS bun_DT,
			b.value_source_value AS bun_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value IN ('BUN, W.B.','BUN, WOOSTER','BUN')  --  LIKE '%bun%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
calcium AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS calcium_DT,
			b.value_source_value AS calcium_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value  = 'CALCIUM'   --  LIKE '%calcium%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x
	WHERE rn = 1
),
platelet AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS platelet_DT,
			b.value_source_value AS platelet_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value  = 'PLATELET COUNT' --  LIKE '%platelet%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
sodium AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS sodium_DT,
			b.value_source_value AS sodium_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value = 'SODIUM' --  LIKE '%sodium%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
phosphorus AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS phosphorus_DT,
			b.value_source_value AS phosphorus_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value  = 'PHOSPHORUS'  -- LIKE '%phosphorus%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
hdl AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS hdl_DT,
			b.value_source_value AS hdl_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value  IN ('HDL CHOLESTEROL','HDL-C')  -- LIKE '%hdl%'
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
ldl AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS ldl_DT,
			b.value_source_value AS ldl_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value IN ('LDL CHOLESTEROL','LDL','LDL CALCULATED','LDL CHOL DIRECT','LDL CHOL, CALCULATED','LDL CHOL, WOOSTER') --   LIKE '%ldl%'   
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
total_cholesterol AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS total_cholesterol_DT,
			b.value_source_value AS total_cholesterol_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value LIKE 'TOTAL CHOLESTEROL%'  -- LIKE '%TOTAL CHOL%'   
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
triglycerides AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS triglycerides_DT,
			b.value_source_value AS triglycerides_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value = 'TRIGLYCERIDES' --  LIKE '%triglycerides%'  
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
glucose AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS glucose_DT,
			b.value_source_value AS glucose_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value  IN ('GLUCOSE','ESTIMATED AVERAGE GLUCOSE') -- LIKE '%glucose%'  
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
hematocrit AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS hematocrit_DT,
			b.value_source_value AS hematocrit_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value  = 'HEMATOCRIT'  -- LIKE '%hematocrit%'  
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
hemoglobin AS
(SELECT *
FROM
	(
		SELECT
		a.study_pat_id,
			b.measurement_date AS hemoglobin_DT,
			b.value_source_value AS hemoglobin_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value = 'HEMOGLOBIN'  -- LIKE '%hemoglobin%'  
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
),
albumin AS
(SELECT *
FROM
	(
		SELECT
			a.study_pat_id,
			b.measurement_date AS albumin_DT,
			b.value_source_value AS albumin_VALUE,
			measurement_source_value,
			ROW_NUMBER() OVER (PARTITION BY a.study_pat_id ORDER BY b.measurement_date DESC) AS rn
		FROM #OMOP_COHORT a 
		INNER JOIN dbo.MEASUREMENT b
			ON a.study_pat_id = b.person_id
		WHERE
			measurement_source_value = 'ALBUMIN'  -- LIKE '%albumin%'  
		AND CAST(b.measurement_date AS DATE) <= CAST(PCP_DT_PRIOR_TO_DX AS DATE)
		AND b.value_source_value IS NOT NULL
	)x 
	WHERE rn = 1
)
SELECT 
	a.*,
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
INTO #OMOP_COHORT5
FROM #OMOP_COHORT4 a
LEFT OUTER JOIN hgba1c b
	ON a.study_pat_id = b.study_pat_id
LEFT OUTER JOIN ALP c
	ON a.study_pat_id = c.study_pat_id
LEFT OUTER JOIN Bilirubin d
	ON a.study_pat_id = d.study_pat_id
LEFT OUTER JOIN ALT e
	ON a.study_pat_id = e.study_pat_id
LEFT OUTER JOIN AST f
	ON a.study_pat_id = f.study_pat_id
LEFT OUTER JOIN Lipase g
	ON a.study_pat_id = g.study_pat_id
LEFT OUTER JOIN Creatinine h
	ON a.study_pat_id = h.study_pat_id
LEFT OUTER JOIN Mcv i
	ON a.study_pat_id = i.study_pat_id
LEFT OUTER JOIN Rdw j
	ON a.study_pat_id = j.study_pat_id
LEFT OUTER JOIN Wbc k
	ON a.study_pat_id = k.study_pat_id
LEFT OUTER JOIN Lymphocytes l
	ON a.study_pat_id = l.study_pat_id
LEFT OUTER JOIN Bun m
	ON a.study_pat_id = m.study_pat_id 
LEFT OUTER JOIN Calcium n
	ON a.study_pat_id = n.study_pat_id
LEFT OUTER JOIN Platelet o
	ON a.study_pat_id = o.study_pat_id
LEFT OUTER JOIN Sodium p
	ON a.study_pat_id = p.study_pat_id
LEFT OUTER JOIN Phosphorus q
	ON a.study_pat_id = q.study_pat_id
LEFT OUTER JOIN Hdl r
	ON a.study_pat_id = r.study_pat_id 
LEFT OUTER JOIN Ldl s
	ON a.study_pat_id = s.study_pat_id
LEFT OUTER JOIN total_cholesterol t
	ON a.study_pat_id = t.study_pat_id
LEFT OUTER JOIN triglycerides u
	ON a.study_pat_id = u.study_pat_id
LEFT OUTER JOIN glucose v
	ON a.study_pat_id = v.study_pat_id
LEFT OUTER JOIN hematocrit w
	ON a.study_pat_id = w.study_pat_id 
LEFT OUTER JOIN hemoglobin x
	ON a.study_pat_id = x.study_pat_id
LEFT OUTER JOIN albumin y
	ON a.study_pat_id = y.study_pat_id;

DROP TABLE #OMOP_COHORT4;
CREATE NONCLUSTERED INDEX IX ON #OMOP_COHORT5 (STUDY_PAT_ID);
SELECT COUNT(DISTINCT STUDY_PAT_ID) AS "Num patients OMOP_COHORT5" FROM #OMOP_COHORT5;

SELECT * FROM #OMOP_COHORT5;
