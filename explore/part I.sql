SELECT TOP 100
	a.Person_id AS STUDY_PAT_ID,
    CONCEPT_NAME,
    CONCEPT_CODE,
    condition_start_date INITIAL_DX_DT,
    BIRTH_DATETIME ,
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
AND condition_source_value NOT LIKE '%C49.A2%';