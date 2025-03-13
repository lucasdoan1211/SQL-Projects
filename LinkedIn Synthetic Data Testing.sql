/******************************************/
/* QUERY 1: DISPLAY DATA FOR USER PROFILE */
/******************************************/
/******************************************/

SELECT CONCAT(u.first_name, " ", u.last_name) full_name, u.image_url profile_image, u.description, o1.name university_name, ed.program university_program, 
o2.name company_name, ex.job_title, COALESCE(exp.total_years_experience,0) total_years_experience, s.skill most_recent_skill
FROM user u
    LEFT JOIN education ed ON u.user_id = ed.user_id AND ed.education_id IN ( /* MOST RECENT EDUCATION */
        SELECT MAX(e2.education_id) -- Flatten by id in case of duplicate overlapping educations
        FROM education e2 /* SUBQUERY BELOW TO IDENTIFY MOST RECENT EDUCATION BASED ON DATE */
        JOIN (SELECT user_id, MAX(end_date) AS max_end_date FROM education e1 WHERE e1.deleted = 0 GROUP BY user_id) AS max_dates 
        ON e2.user_id = max_dates.user_id AND e2.end_date = max_dates.max_end_date
        WHERE e2.deleted = 0 -- omit deleted records
        GROUP BY e2.user_id
    ) 
    LEFT JOIN organization o1 ON ed.organization_id = o1.organization_id
    LEFT JOIN experience ex ON u.user_id = ex.user_id AND ex.experience_id IN ( /* MOST RECENT AND CURRENT WORK EXPERIENCE */ 	
    	SELECT MAX(ex2.experience_id) -- Flatten by id in case of duplicate active employments
		FROM experience ex2  /* SUBQUERY TO BELOW IDENTIFY MOST RECENT AND CURRENT EXPERIENCE BASED ON DATE */
        JOIN (SELECT ex1.user_id, MAX(COALESCE(ex1.end_date,CURDATE())) max_end_date FROM experience ex1 WHERE ex1.deleted = 0 GROUP BY ex1.user_id) max_ex 
        ON ex2.user_id = max_ex.user_id AND COALESCE(ex2.end_date, CURDATE()) = max_ex.max_end_date
        WHERE ex2.end_date is null and ex2.deleted = 0 -- omit deleted records, select null end-date for active employments
		GROUP BY ex2.user_id
    ) 
    LEFT JOIN organization o2 ON ex.organization_id = o2.organization_id
    LEFT JOIN (  /* TOTAL YEARS OF WORK EXPERIENCE */
        SELECT exp1.user_id, ROUND(SUM(DATEDIFF(COALESCE(end_date,CURDATE()), start_date)) / 365.25, 1) total_years_experience
        FROM experience exp1	
        WHERE exp1.deleted = 0 -- omit deleted records
        GROUP BY exp1.user_id
    ) exp ON u.user_id = exp.user_id 
    LEFT JOIN skill s ON u.user_id = s.user_id AND s.skill_id IN ( /* MOST RECENT ACQUIRED SKILL */
        SELECT MAX(s2.skill_id)  -- Flatten by id in case of duplicate skill entries on the same day
        FROM skill s2 /* SUBQUERY BELOW TO IDENTIFY LAST SKILL ENTERED BASED ON DATE */
        JOIN (SELECT user_id, MAX(modified_date) AS max_date FROM skill s1 WHERE s1.deleted = 0 GROUP BY user_id) AS max_dates 
            ON s2.user_id = max_dates.user_id AND s2.modified_date = max_dates.max_date
        WHERE s2.deleted = 0 -- omit deleted records
        GROUP BY s2.user_id
    ) WHERE u.deleted = 0 -- omit deleted records


/* QUERY 2: BUSINESS QUESTION 2 */
/********************************/
/********************************/


SELECT demographic, category, COUNT(*) total, Round((COUNT(*) / MAX(denom))*100,1) AS percentage
FROM (
  (
  SELECT 
      'SEX' demographic
      ,COALESCE(UPPER(sex), 'UNKNOWN') category
  FROM user WHERE user.deleted != 1
  )
UNION ALL
  (
  SELECT 
      'AGE GROUP' demographic
      ,CASE 
          WHEN (DATEDIFF(CURDATE(), birth_date) / 365.25) BETWEEN 18 AND 34 then '18-34'
          WHEN (DATEDIFF(CURDATE(), birth_date) / 365.25) BETWEEN 35 AND 49 then '35-49'
          WHEN (DATEDIFF(CURDATE(), birth_date) / 365.25) >= 50 then '50+' 
          ELSE 'UNKNOWN' END category
  FROM user WHERE user.deleted != 1
  )
UNION ALL
  (
  SELECT 
      'HIGHEST EDUCATION' demographic
      ,CASE 
          WHEN ed.num = 4 THEN 'DOCTORATE'
          WHEN ed.num = 3 THEN 'MASTERS'
          WHEN ed.num = 2 THEN 'BACHELORS'
          WHEN ed.num = 1 THEN 'UNKNOWN OR LESS THAN POST SECONDARY' 
          ELSE 'UNKNOWN OR LESS THAN POST SECONDARY' END category
  FROM user u
  LEFT JOIN (
      SELECT 
          e2.user_id
          ,MAX(CASE 
              WHEN e2.program like '%Doctor%' then 4
              WHEN e2.program like '%Master%' then 3
              WHEN e2.program like '%Bachelor%' then 2
              ELSE 1 END) num
      FROM education e2
      WHERE e2.deleted != 1
      GROUP BY e2.user_id
  ) ed ON u.user_id = ed.user_id 
  WHERE u.deleted != 1
  )
UNION ALL
  (
  SELECT
      'YEARS EXPERIENCE' demographic
      ,CASE 
          WHEN exp.total_years_experience >= 0 AND exp.total_years_experience < 8 THEN '0-7'
          WHEN exp.total_years_experience >= 8 AND exp.total_years_experience < 15 THEN '8-14'
          WHEN exp.total_years_experience >= 15 AND exp.total_years_experience < 25 THEN '15-25'      
          WHEN exp.total_years_experience >= 25 THEN '25+' 
          ELSE 'UNKNOWN' END category
  FROM user u2
  LEFT JOIN (  
      SELECT exp1.user_id, ROUND(SUM(DATEDIFF(COALESCE(end_date,CURDATE()), start_date)) / 365.25, 1) total_years_experience
      FROM experience exp1
      WHERE exp1.deleted != 1
      GROUP BY exp1.user_id
  ) exp ON u2.user_id = exp.user_id 
  WHERE u2.deleted != 1
) 
  
) x, (SELECT COUNT(*) denom FROM user WHERE deleted != 1) y

GROUP BY demographic, category
order by demographic, category



/* QUERY 3: BUSINESS QUESTION 3 */
/********************************/
/********************************/

SELECT
(select COUNT(*) total_users FROM user u WHERE u.deleted != 1) total_users
,(Select COUNT(*) new_users FROM user u WHERE u.deleted != 1 AND CASE WHEN u.creation_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH) THEN 1 ELSE 0 END = 1) new_users
,(SELECT SUM(CASE WHEN last_active >= DATE_SUB(CURDATE(), INTERVAL 4 MONTH) THEN 1 ELSE 0 END) active_users FROM (
SELECT x.user_id, MAX(last_updated) last_active FROM (
  Select user_id, MAX(modified_date) last_updated from user GROUP BY user_id
  UNION ALL
  Select sender_id user_id, MAX(COALESCE(sent_date, connection_date)) last_updated from connection GROUP BY user_id
  UNION ALL
  Select sender_id user_id, MAX(modified_date) last_updated from message GROUP BY user_id
  UNION ALL
  Select user_id, MAX(modified_date) last_updated from post GROUP BY user_id
  UNION ALL
  Select user_id, MAX(modified_date) last_updated from comment GROUP BY user_id
  UNION ALL
  Select user_id, MAX(modified_date) last_updated from reaction GROUP BY user_id
  UNION ALL
  Select user_id, MAX(modified_date) last_updated from skill GROUP BY user_id
  UNION ALL
  Select user_id, MAX(modified_date) last_updated from education GROUP BY user_id
  UNION ALL
  Select user_id, MAX(modified_date) last_updated from experience GROUP BY user_id
) x
LEFT JOIN user u on x.user_id = u.user_id
WHERE u.deleted != 1
GROUP BY x.user_id


/* QUERY 4: BUSINESS QUESTION 4 */
/********************************/
/********************************/

/* Report on the top school and top company with the most employment and education experiences respectively. */

Select 
	o.type
    ,o.name
    ,COUNT(*) total
    ,maxx.max_total 
from 
	organization o
    left join experience ex on o.organization_id = ex.organization_id
    left join education ed on o.organization_id = ed.organization_id
    LEFT JOIN (
      SELECT type, MAX(total) AS max_total
      FROM (
        Select 
            type
            ,name
            ,COUNT(*) total
        from 
            organization y
            left join experience ex on y.organization_id = ex.organization_id
            left join education ed on y.organization_id = ed.organization_id
       	GROUP BY type, name
		) z
      GROUP BY type
    ) maxx ON o.type = maxx.type
group by 
	o.type
    ,o.name
HAVING COUNT(*) = maxx.max_total
order by total desc








