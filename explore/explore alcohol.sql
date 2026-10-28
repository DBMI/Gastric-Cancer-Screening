
SELECT DISTINCT 
	c.concept_name,
	c.domain_id,
	c.vocabulary_id,
	c.concept_code,
	obs.observation_concept_id,
	obs.observation_source_value,
	obs.value_as_string
FROM observation obs
JOIN concept c
	ON obs.observation_concept_id = c.concept_id
   AND concept_name LIKE '%drink%';

   
SELECT DISTINCT 
	observation_concept_id
FROM observation obs
JOIN concept c
	ON obs.observation_concept_id = c.concept_id
   AND concept_name LIKE '%drink%';

SELECT DISTINCT 
	c.concept_name,
	c.domain_id,
	c.vocabulary_id,
	c.concept_code,
	obs.observation_concept_id,
	obs.observation_source_value,
	obs.value_as_string
FROM observation obs
JOIN concept c
	ON obs.observation_concept_id = c.concept_id
   AND concept_name LIKE '%alcohol%';
