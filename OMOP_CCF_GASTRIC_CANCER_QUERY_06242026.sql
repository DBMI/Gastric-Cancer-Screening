
create or replace TABLE INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_STUDY AS
with PATIENT_GC_LIST as 
(select *
FROM
(
select   a.Person_id as STUDY_PAT_ID,  CONCEPT_NAME ,CONCEPT_CODE, condition_start_date as INITIAL_DX_DT ,BIRTH_DATETIME
        ,GENDER_SOURCE_VALUE ,race_source_value , ethnicity_source_value ,f.state ,c.person_source_value  --,enterpriseid 
        ,case when  f.state ilike '%fl%' then 'FLORIDA' else 'OHIO' end as STUDY_STATE
        ,row_number() over (partition by a.Person_id order by condition_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE a
    inner join CDM_SILVER_OMOP_PRD.OMOP.CONCEPT b on a.condition_source_concept_id =  b.concept_id
    inner join  CDM_SILVER_OMOP_PRD.OMOP.PERSON c on c.person_id = a.person_id  
    inner join CDM_SILVER_OMOP_PRD.OMOP.LOCATION f on f.location_id = c.location_id
   -- inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.GASTRIC_CA_ONCOLOG2 g on g.pat_id = c.person_source_value 
    where a.condition_source_value ilike any ('%C16.9%','%C16.1%','%C16.2%','%C16.3%','%C16.4%','%C16.5%','%C16.6%','%C16.7%','%C16.8%' )
          and  condition_source_value not ilike  '%C49.A2%'
  )x where rn = 1    and INITIAL_DX_DT >= '2010-01-01'        
)

,FIRST_ENC as
(select *
from
(select A.PERSON_ID,  a.visit_start_date as FIRST_ENC_DT
        ,row_number () over (partition by a.PERSON_ID order by a.visit_start_date asc) as rn3
from  CDM_SILVER_OMOP_PRD.OMOP.VISIT_OCCURRENCE a
        INNER JOIN PATIENT_GC_LIST b on a.PERSON_ID = b.STUDY_PAT_ID
)x where rn3 = 1 )

,Diagnosis_CNT as
(select   a.Person_id as STUDY_PAT_ID,  count(*) as COUNT_DX
          -- ,row_number() over (partition by a.Person_id order by condition_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE a
    inner join CDM_SILVER_OMOP_PRD.OMOP.CONCEPT b on a.condition_source_concept_id =  b.concept_id
    inner join  CDM_SILVER_OMOP_PRD.OMOP.PERSON c on c.person_id = a.person_id  
    inner join CDM_SILVER_OMOP_PRD.OMOP.LOCATION f on f.location_id = c.location_id
  --  inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.GASTRIC_CA_ONCOLOG2 g on g.pat_id = c.person_source_value 
    where a.condition_source_value ilike any ('%C16.9%','%C16.1%','%C16.2%','%C16.3%','%C16.4%','%C16.5%','%C16.6%','%C16.7%','%C16.8%' )
          and  condition_source_value not ilike  '%C49.A2%'
    group by a.Person_id)
--  16442370672993795537


select *
from
(
select   a.*, FIRST_ENC_DT, visit_start_date as PCP_DT_PRIOR_TO_DX  , visit_source_value as study_visit_source, specialty_source_value as study_Specialty
        ,COUNT_DX,row_number() over (partition by a.STUDY_PAT_ID order by visit_start_date desc) as rn2 --,ONCOLOG_DX_DT
        
from PATIENT_GC_LIST a 
inner join CDM_SILVER_OMOP_PRD.OMOP.VISIT_OCCURRENCE b on a.STUDY_PAT_ID = b.person_id
left outer  JOIN CDM_SILVER_OMOP_PRD.OMOP.PROVIDER  c on b.provider_id = c.provider_id

left outer join FIRST_ENC d on d.person_id = a.STUDY_PAT_ID
left outer join Diagnosis_CNT e on e.STUDY_PAT_ID =  a.STUDY_PAT_ID
--left outer join ONCOLOG_DX_DT f on a.study_pat_id = f.study_pat_id

 where cast(VISIT_START_DATE as date) < dateadd(year,-1,cast(INITIAL_DX_DT as date)) 

)x  where COUNT_DX >= 3
      



/************************** CONTROLS *****************************/

--  select  count(*) from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.GASTRIC_CA_STUDY_CONTROL 
create or replace table INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.GASTRIC_CA_STUDY_CONTROL as
with CONTROLS as
(select *
from
(
select top 2000000 c.person_id  as Study_Person_ID
 ,c.GENDER_SOURCE_VALUE CONTROL_GENDER ,c.race_source_value CONTROL_RACE , c.ethnicity_source_value as CONTROL_ETHNICITY,f.state CONTROL_STATE
,a.visit_start_date , a.visit_source_value, b.specialty_source_value as CONTROL_SPECIALTY
        ,case when  f.state ilike '%fl%' then 'FLORIDA' else 'OHIO' end as STUDY_CNTRL_STATE
    ,c.BIRTH_DATETIME as CONTROL_DOB
       ,Random() as Random1
        ,row_number() over (partition by a.person_id order by a.visit_start_date asc) as rn3
from  CDM_SILVER_OMOP_PRD.OMOP.VISIT_OCCURRENCE a
        INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.PROVIDER b ON a.provider_id = b.provider_id
        inner join  CDM_SILVER_OMOP_PRD.OMOP.PERSON c on c.person_id = a.person_id  
            inner join CDM_SILVER_OMOP_PRD.OMOP.LOCATION f on f.location_id = c.location_id
 where datediff(year,c.BIRTH_DATETIME,a.visit_start_date)  between 40 and 80
)x 
)

SELECT *

FROM INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_STUDY A
inner join CONTROLS b ON cast(b.visit_start_date as date) between dateadd(day,-30,cast(PCP_DT_PRIOR_TO_DX as date)) and dateadd(day,30,cast(PCP_DT_PRIOR_TO_DX as date))


--  select * from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT order by study_pat_id
create or replace table INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT as
 with GASTRIC_CA_COHORT1 as
 (select  y.*
FROM
(
select x.*
			,row_number() over (partition by STUDY_PAT_ID order by Random_Seed asc) as rn5
from
(
select a.*
			,row_number() over (partition by a.STUDY_PERSON_ID order by a.Random1 asc) as rn4 
			,RANDOM() as Random_Seed

from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.GASTRIC_CA_STUDY_CONTROL a
)x where rn4 = 1
)y where rn5 <= 5
)  --ORDER BY STUDY_PAT_ID , rn5

select *
from
(
select STUDY_PAT_ID,  PCP_DT_PRIOR_TO_DX , GENDER_SOURCE_VALUE, race_source_value, ethnicity_source_value, Study_state, 'STUDY'
        ,row_number() over (partition by STUDY_PAT_ID order by INITIAL_DX_DT asc) as rn
from GASTRIC_CA_COHORT1
)x  WHere rn = 1

UNION

select Study_person_id ,visit_start_date,  CONTROL_GENDER ,CONTROL_RACE , CONTROL_ETHNICITY,STUDY_CNTRL_STATE  ,'CONTROL','1'

from GASTRIC_CA_COHORT1



/***********************************************************************************************************************/
/***********************************************************************************************************************/
/***********************************************************************************************************************/



create or replace table INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT2 as 
with BMI as
(select *
from
(select a.study_pat_id, b.measurement_date as BMI_DT , b.value_as_number as BMI , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value ilike '%BMI%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_as_number is not null
)x where rn = 1)
,WEIGHT as
(select *
from
(select a.study_pat_id, b.measurement_date as WEIGHT_DT , b.value_as_number as WEIGHT , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value ilike '%WEIGHT%' 
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_as_number is not null
)x where rn = 1)
,ALCOHOL as
(select *
from
(select a.study_pat_id , b.observation_date as ALCOHOL_DT ,observation_source_value as ALCOHOL , VALUE_AS_STRING
        ,row_number() over (partition by a.study_pat_id order by b.observation_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.OBSERVATION b on a.study_pat_id = b.person_id
where observation_source_value = 'ALCOHOL_USE_C' -- and value_as_string = 'Yes'
and cast(b.observation_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,TOBACCO as
(select *
from
(select a.study_pat_id , b.observation_date as TOBACCO_DT ,observation_source_value as TOBACCO , VALUE_AS_STRING
        ,row_number() over (partition by a.study_pat_id order by b.observation_date desc) as rn2
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.OBSERVATION b on a.study_pat_id = b.person_id
where observation_source_value = 'TOBACCO_USER_C' -- and value_as_string = 'Yes'
and cast(b.observation_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn2 = 1)
,FAM_HX_CA as
(select *
from
(select a.study_pat_id , b.condition_start_date as FAM_HX_CA_DT  ,condition_source_value as FAM_HX_CA
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date asc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value between 'C1' and 'C99'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,PERSONAL_HX_CA_ICD as
(select *
from
(select a.study_pat_id , b.condition_start_date as PERSONAL_HX_CA_ICD_DT ,b.condition_source_value as PERSONAL_HX_CA_ICD
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date asc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where (condition_source_value between 'C1' and 'C99' OR condition_source_value between 'D1' and 'D49' )
and not (condition_source_value ilike any ('C25%','C16'))
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)

,Diabetes as
(select *
from
(select a.study_pat_id , b.condition_start_date  as Diabetes_DT,b.condition_source_value Diabetes
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date asc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike any ('E10%','E11%','E13%')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Hypertension as
(select *
from
(select a.study_pat_id , b.condition_start_date as Hypertension_DT ,b.condition_source_value as Hypertension
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike 'I10%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Hypercholesterolemia as
(select *
from
(select a.study_pat_id , b.condition_start_date as Hypercholesterolemia_DT,b.condition_source_value as Hypercholesterolemia
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value = 'E78.5'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Coronary_artery_disease as
(select *
from
(select a.study_pat_id , b.condition_start_date as Coronary_artery_disease_DT ,b.condition_source_value as Coronary_artery_disease
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike  'I25%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Cirrhosis as
(select *
from
(select a.study_pat_id , b.condition_start_date as Cirrhosis_DT  ,b.condition_source_value as Cirrhosis
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike  'K74%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Emphysema as
(select *
from
(select a.study_pat_id , b.condition_start_date as Emphysema_DT  ,b.condition_source_value as Emphysema
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike  'J43%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Stroke as
(select *
from
(select a.study_pat_id , b.condition_start_date as Stroke_DT ,b.condition_source_value as Stroke
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike 'I63%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Gastric_Ulcer as
(select *
from
(select a.study_pat_id , b.condition_start_date as Gastric_Ulcer_DT ,b.condition_source_value as Gastric_Ulcer
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike 'K25%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Viral_hepatitis as
(select *
from
(select a.study_pat_id , b.condition_start_date as Viral_hepatitis_DT  ,b.condition_source_value as Viral_hepatitis
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike  'B19%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Depression as
(select *
from
(select a.study_pat_id , b.condition_start_date as Depression_DT ,b.condition_source_value as Depression
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike 'F32%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,IBD as
(select *
from
(select a.study_pat_id , b.condition_start_date as IBD_DT ,b.condition_source_value as IBD
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike any ('K50%','K51%')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Chronic_respiratory_disease as
(select *
from
(select a.study_pat_id , b.condition_start_date as Chronic_respiratory_disease_DT  ,b.condition_source_value as Chronic_respiratory_disease
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike 'J44.9%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Chronic_renal_disease as
(select *
from
(select a.study_pat_id , b.condition_start_date as Chronic_renal_disease_DT ,b.condition_source_value as Chronic_renal_disease
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike 'N18%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Upper_Gastrointestinal_Disease as
(select *
from
(select a.study_pat_id , b.condition_start_date as Upper_Gastrointestinal_Disease_DT ,b.condition_source_value as Upper_Gastrointestinal_Disease
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value between 'K20' and 'K31.9'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Lower_Gastrointestinal_Disease as
(select *
from
(select a.study_pat_id , b.condition_start_date as Lower_Gastrointestinal_Disease_DT  ,b.condition_source_value as Lower_Gastrointestinal_Disease
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value between 'K50' and 'K52.9'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)


select a.* 
        ,BMI_DT , BMI
        ,WEIGHT_DT , WEIGHT
        ,ALCOHOL_DT , ALCOHOL
        ,TOBACCO_DT , TOBACCO
        ,FAM_HX_CA_DT , FAM_HX_CA
        ,PERSONAL_HX_CA_ICD_DT , PERSONAL_HX_CA_ICD
        ,Diabetes_DT , Diabetes
        ,Hypertension_DT , Hypertension
        ,Hypercholesterolemia_DT , Hypercholesterolemia
        ,Coronary_artery_disease_DT , Coronary_artery_disease
        ,Cirrhosis_DT , Cirrhosis
        ,Emphysema_DT , Emphysema
        ,Stroke_DT , Stroke
        ,Gastric_Ulcer_DT , Gastric_Ulcer
        ,Viral_hepatitis_DT , Viral_hepatitis
        ,Depression_DT , Depression
        ,IBD_DT , IBD
        ,Chronic_respiratory_disease_DT , Chronic_respiratory_disease
        ,Chronic_renal_disease_DT , Chronic_renal_disease
        ,Upper_Gastrointestinal_Disease_DT , Upper_Gastrointestinal_Disease
        ,Lower_Gastrointestinal_Disease_DT , Lower_Gastrointestinal_Disease

from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a

        left outer join BMI b ON a.study_pat_id = b.study_pat_id
        left outer join WEIGHT c ON a.study_pat_id = c.study_pat_id
        left outer join ALCOHOL d ON a.study_pat_id = d.study_pat_id
        left outer join TOBACCO e ON a.study_pat_id = e.study_pat_id
        left outer join FAM_HX_CA f ON a.study_pat_id = f.study_pat_id
        left outer join PERSONAL_HX_CA_ICD g ON a.study_pat_id = g.study_pat_id
        left outer join Diabetes h ON a.study_pat_id = h.study_pat_id
        left outer join Hypertension i ON a.study_pat_id = i.study_pat_id
        left outer join Hypercholesterolemia j ON a.study_pat_id = j.study_pat_id
        left outer join Coronary_artery_disease k ON a.study_pat_id = k.study_pat_id
        left outer join Cirrhosis l ON a.study_pat_id = l.study_pat_id
        left outer join Emphysema m ON a.study_pat_id = m.study_pat_id
        left outer join Stroke n ON a.study_pat_id = n.study_pat_id
        left outer join Gastric_Ulcer o ON a.study_pat_id = o.study_pat_id
        left outer join Viral_hepatitis p ON a.study_pat_id = p.study_pat_id
        left outer join Depression q ON a.study_pat_id = q.study_pat_id
        left outer join IBD r ON a.study_pat_id = r.study_pat_id
        left outer join Chronic_respiratory_disease s ON a.study_pat_id = s.study_pat_id
        left outer join Chronic_renal_disease t ON a.study_pat_id = t.study_pat_id
        left outer join Upper_Gastrointestinal_Disease u ON a.study_pat_id = u.study_pat_id
        left outer join Lower_Gastrointestinal_Disease v ON a.study_pat_id = v.study_pat_id

/***************************************************************************************************/


create or replace table INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT3 as 

with Gallstone_disorders as
(select *
from
(select a.study_pat_id , b.condition_start_date as Gallstone_disorders_DT  ,b.condition_source_value as Gallstone_disorders
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ILIKE 'K80%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Hereditary_cancer_syndromes as
(select *
from
(select a.study_pat_id , b.condition_start_date as Hereditary_cancer_syndromes_DT  ,b.condition_source_value as Hereditary_cancer_syndromes
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ILIKE 'Z15.0%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Peptic_ulcer as
(select *
from
(select a.study_pat_id , b.condition_start_date as Peptic_ulcer_DT  ,b.condition_source_value as Peptic_ulcer
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ILIKE 'K27%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Deep_vein_thrombosis as
(select *
from
(select a.study_pat_id , b.condition_start_date as Deep_vein_thrombosis_DT  ,b.condition_source_value as Deep_vein_thrombosis
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('I82.40','I82.401','I82.402','I82.403','I82.50','I82.501','I82.502','I82.503')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Pulmonary_Embolism as
(select *
from
(select a.study_pat_id , b.condition_start_date as Pulmonary_Embolism_DT  ,b.condition_source_value as Pulmonary_Embolism
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value  ILIKE 'I26%'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,PERSONAL_HX_Gallstones as
(select *
from
(select a.study_pat_id , b.condition_start_date as PERSONAL_HX_Gallstones_DT  ,b.condition_source_value as PERSONAL_HX_Gallstones
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value = 'Z87.79'
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,PERSONAL_HX_cholecystectomy as
(select *
from
(select a.study_pat_id , b.condition_start_date as PERSONAL_HX_cholecystectomy_DT  ,b.condition_source_value as PERSONAL_HX_cholecystectomy
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ilike  'Z90.5%' 
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Vitamin_D_deficiency as
(select *
from
(select a.study_pat_id , b.condition_start_date as Vitamin_D_deficiency_DT  ,b.condition_source_value as Vitamin_D_deficiency
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('E55.0','E55.9','E64.3')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Pancreatic_Disorders as
(select *
from
(select a.study_pat_id , b.condition_start_date as Pancreatic_Disorders_DT  ,b.condition_source_value as Pancreatic_Disorders
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('K86.81')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Chronic_pancreatitis as
(select *
from
(select a.study_pat_id , b.condition_start_date as Chronic_pancreatitis_DT  ,b.condition_source_value as Chronic_pancreatitis
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('K86.1')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Acute_pancreatitis as
(select *
from
(select a.study_pat_id , b.condition_start_date as Acute_pancreatitis_DT  ,b.condition_source_value as Acute_pancreatitis
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('K85.0','K85.1','K85.2','K85.3','K85.8','K85.9','K85.90','K85.91') 
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Pseudocyst as
(select *
from
(select a.study_pat_id , b.condition_start_date as Pseudocyst_DT  ,b.condition_source_value as Pseudocyst
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ILIKE ('K83%')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Biliary_tract_disease as
(select *
from
(select a.study_pat_id , b.condition_start_date as Biliary_tract_disease_DT  ,b.condition_source_value as Biliary_tract_disease
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ILIKE ('K83%')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Abdominal_pain as
(select *
from
(select a.study_pat_id , b.condition_start_date as Abdominal_pain_DT  ,b.condition_source_value as Abdominal_pain
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ILIKE ('R10%')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Jaundice as
(select *
from
(select a.study_pat_id , b.condition_start_date as Jaundice_DT  ,b.condition_source_value as Jaundice
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ILIKE  ('R17%')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Dyspepsia as
(select *
from
(select a.study_pat_id , b.condition_start_date as Dyspepsia_DT  ,b.condition_source_value as Dyspepsia
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value ILIKE  ('K30%')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Nausea_and_vomiting as
(select *
from
(select a.study_pat_id , b.condition_start_date as Nausea_and_vomiting_DT  ,b.condition_source_value as Nausea_and_vomiting
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('R11.0','R11.1','R11.10','R11.11','R11.12','R11.2')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Weight_loss as
(select *
from
(select a.study_pat_id , b.condition_start_date as Weight_loss_DT  ,b.condition_source_value as Weight_loss
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('R63.4')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Back_pain as
(select *
from
(select a.study_pat_id , b.condition_start_date as Back_pain_DT  ,b.condition_source_value as Back_pain
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('M54.50','M54.51','M54.59','M54.4','M54.8','M54.89')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Constipation as
(select *
from
(select a.study_pat_id , b.condition_start_date as Constipation_DT  ,b.condition_source_value as Constipation
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('K59.00','K59.01','K59.02','K59.03','K59.04','K59.09')
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Diarrhea as
(select *
from
(select a.study_pat_id , b.condition_start_date as Diarrhea_DT  ,b.condition_source_value as Diarrhea
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('K52.9','K59.1','R19.7') 
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)
,Malaise_fatigue as
(select *
from
(select a.study_pat_id , b.condition_start_date as Malaise_fatigue_DT  ,b.condition_source_value as Malaise_fatigue
        ,row_number() over (partition by a.study_pat_id order by b.condition_start_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.CONDITION_OCCURRENCE b on a.study_pat_id = b.person_id
where condition_source_value IN ('R53','R53.9','R53.81','R53.82','R53.83') 
and cast(b.condition_start_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
)x where rn = 1)



select a.*
        ,Gallstone_disorders_DT , Gallstone_disorders
        ,Hereditary_cancer_syndromes_DT , Hereditary_cancer_syndromes
        ,Peptic_ulcer_DT , Peptic_ulcer
        ,Deep_vein_thrombosis_DT , Deep_vein_thrombosis
        ,Pulmonary_Embolism_DT , Pulmonary_Embolism
        ,PERSONAL_HX_Gallstones_DT , PERSONAL_HX_Gallstones
        ,PERSONAL_HX_cholecystectomy_DT , PERSONAL_HX_cholecystectomy
        ,Vitamin_D_deficiency_DT , Vitamin_D_deficiency
        ,Pancreatic_Disorders_DT , Pancreatic_Disorders
        ,Chronic_pancreatitis_DT , Chronic_pancreatitis
        ,Acute_pancreatitis_DT , Acute_pancreatitis
        ,Pseudocyst_DT , Pseudocyst
        ,Biliary_tract_disease_DT , Biliary_tract_disease
        ,Abdominal_pain_DT , Abdominal_pain
        ,Jaundice_DT , Jaundice
        ,Dyspepsia_DT , Dyspepsia
        ,Nausea_and_vomiting_DT , Nausea_and_vomiting
        ,Weight_loss_DT ,Weight_loss
        ,Back_pain_DT , Back_pain
        ,Constipation_DT , Constipation
        ,Diarrhea_DT , Diarrhea
        ,Malaise_fatigue_DT , Malaise_fatigue


from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT2 a

        left outer join Gallstone_disorders b ON a.study_pat_id = b.study_pat_id
        left outer join Hereditary_cancer_syndromes  c  on a.study_pat_id = c.study_pat_id
        left outer join Peptic_ulcer d ON a.study_pat_id = d.study_pat_id
        left outer join Deep_vein_thrombosis e on a.study_pat_id = e.study_pat_id
        left outer join Pulmonary_Embolism f  on a.study_pat_id = f.study_pat_id
        left outer join PERSONAL_HX_Gallstones g  on a.study_pat_id = g.study_pat_id
        left outer join PERSONAL_HX_cholecystectomy h  on a.study_pat_id = h.study_pat_id
        left outer join Vitamin_D_deficiency i   on a.study_pat_id = i.study_pat_id
        left outer join Pancreatic_Disorders j  on a.study_pat_id = j.study_pat_id
        left outer join Chronic_pancreatitis k  on a.study_pat_id = k.study_pat_id
        left outer join Acute_pancreatitis l  on a.study_pat_id = l.study_pat_id
        left outer join Pseudocyst m  on a.study_pat_id = m.study_pat_id
        left outer join Biliary_tract_disease n  on a.study_pat_id = n.study_pat_id
        left outer join Abdominal_pain o  on  a.study_pat_id = o.study_pat_id
        left outer join Jaundice p  on a.study_pat_id = p.study_pat_id
        left outer join Dyspepsia q  on a.study_pat_id = q.study_pat_id
        left outer join Nausea_and_vomiting r  on a.study_pat_id = r.study_pat_id
        left outer join Weight_loss s  on a.study_pat_id = s.study_pat_id
        left outer join Back_pain t  on a.study_pat_id = t.study_pat_id
        left outer join Constipation u  on a.study_pat_id = u.study_pat_id
        left outer join Diarrhea v  on a.study_pat_id = v.study_pat_id
        left outer join Malaise_fatigue w  on a.study_pat_id = w.study_pat_id



/********************** MEDICATION QUERY *************************************/
/*****************************************************************************/


create or replace table INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT4 as 
with Metformin_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as Metformin , a.drug_exposure_start_date  as Metformin_DT
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where a.drug_source_value ilike '%Metformin%'  and a.route_source_value = '1201'
)x where rn = 1)
,Insulin_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as Insulin , a.drug_exposure_start_date as Insulin_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where a.drug_source_value ilike '%Insulin%'  and a.route_source_value = '1201'
)x where rn = 1)

,Aspirin_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as Aspirin , a.drug_exposure_start_date as Aspirin_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where a.drug_source_value ilike '%Aspirin%'  and a.route_source_value = '1201'
)x where rn = 1)

,NSAID_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as NSAID , a.drug_exposure_start_date as NSAID_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where (a.drug_source_value ilike '%ibuprofen%'  OR a.drug_source_value ilike '%naproxen%' 
     OR a.drug_source_value ilike '%aspirin%'  OR a.drug_source_value ilike '%diclofenac%'
      OR a.drug_source_value ilike '%celecoxib%')
     and a.route_source_value = '1201'
)x where rn = 1)
,Beta_Blocker_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as Beta_Blocker , a.drug_exposure_start_date as Beta_Blocker_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where (a.drug_source_value ilike '%Metoprolol%'OR  a.drug_source_value ilike '%Atenolol%'  
     OR a.drug_source_value ilike '%Carvedilol%'OR  a.drug_source_value ilike '%Propranolol%' )
     and a.route_source_value = '1201'
)x where rn = 1)

,Statin_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as Statin , a.drug_exposure_start_date as Statin_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where a.drug_source_value ilike '%Statin%'  and a.route_source_value = '1201'
)x where rn = 1)
,PPI_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as PPI , a.drug_exposure_start_date as PPI_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
        inner join CDM_SILVER_OMOP_PRD.OMOP.CONCEPT d on a.drug_concept_id = d.concept_id
     where (a.drug_source_value ilike '%omeprazole%'  OR a.drug_source_value ilike '%esomeprazole%'  
     OR  a.drug_source_value ilike '%lansoprazole%'  OR a.drug_source_value ilike '%pantoprazole%'
     OR  a.drug_source_value ilike '%rabeprazole%'  OR a.drug_source_value ilike '%dexlansoprazole%')
     and a.route_source_value = '1201' and DOMAIN_ID = 'Drug'
)x where rn = 1)
,Sulfonylurea_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as Sulfonylurea , a.drug_exposure_start_date as Sulfonylurea_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where (a.drug_source_value ilike '%glimepiride%'  or  a.drug_source_value ilike '%glipizide%' 
     OR a.drug_source_value ilike '%glyburide%'  or  a.drug_source_value ilike '%Glynase%' )
     and a.route_source_value = '1201'
)x where rn = 1)
,Diuretics_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as Diuretics , a.drug_exposure_start_date as Diuretics_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where a.drug_source_value ilike ANY ('%Furosemide%','%Bumetanide%','%Torsemide%','%Ethacrynic%','%Hydrochlorothiazide%','%Chlorthalidone%','%Indapamide%'
        ,'%Metolazone%','%Chlorothiazide%','%Spironolactone%','%Triamterene%','%Amiloride%','%Eplerenone%')
     and a.route_source_value = '1201'
)x where rn = 1)
,Antipsychotics_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as Antipsychotics , a.drug_exposure_start_date as Antipsychotics_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where a.drug_source_value ilike ANY ('%Aripiprazole%','%Olanzapine%','%Risperidone%','%Haloperidol%','%Chlorpromazine%')
     and a.route_source_value = '1201'
)x where rn = 1)
,Hormone_Start as 
(select *
FROM
(select b.study_pat_id ,a.drug_source_value as Hormone , a.drug_exposure_start_date as Hormone_DT 
        ,row_number() over (partition by b.study_pat_id order by a.drug_exposure_start_date asc) as rn
from CDM_SILVER_OMOP_PRD.OMOP.DRUG_EXPOSURE a
        inner join INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT b on a.person_id = b.study_pat_id
     where a.drug_source_value ilike ANY ('%Activella%','%Femhrt%','%Jinteli%','%Prefest%','%Bijuva%','%Angeliq%','%Combipatch%'
        ,'%Climara%','%Evorel%','%Femoston Conti%','%Kliovance%','%Kliofem%')
     and a.route_source_value = '1201'
)x where rn = 1)

SELECT a.*
        ,Metformin , Metformin_DT
        ,Insulin , Insulin_DT
        ,Aspirin , Aspirin_DT
        ,NSAID , NSAID_DT
        ,Beta_Blocker , Beta_Blocker_DT
        ,Statin , Statin_DT
        ,PPI , PPI_DT
        ,Sulfonylurea , Sulfonylurea_DT
        ,Diuretics , Diuretics_DT
        ,Antipsychotics , Antipsychotics_DT
        ,Hormone , Hormone_DT

from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT3 a
        left outer join Metformin_Start b ON a.study_pat_id = b.study_pat_id
        left outer join Insulin_Start c ON a.study_pat_id = c.study_pat_id
        left outer join Aspirin_Start d ON a.study_pat_id = d.study_pat_id
        left outer join NSAID_Start e ON a.study_pat_id = e.study_pat_id
        left outer join Beta_Blocker_Start f ON a.study_pat_id = f.study_pat_id
        left outer join Statin_Start g ON a.study_pat_id = g.study_pat_id
        left outer join PPI_Start h  ON a.study_pat_id = h.study_pat_id
        left outer join Sulfonylurea_Start i ON a.study_pat_id = i.study_pat_id
        left outer join Diuretics_Start j ON a.study_pat_id = j.study_pat_id
        left outer join Antipsychotics_Start k ON a.study_pat_id = k.study_pat_id
        left outer join Hormone_Start l on a.study_pat_id = l.study_pat_id




/********************************* LABS QUERY *************************/
/**********************************************************************/


create or replace table INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT5 as 
with hgba1c as
(select *
from
(select a.study_pat_id , b.measurement_date as hgba1c_DT , b.value_source_value as hgba1c_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value ilike '%HGBA1C%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,ALP as
(select *
from
(select a.study_pat_id , b.measurement_date as ALP_DT , b.value_source_value as ALP_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value IN ('ALKALINE PHOSPHATASE','ALK PHOS') -- ilike '%ALK%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,bilirubin as
(select *
from
(select a.study_pat_id , b.measurement_date as bilirubin_DT , b.value_source_value as bilirubin_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value = 'BILIRUBIN, TOTAL'  -- ilike '%bilirubin%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,ALT as
(select *
from
(select a.study_pat_id , b.measurement_date as ALT_DT , b.value_source_value as ALT_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value in ('SGPT (ALT)','ALT')  -- ilike '%bilirubin%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,AST as
(select *
from
(select a.study_pat_id , b.measurement_date as AST_DT , b.value_source_value as AST_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value in ('SGOT (AST)','AST')  -- ilike '%bilirubin%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,lipase as
(select *
from
(select a.study_pat_id , b.measurement_date as lipase_DT , b.value_source_value as lipase_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value = 'LIPASE'   -- ilike '%lipase%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,creatinine as
(select *
from
(select a.study_pat_id , b.measurement_date as creatinine_DT , b.value_source_value as creatinine_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value = 'CREATININE'   --ilike '%creatinine%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,mcv as
(select *
from
(select a.study_pat_id , b.measurement_date as mcv_DT , b.value_source_value as mcv_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value ilike 'mcv%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,rdw as
(select *
from
(select a.study_pat_id , b.measurement_date as rdw_DT , b.value_source_value as rdw_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value ilike 'rdw%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,wbc as
(select *
from
(select a.study_pat_id , b.measurement_date as wbc_DT , b.value_source_value as wbc_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value = 'WBC'  -- ilike '%wbc%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,lymphocytes as
(select *
from
(select a.study_pat_id , b.measurement_date as lymphocytes_DT , b.value_source_value as lymphocytes_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value IN ('LYMPHOCYTES','LYMPHOCYTES - INTL')  --ilike '%lymphocytes%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,bun as
(select *
from
(select a.study_pat_id , b.measurement_date as bun_DT , b.value_source_value as bun_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value IN ('BUN, W.B.','BUN, WOOSTER','BUN')  --  ilike '%bun%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,calcium as
(select *
from
(select a.study_pat_id , b.measurement_date as calcium_DT , b.value_source_value as calcium_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value  = 'CALCIUM'   --  ilike '%calcium%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,platelet as
(select *
from
(select a.study_pat_id , b.measurement_date as platelet_DT , b.value_source_value as platelet_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value  = 'PLATELET COUNT' --  ilike '%platelet%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,sodium as
(select *
from
(select a.study_pat_id , b.measurement_date as sodium_DT , b.value_source_value as sodium_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value = 'SODIUM' --  ilike '%sodium%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,phosphorus as
(select *
from
(select a.study_pat_id , b.measurement_date as phosphorus_DT , b.value_source_value as phosphorus_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value  = 'PHOSPHORUS'  -- ilike '%phosphorus%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,hdl as
(select *
from
(select a.study_pat_id , b.measurement_date as hdl_DT , b.value_source_value as hdl_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value  IN ('HDL CHOLESTEROL','HDL-C')  -- ilike '%hdl%'
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,ldl as
(select *
from
(select a.study_pat_id , b.measurement_date as ldl_DT , b.value_source_value as ldl_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value IN ('LDL CHOLESTEROL','LDL','LDL CALCULATED','LDL CHOL DIRECT','LDL CHOL, CALCULATED','LDL CHOL, WOOSTER') --   ilike '%ldl%'   
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,total_cholesterol as
(select *
from
(select a.study_pat_id , b.measurement_date as total_cholesterol_DT , b.value_source_value as total_cholesterol_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value ilike 'TOTAL CHOLESTEROL%'  -- ilike '%TOTAL CHOL%'   
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,triglycerides as
(select *
from
(select a.study_pat_id , b.measurement_date as triglycerides_DT , b.value_source_value as triglycerides_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value = 'TRIGLYCERIDES' --  ilike '%triglycerides%'  
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,glucose as
(select *
from
(select a.study_pat_id , b.measurement_date as glucose_DT , b.value_source_value as glucose_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value  IN ('GLUCOSE','ESTIMATED AVERAGE GLUCOSE') -- ilike '%glucose%'  
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,hematocrit as
(select *
from
(select a.study_pat_id , b.measurement_date as hematocrit_DT , b.value_source_value as hematocrit_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value  = 'HEMATOCRIT'  -- ilike '%hematocrit%'  
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,hemoglobin as
(select *
from
(select a.study_pat_id , b.measurement_date as hemoglobin_DT , b.value_source_value as hemoglobin_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value = 'HEMOGLOBIN'  -- ilike '%hemoglobin%'  
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)
,albumin as
(select *
from
(select a.study_pat_id , b.measurement_date as albumin_DT , b.value_source_value as albumin_VALUE , measurement_source_value
        ,row_number() over (partition by a.study_pat_id order by b.measurement_date desc) as rn
from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT a 
INNER JOIN CDM_SILVER_OMOP_PRD.OMOP.MEASUREMENT b on a.study_pat_id = b.person_id
where  measurement_source_value = 'ALBUMIN'  -- ilike '%albumin%'  
and cast(b.measurement_date as date) <= cast(PCP_DT_PRIOR_TO_DX as date)
and  b.value_source_value is not null
)x where rn = 1)


select a.*
        ,hgba1c_DT , hgba1c_VALUE
        ,ALP_DT , ALP_VALUE
        ,Bilirubin_DT , Bilirubin_VALUE
        ,ALT_DT , ALT_VALUE
        ,AST_DT , AST_VALUE
        ,Lipase_DT , Lipase_VALUE
        ,Creatinine_DT , Creatinine_VALUE
        ,Mcv_DT , Mcv_VALUE
        ,Rdw_DT , Rdw_VALUE
        ,Wbc_DT , Wbc_VALUE
        ,Lymphocytes_DT , Lymphocytes_VALUE
        ,Bun_DT , Bun_VALUE
        ,Calcium_DT , Calcium_VALUE
        ,Platelet_DT , Platelet_VALUE
        ,Sodium_DT , Sodium_VALUE
        ,Phosphorus_DT , Phosphorus_VALUE
        ,Hdl_DT , Hdl_VALUE
        ,Ldl_DT , Ldl_VALUE
        ,total_cholesterol_DT , total_cholesterol_VALUE
        ,triglycerides_DT , triglycerides_VALUE
        ,glucose_DT , glucose_VALUE
        ,hematocrit_DT , hematocrit_VALUE
        ,hemoglobin_DT , hemoglobin_VALUE
        ,albumin_DT , albumin_VALUE

from INSTITUTES_SILVER_DDIHSNI_DEV.WAREHOUSE.OMOP_COHORT4 a

        left outer join hgba1c b ON  a.study_pat_id = b.study_pat_id
        left outer join ALP c ON  a.study_pat_id = c.study_pat_id
        left outer join Bilirubin d ON  a.study_pat_id = d.study_pat_id
        left outer join ALT e ON  a.study_pat_id = e.study_pat_id
        left outer join AST f ON  a.study_pat_id = f.study_pat_id
        left outer join Lipase g ON  a.study_pat_id = g.study_pat_id
        left outer join Creatinine h ON  a.study_pat_id = h.study_pat_id
        left outer join Mcv i ON  a.study_pat_id = i.study_pat_id
        left outer join Rdw j ON  a.study_pat_id = j.study_pat_id
        left outer join Wbc k ON  a.study_pat_id = k.study_pat_id
        left outer join Lymphocytes l ON  a.study_pat_id = l.study_pat_id
        left outer join Bun m ON  a.study_pat_id = m.study_pat_id 
        left outer join Calcium n ON  a.study_pat_id = n.study_pat_id
        left outer join Platelet o ON  a.study_pat_id = o.study_pat_id
        left outer join Sodium p ON  a.study_pat_id = p.study_pat_id
        left outer join Phosphorus q ON  a.study_pat_id = q.study_pat_id
        left outer join Hdl r ON  a.study_pat_id = r.study_pat_id 
        left outer join Ldl s ON  a.study_pat_id = s.study_pat_id
        left outer join total_cholesterol t ON  a.study_pat_id = t.study_pat_id
        left outer join triglycerides u ON  a.study_pat_id = u.study_pat_id
        left outer join glucose v ON  a.study_pat_id = v.study_pat_id
        left outer join hematocrit w ON  a.study_pat_id = w.study_pat_id 
        left outer join hemoglobin x ON  a.study_pat_id = x.study_pat_id
        left outer join albumin y ON  a.study_pat_id = y.study_pat_id


