
SELECT DISTINCT TOP 100 
	obs.observation_concept_id,
	c.concept_name,
	obs.observation_source_value
FROM OBSERVATION obs
JOIN concept c
	ON obs.observation_concept_id = c.concept_id
AND (concept_name LIKE '%tobacco%' OR concept_name LIKE '%smoking%');

