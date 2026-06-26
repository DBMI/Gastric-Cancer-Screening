SELECT COUNT(DISTINCT Person_id) AS "Num patients" FROM dbo.condition_occurrence;
SELECT COUNT(DISTINCT Person_id) AS "Num patients with condition_source_concept_id" FROM dbo.condition_occurrence WHERE condition_source_concept_id IS NOT NULL;

SELECT COUNT(DISTINCT Person_id) AS "Num patients" FROM dbo.person;
SELECT COUNT(DISTINCT Person_id) AS "Num patients with location_id" FROM dbo.person WHERE location_id IS NOT NULL;


SELECT TOP 100 
	a.Person_id as STUDY_PAT_ID,
	a.condition_source_concept_id,
	a.condition_start_date INITIAL_DX_DT,
	c.BIRTH_DATETIME,
	c.GENDER_SOURCE_VALUE,
	c.race_source_value,
	c.ethnicity_source_value,
	c.location_id
--	f.state
FROM dbo.CONDITION_OCCURRENCE a
--INNER JOIN dbo.CONCEPT b 
--	on a.condition_source_concept_id =  b.concept_id
INNER JOIN dbo.PERSON c 
	on a.person_id = c.person_id  
--INNER JOIN dbo.LOCATION f 
--	on c.location_id = f.location_id
WHERE 
	(  a.condition_source_value LIKE '%C16.9%'
	OR a.condition_source_value LIKE '%C16.1%'
	OR a.condition_source_value LIKE '%C16.2%'
	OR a.condition_source_value LIKE '%C16.3%'
	OR a.condition_source_value LIKE '%C16.4%'
	OR a.condition_source_value LIKE '%C16.5%'
	OR a.condition_source_value LIKE '%C16.6%'
	OR a.condition_source_value LIKE '%C16.7%'
	OR a.condition_source_value LIKE '%C16.8%')
   and a.condition_source_value not like '%C49.A2%';