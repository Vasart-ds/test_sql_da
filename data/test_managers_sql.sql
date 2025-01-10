WITH message_sorting AS (
	SELECT type,
		entity_id,
        	created_by,
        	created_at,
        	LEAD(created_at) OVER (PARTITION BY entity_id ORDER BY created_at) AS manager_answer_time,
        	LAG(type) OVER (PARTITION BY entity_id ORDER BY created_at) AS prev_type
	FROM test.chat_messages
),
filtered_msgs AS (
	SELECT entity_id,
           	created_by,
           	created_at,
           	manager_answer_time,
           CASE
           	WHEN (prev_type IS NULL AND LEAD(prev_type) OVER (PARTITION BY entity_id) = 'incoming_chat_message') THEN '0'
          	WHEN (prev_type IS NULL AND LEAD(prev_type) OVER (PARTITION BY entity_id) IS NULL) THEN 'non_answ'
          	WHEN LAG(prev_type) OVER (PARTITION BY entity_id) IS NULL THEN '1'
           ELSE prev_type
           END AS upd_type
 	FROM message_sorting
),
response_time AS (
	SELECT entity_id,
 		created_at,
 		manager_answer_time,
 		(CASE WHEN created_by = 0 THEN lead(created_by) over (partition by entity_id order by created_at) END) AS manager_id,
 		(CASE WHEN manager_answer_time IS NOT NULL AND created_at IS NOT NULL THEN 
                	GREATEST(to_timestamp(manager_answer_time)::time, '09:30:00') -
                	GREATEST(to_timestamp(created_at)::time, '00:00:00') ELSE NULL END) AS response_lag
	FROM filtered_msgs
	WHERE (upd_type = '0' OR upd_type = '1')
),
avg_response AS (
	SELECT rt.manager_id,
	   	m.name_mop,
	   	AVG(rt.response_lag::time) AS avg_response_time,
	   	r.rop_name
	FROM response_time rt
	JOIN test.managers m on rt.manager_id = m.mop_id
	JOIN test.rops r on r.rop_id = m.rop_id::int
	WHERE manager_id is not null and manager_id != 0
	GROUP BY rt.manager_id, m.name_mop, r.rop_name
)

SELECT manager_id,
	name_mop,
	rop_name,
	CASE 
	   WHEN EXTRACT(HOUR FROM avg_response_time::time) > 0 THEN 
		 	 EXTRACT(HOUR FROM avg_response_time::time) * 60 + extract(MINUTE FROM avg_response_time::time)
	   ELSE EXTRACT(MINUTE FROM avg_response_time::time)
	   END AS avg_response_minutes
FROM avg_response
ORDER BY avg_response_minutes;
