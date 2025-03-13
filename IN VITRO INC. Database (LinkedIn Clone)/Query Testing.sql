/* 1. Display data for user profile header. Requirements: To retrieve data for all users that is displayed in their profile header for the IN VITRO INC. social media platform. This includes their full name, image location of their profile image, user's brief description, the name and program of their last and most recent education attended, their job title and employer for their most recent work experience from which the user is currently employed, their total years of work experience, and their most recent acquired skill. */

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
    	SELECT MAX(ex2.experience_id) experience_id -- Flatten by id in case of duplicate active employments
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
    
    ;


/* 2. Reactions to posts between users who attended/worked at the same organization. Count all non-deleted instances of users making a reaction to another user's post that has been employed by the same company or that attended the same school. Group the output by the full name of the user making the post, the full name of the user giving the reaction, and the organization (school or company) that they attended. */

SELECT *, COUNT(*) total_instances FROM (
SELECT CONCAT(u.first_name, ' ', u.last_name) AS name_of_poster, concat(u2.first_name, ' ', u2.last_name) name_of_reactioner, COALESCE(o1.name, o2.name) AS organization_name
FROM user u
    JOIN reaction r ON u.user_id = r.user_id /* REACTIONER */
    JOIN post p ON r.post_id = p.post_id
    JOIN user u2 ON p.user_id = u2.user_id AND u2.deleted = 0 /* POSTER */ -- omit any user deleted entry
    LEFT JOIN experience e ON u2.user_id = e.user_id AND e.deleted = 0 -- omit any user deleted entry
    LEFT JOIN education edu ON u2.user_id = edu.user_id AND edu.deleted = 0-- omit any user deleted entry
    LEFT JOIN organization o1 ON e.organization_id = o1.organization_id and o1.deleted = 0 -- omit any user deleted entry
  	LEFT JOIN organization o2 ON edu.organization_id = o2.organization_id and o2.deleted = 0 -- omit any user deleted entry
WHERE
   (e.organization_id IN (SELECT organization_id FROM experience WHERE user_id = u.user_id AND deleted = 0)  /* Correlated subquery 1 to filter users who worked for the same company */
    OR edu.organization_id IN (SELECT organization_id FROM education WHERE user_id = u.user_id AND deleted = 0))  /* Correlated subquery 2 to filter users who attended the same school */
    AND u.user_id != u2.user_id
    AND u.deleted = 0 -- omit any user deleted entry
    AND r.deleted = 0 -- omit any user deleted entry
    AND p.deleted = 0 -- omit any user deleted entry
) AS subquery
GROUP BY name_of_poster, name_of_reactioner, organization_name

;


/* 3. Summary business intelligence report on all user demographics, including their sex, age group, their highest level of education, and years of work experience by categories. */

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

;


/* 4. Business intelligence query to report on 1) total users who have not deactivated their accounts, 2) new users in the past 6 months, and 3) active users in the past 4 months. For the latter, include all activity such as posts, messages, connections, comments, reactions, skill entries, and education and experience entries, even those that are deleted */

SELECT
(select COUNT(*) total_users FROM user u WHERE u.deleted != 1) total_users
,(Select COUNT(*) new_users FROM user u WHERE u.deleted != 1 AND (CASE WHEN u.creation_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH) THEN 1 ELSE 0 END) = 1) new_users
,(SELECT SUM(CASE WHEN last_active >= DATE_SUB(CURDATE(), INTERVAL 4 MONTH) THEN 1 ELSE 0 END) 
    FROM (  
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
	) z
 ) active_users 

;


/* 5. Report on the top school and top company with the most employment and education experiences respectively. Include ties if applicable. In addition to organization type and name, report on the total experiences. */

SELECT type, name, total FROM (
Select 
	o.type
    ,o.name
    ,COUNT(*) total
    ,max_total
from 
	organization o
    left join experience ex on o.organization_id = ex.organization_id
    left join education ed on o.organization_id = ed.organization_id
    LEFT JOIN (
      SELECT type, MAX(total) AS max_total
      FROM (
        Select 
            type
            ,y.organization_id
            ,COUNT(*) total
        from 
            organization y
            left join experience ex on y.organization_id = ex.organization_id
            left join education ed on y.organization_id = ed.organization_id
       	GROUP BY type, y.organization_id
		) z
      GROUP BY type
    ) maxx ON o.type = maxx.type
group by 
	o.type
    ,o.name
order by total desc
) x
WHERE total = max_total

;


/* 6. List to top 10 users who have made more than 5 non-deleted posts and who have any experience or education. Report them by user id, full name, and total post count. Limit your results to the top 10 users with the most posts.  */

SELECT u.user_id, CONCAT(u.first_name, ' ', u.last_name) full_name, post_count
FROM user u
left join (SELECT user_id, COUNT(*) post_count FROM post WHERE deleted = 0 GROUP BY user_id) po on u.user_id = po.user_id
WHERE u.user_id IN (
    SELECT p.user_id
    FROM post p
    WHERE p.deleted = 0
    GROUP BY p.user_id
    HAVING COUNT(*) > 5
)
AND (
    u.user_id IN (
        SELECT e.user_id
        FROM experience e
        WHERE e.deleted = 0
    )
    OR
    u.user_id IN (
        SELECT ed.user_id
        FROM education ed
        WHERE ed.deleted = 0
    )
)
ORDER BY post_count DESC
LIMIT 10

;


/* 7. List all distinct users who made comments on the posts of their connections. List the full name and id of the users who made the post and the full name and id of users who made the comments. Do not include deleted records. */

SELECT DISTINCT CONCAT(u_post.first_name, ' ', u_post.last_name) AS post_author_name
				,u_post.user_id AS post_author_id
                ,CONCAT(u_comment.first_name, ' ', u_comment.last_name) AS comment_author_name
                ,u_comment.user_id AS comment_author_id
FROM (select receiver_id a, sender_id b FROM connection where deleted = 0 and connection_date is not null
UNION ALL select sender_id b, receiver_id a FROM connection where deleted = 0 and connection_date is not null) c /* all connections both ways */
JOIN post p ON c.b = p.user_id AND p.deleted = 0
JOIN comment cm ON p.post_id = cm.post_id AND cm.deleted = 0
JOIN user u_post ON p.user_id = u_post.user_id AND u_post.deleted = 0
JOIN user u_comment ON cm.user_id = u_comment.user_id AND u_comment.deleted = 0
WHERE cm.user_id = c.a

;


/* 8. List the top 10 trending non-deleted posts with the most non-deleted reactions and comments from last year. List the poster id, their full name, the text included in the post, and the total interactions they received from their post. */

SELECT u.user_id, CONCAT(u.first_name, ' ', u.last_name) full_name, post_id, post post_description
,(coalesce(total_reactions, 0) + coalesce(total_comments, 0)) AS total_interactions
FROM (
  SELECT x.post_id, x.user_id, x.post, x.total_reactions, COUNT(*) total_comments FROM (
    SELECT p.post_id, p.user_id, p.post, count(*) total_reactions  
    FROM post p
    LEFT JOIN reaction r ON p.post_id = r.post_id AND r.deleted = 0
    WHERE p.deleted = 0 AND YEAR(p.post_date) = (YEAR(CURDATE())-1)
    GROUP BY p.post_id, p.user_id, p.post
    ) x
   LEFT JOIN comment c ON x.post_id = c.post_id AND c.deleted = 0
  GROUP BY x.post_id, x.user_id, x.post, x.total_reactions 
) z
left join user u on z.user_id = u.user_id
ORDER BY total_interactions DESC
LIMIT 10

; 


/* 9. List the top 10 users with accounts who have deleted the most comments, posts, or reactions. Specify their user id, full name, account creation dates, as well as the sum of the total posts, comments, and reactions deleted. Be sure to exclude users with deactivated accounts. */

SELECT u.user_id, CONCAT(u.first_name, ' ' ,u.last_name), DATE(u.creation_date) creation_date
,(COALESCE(rt,0) + COALESCE(ct,0) + COALESCE(pt,0)) total_deleted_activities
FROM user u
LEFT JOIN (
	SELECT r.user_id, COUNT(*) rt
    FROM reaction r
    WHERE r.deleted = 1
  	GROUP BY r.user_id
) r1 on u.user_id = r1.user_id
LEFT JOIN (
	SELECT c.user_id, COUNT(*) ct
    FROM comment c
    WHERE c.deleted = 1
  	GROUP BY c.user_id
) c1 on u.user_id = c1.user_id
LEFT JOIN (
	SELECT p.user_id, COUNT(*) pt
    FROM post p
    WHERE p.deleted = 1
  	GROUP BY p.user_id
) p1 on u.user_id = p1.user_id
WHERE u.deleted = 0
ORDER BY total_deleted_activities DESC
LIMIT 10

;


/* 10. Return the 5 most common skills among all users with non-deactivated accounts that have an educational background in "Analytics" , "Data" , "Intelligence", or "Technology" as determined by their education programs. Include the skill, and the frequency of that skill in the results. Omit any user-deleted education and skill records. */

SELECT skill.skill, COUNT(*) AS skill_count
FROM skill
JOIN user ON skill.user_id = user.user_id
JOIN education ON user.user_id = education.user_id
WHERE education.program LIKE '%Analytics%'
   OR education.program LIKE '%Data%'
   OR education.program LIKE '%Intelligence%'
   OR education.program LIKE '%Technology%'
   AND skill.deleted = 0
   AND user.deleted = 0
   AND education.deleted = 0
GROUP BY skill.skill
ORDER BY skill_count DESC
LIMIT 5

;


/* 11. Return the 10 most active users after in the last month of the previous year based on their total comments, posts, messages and reactions. Be sure to include their user id, full name, and the sum of their total activities as defined above. Be sure to include all their activities, including deleted ones, but do not include deactivated users. */

SELECT Activity.user_id, CONCAT(Activity.first_name,' ',Activity.last_name) full_name, 
(COALESCE(Activity.comment_count,0)+COALESCE(Activity.post_count,0)+COALESCE(Activity.message_count,0)+COALESCE(Activity.reaction_count,0)) AS total_activity
FROM (
SELECT
  user.user_id,
  user.first_name,
  user.last_name,
  COUNT(DISTINCT comment.comment_id) AS comment_count,
  COUNT(DISTINCT post.post_id) AS post_count,
  COUNT(DISTINCT message.message_id) AS message_count,
  COUNT(DISTINCT reaction.reaction_id) AS reaction_count
FROM
  user
  LEFT JOIN comment ON user.user_id = comment.user_id AND comment.comment_date between DATE(CONCAT(YEAR(CURDATE())-1,'-12-01')) AND DATE(CONCAT(YEAR(CURDATE())-1,'-12-31'))
  LEFT JOIN post ON user.user_id = post.user_id AND post.post_date between DATE(CONCAT(YEAR(CURDATE())-1,'-12-01')) AND DATE(CONCAT(YEAR(CURDATE())-1,'-12-31'))
  LEFT JOIN message ON user.user_id = message.sender_id AND message.sent_date between DATE(CONCAT(YEAR(CURDATE())-1,'-12-01')) AND DATE(CONCAT(YEAR(CURDATE())-1,'-12-31'))
  LEFT JOIN reaction ON user.user_id = reaction.user_id AND reaction.reaction_date between DATE(CONCAT(YEAR(CURDATE())-1,'-12-01')) AND DATE(CONCAT(YEAR(CURDATE())-1,'-12-31'))
WHERE user.deleted = 0
GROUP BY
  user.user_id,
  user.first_name,
  user.last_name
) AS Activity
ORDER BY total_activity DESC
LIMIT 10

;


/* 12. Retrieve the top 5 most users who have sent the most direct messages on the social media platform. Omit deactivated accounts but include any deleted messages. Display the results by user id, full name, email address, as well as their total number of sent messages */

SELECT 
    u.user_id,
    CONCAT(u.first_name,' ', u.last_name) full_name,
    email,
    count(*) as total_messages
FROM
    user u
JOIN
    message m ON u.user_id = m.sender_id
WHERE u.deleted = 0
GROUP BY
    u.user_id
ORDER BY 
    total_messages DESC 
LIMIT 5

;


/* 13. For user 31 who sent the most messages through the social media platform, find all the users they SENT direct messages to and return the latest/current employer and their respective job titles and descriptions for these users. You should also return their user id their full name and the number of years of experience they have in that specific role to date. Do this through creating views entered in the Schema SQL part of DB Fiddle as the views are part of the DDL (VIEWS ALSO INCLUDED HERE COMMENTED OUT FOR REFERENCE). Include all deleted or deactivated accounts/records. Order results by years in position descending. */

/*
CREATE VIEW receiver AS
SELECT 
    message.receiver_id, 
    COUNT(*) as messages_received
    FROM message
    JOIN user ON message.receiver_id = user.user_id
    WHERE message.sender_id = 31
    GROUP BY message.receiver_id
    ORDER BY messages_received DESC
    ; 
    
CREATE VIEW receiver_exp AS 
  SELECT x.receiver_id, MAX(e.experience_id) experience_id FROM ( -- assumes latest date then latest entry is most recent
  SELECT receiver.receiver_id, MAX(COALESCE(experience.end_Date, CURDATE())) AS max_end_date
  FROM experience
  JOIN receiver ON experience.user_id = receiver.receiver_id
  GROUP BY receiver.receiver_id 
  ) x
  LEFT JOIN experience e on e.user_id = x.receiver_id and COALESCE(e.end_date, CURDATE()) = x.max_end_date 
  GROUP BY x.receiver_id
;
*/

SELECT r.receiver_id, CONCAT(u.first_name, ' ', u.last_name) full_name, o.name company_name, e.job_title, e.job_description, ROUND(DATEDIFF(COALESCE(e.end_date,CURDATE()), e.start_date) / 365.25, 1) years_in_position
FROM receiver r
LEFT JOIN user u on u.user_id = r.receiver_id
LEFT JOIN experience e on r.receiver_id = e.user_id and e.experience_id in (SELECT experience_id from receiver_exp)
LEFT JOIN organization o on e.organization_id = o.organization_id
ORDER BY years_in_position DESC

;


/* 14. List all users who have been an Analyst or Data Scientist for at least 1 year and have an Analysis or Analytics related skill in their profile. List the users by their user id, full name, and combined years of experience in the any analytics related role. Exclude all deactivated accounts and user-deleted records. Order by years of experience descending. */

SELECT
    u.user_id,
    CONCAT(u.first_name, ' ', u.last_name) full_name,
    ROUND(SUM(DATEDIFF(COALESCE(end_date,CURDATE()), start_date)) / 365.25, 1) years_analytics_experience
FROM
    user u
    JOIN experience e ON u.user_id = e.user_id and e.deleted = 0
    JOIN skill s ON u.user_id = s.user_id and s.deleted = 0
    JOIN organization o ON e.organization_id = o.organization_id and o.deleted = 0
WHERE
   (e.job_title LIKE '%Analyst%' OR e.job_title LIKE '%Data Scientist%')
    AND s.skill LIKE '%Analy%'
    AND ROUND(DATEDIFF(COALESCE(e.end_Date, CURDATE()), e.start_Date) / 365.25, 1) >= 1
    AND u.deleted = 0
GROUP BY
	user_id, full_name
ORDER BY years_analytics_experience DESC
    
;


/* 15. Retrieve the top 5 most popular trending users who have the most connections on the social media platform. Omit deactivated accounts and deleted records and display the results by user id, their profile image url, their profile description, as well as their total number of connections */

SELECT 
    u.user_id,
    CONCAT(u.first_name,' ', u.last_name) full_name,
    u.image_url profile_image_url,
    description profile_description,
    COUNT(*) total_connections
FROM 
    user u
JOIN 
    (select receiver_id a, connection_date FROM connection where deleted = 0 
	UNION ALL select sender_id a, connection_date FROM connection where deleted = 0) c ON u.user_id = c.a /* all connections both ways */
WHERE c. connection_date IS NOT NULL and u.deleted = 0
GROUP BY 
    u.user_id, u.first_name, u.last_name
ORDER BY 
    total_connections DESC
LIMIT 5

;


/* 16. A recruiter has asked the company for a list of business savvy candidates who also have a business related Masters Degree to back up their skills. They should have a four point GPA greater 3.37. You are an employee who is not sure if you should be giving away personal information, but you do it anyways as you are willing to let things slide today. The recruiter wants their full name, email address, a link to their profile image, their GPA and their verified masters degree and respective insitution. Today, you also decide to include deleted records in case in helps the recruiter, hoping that you don't get in trouble. Do this through creating a view entered in the Schema SQL part of DB Fiddle as the views are part of the DDL (VIEWS ALSO INCLUDED HERE COMMENTED OUT FOR REFERENCE)*/ 

/*
SELECT u.user_id, CONCAT(u.first_name, ' ', u.last_name) full_name, email, u.image_url profile_image_url, e.gpa, o.name, e.program, e.education_id, COALESCE(e.end_date,CURDATE()) enddate
FROM user u
left join education e ON u.user_id = e.user_id
left join organization o on e.organization_id = o.organization_id
left join skill s on u.user_id = s.user_id and s.skill like '%business%'
WHERE e.program LIKE '%Master%' AND e.program LIKE '%business%' AND e.gpa > 3.37
GROUP BY u.user_id, full_name, email, profile_image_url, e.gpa, o.name, e.program, e.education_id, enddate
*/

select user_id, full_name, email, profile_image_url, gpa, name university_name, program from edu
WHERE edu.education_id IN ( /* MOST RECENT EDUCATION */
        SELECT education_id FROM ( SELECT e2.user_id, MAX(e2.education_id) education_id -- Flatten by id in case of duplicate overlapping educations
        FROM edu e2 /* SUBQUERY BELOW TO IDENTIFY MOST RECENT EDUCATION BASED ON DATE */
        JOIN (SELECT user_id, MAX(enddate) AS max_end_date FROM edu e1 GROUP BY user_id) AS max_dates 
        ON e2.user_id = max_dates.user_id AND e2.enddate = max_dates.max_end_date
        GROUP BY e2.user_id) x )

;


/*************************************************************************************************/
/*************************************************************************************************/
/* THE FOLLOWING QUERIES TEST MORE OF THE TRANSACTIONAL/OPERATIONAL REQUIREMENTS OF THE DATABASE */
/*************************************************************************************************/
/*************************************************************************************************/


/* 17. List all users have education at when searching by a school to ensure the database can meet operational requirements. Use McGill University as an example in your search. Display the first and last name of the user. */

SELECT CONCAT(u.first_name, ' ', u.last_name) full_name
FROM user u
JOIN education e ON u.user_id = e.user_id
JOIN organization o ON e.organization_id = o.organization_id
WHERE o.name = 'McGill University'

;


/* 18. Report on all direct messages that have not yet been seen by a recipient. Display the recipients id and full name of the user as well as the senders name and the message. Test this for user id 4. */

SELECT m.receiver_id, CONCAT(ur.first_name, ' ', ur.last_name) receiver, m.message, CONCAT(us.first_name, ' ', us.last_name) sender
FROM message m
LEFT JOIN user ur on m.receiver_id = ur.user_id
LEFT JOIN user us on m.sender_id = us.user_id
WHERE seen = 0 AND ur.user_id = 4

;


/* 19. Report on all connection requests that have not yet been accepted by a recipient. Display the recipients id and full name of the user as well as the senders name. Test this for user id 20. */

SELECT c.receiver_id, CONCAT(ur.first_name, ' ', ur.last_name) receiver, CONCAT(us.first_name, ' ', us.last_name) sender
FROM connection c
LEFT JOIN user ur on c.receiver_id = ur.user_id
LEFT JOIN user us on c.sender_id = us.user_id
WHERE connection_date IS NULL AND ur.user_id = 20

;


/* 20. Report on all unread comments on posts that have not yet been seen by the initial poster. Display the posters user id and full name of the user as well as the commenter's name and the actuall comment. Test this for user id 33. */

SELECT p.user_id, CONCAT(up.first_name, ' ', up.last_name) poster, c.comment, CONCAT(uc.first_name, ' ', uc.last_name) commenter
FROM comment c
LEFT JOIN user uc on c.user_id = uc.user_id
LEFT JOIN post p on c.post_id = p.post_id
LEFT JOIN user up on p.user_id = up.user_id
WHERE c.seen = 0 AND p.user_id = 33

;


/* 21. To perform searches on comments of a post. Test this for post_id 1. */

SELECT post.post_id, post.user_id, post.post_date, comment.comment_id, comment.comment
FROM post
RIGHT JOIN comment ON post.post_id = comment.post_id
WHERE post.post_id = 1 

;


/* 22. To perform searches on organizations. Test this searching for an organization name that containts "solutions" in it limiting to only 10 results. */
SELECT 
   	organization_id, name, image_url, phone, type, street_number, street_name, city, postal_code, province, country, creation_date, modified_date, deleted
FROM 
    organization
WHERE 
    name like '%Solutions%' LIMIT 10

;


/* 23. To perform searches for skills, suggesting most common skills first. Test this for skills that contain "Strategy" limiting to only 10 results. */
SELECT skill_type FROM (
SELECT 
    skill AS skill_type,
    COUNT(*) AS skill_count
FROM 
    skill s
WHERE skill like '%Strategy%' 
GROUP BY 
    skill
) X
ORDER BY 
    skill_count DESC
LIMIT 10 

 ;


/* 24. To perform searches on a user by their full name displaying their full name as well as the url for their profile image. Test this by searching for Emily. */

Select CONCAT(u.first_name, ' ', u.last_name) full_name, u.image_url
From user u
WHERE CONCAT(u.first_name, ' ', u.last_name) like 'Emily%'
AND deleted = 0

;


/* 25. To perform searches on a user’s reactions. */

SELECT r.reaction_id, r.user_id, r.post_id, r.reaction, r.reaction_date
FROM reaction r
JOIN user u ON r.user_id = u.user_id
WHERE r.user_id = 49 AND r.deleted = 0 AND u.deleted = 0 and post_id is not null

;


/* 26. To perform searches on a user’s experience and respective skills. Test this with user 49. */

SELECT 
    e.job_title,
    e.job_description,
    o.name AS organization_name,
    e.start_date,
    e.end_date,
    s.skill
FROM 
    experience e
LEFT JOIN 
    organization o ON e.organization_id = o.organization_id
LEFT JOIN 
    skill s ON e.user_id = s.user_id
WHERE 
    e.user_id = 49
    AND e.job_description IS NOT NULL
    AND e.deleted = 0
    AND s.deleted = 0
    
;


/* 27. To perform searches by either a company or school with the most attended schools or greatest employers auto-populating first. Limit to five results for each. */

(
    SELECT o.organization_id, o.name, COUNT(*) AS count, 'Education' AS type
    FROM education ed
    JOIN organization o ON ed.organization_id = o.organization_id
    WHERE ed.deleted = 0 AND o.type = 'School' AND o.deleted = 0
    GROUP BY o.organization_id, o.name
    ORDER BY count DESC
    LIMIT 5
)
UNION ALL
(
    SELECT o.organization_id, o.name, COUNT(*) AS count, 'Experience' AS type
    FROM experience e
    JOIN organization o ON e.organization_id = o.organization_id
    WHERE e.deleted = 0 AND o.type = 'Company' AND o.deleted = 0
    GROUP BY o.organization_id, o.name
    ORDER BY count DESC
    LIMIT 5
)

;









