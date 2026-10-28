SELECT TOP 10 
	b.person_id,
    b.measurement_date AS BMI_DT,
    b.value_as_number AS BMI ,
    row_number() OVER (PARTITION BY b.person_id
                        ORDER BY b.measurement_date DESC) AS rn
FROM dbo.MEASUREMENT b
WHERE measurement_source_value LIKE '%BODY MASS INDEX%'
AND b.value_as_number IS NOT NULL;


SELECT DISTINCT TOP 10 measurement_source_value FROM measurement WHERE measurement_source_value LIKE '%BMI%';
SELECT DISTINCT TOP 10 measurement_source_value FROM measurement WHERE measurement_source_value LIKE '%BMI%';

WITH BMI AS (
SELECT DISTINCT concept_id
FROM concept c
WHERE 
	concept_name LIKE '%Body mass index%'
AND	(concept_class_id IN ('Clinical Observation', 'LOINC Component', 'LOINC Hierarchy')
  OR domain_id = 'Measurement')
)
SELECT TOP 100 * FROM measurement WHERE measurement_concept_id IN (SELECT concept_id from BMI);


WITH Weight AS (
SELECT DISTINCT concept_id
FROM concept c
WHERE 
	concept_name LIKE '%weight%'
AND	(concept_class_id IN ('Clinical Observation', 'LOINC Component', 'LOINC Hierarchy')
  OR domain_id = 'Measurement')
)
SELECT TOP 100 * FROM measurement WHERE measurement_concept_id IN (SELECT concept_id from Weight);

