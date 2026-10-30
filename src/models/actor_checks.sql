-- Payment ownership supplies an explicit activity exposure PROXY, not proof of
-- discount authority. Positive applications are attributed to their own actor.
WITH owners AS (
 SELECT location_id,business_date,check_id,min_by(employee_id,payment_ordinal) AS payment_owner_id
 FROM {payments} WHERE payment_type <> 'GC Sold' GROUP BY ALL
),
positive AS (
 SELECT location_id,business_date,check_id,nullif(discount_employee_id,0) AS employee_id,
   count(*) AS positive_applications,
   sum(CAST(amount AS DECIMAL(38,6))) AS actor_positive_amount
 FROM {events} WHERE amount>0 AND NOT isnan(amount) AND abs(amount)<>CAST('Infinity' AS DOUBLE)
 GROUP BY ALL
),
check_actors AS (
 SELECT location_id,business_date,check_id,count_if(employee_id IS NOT NULL) AS known_actors,
   count_if(employee_id IS NULL)>0 AS has_unknown_actor
 FROM positive GROUP BY ALL
),
keys AS (
 SELECT location_id,business_date,check_id,payment_owner_id AS employee_id FROM owners
 WHERE payment_owner_id IS NOT NULL AND payment_owner_id<>0
 UNION
 SELECT location_id,business_date,check_id,employee_id FROM positive
)
SELECT k.*, o.payment_owner_id,
 date_sub(k.business_date,pmod(dayofweek(k.business_date)-5,7)) AS week_start,
 coalesce(p.positive_applications,0L) AS positive_applications,
 coalesce(p.actor_positive_amount,CAST(0 AS DECIMAL(38,6))) AS actor_positive_amount,
 coalesce(k.employee_id=o.payment_owner_id,false) AS is_payment_owner,
 coalesce(a.known_actors,0)>1 AS multi_actor_check,
 coalesce(a.has_unknown_actor,false) AS has_unknown_actor,
 f.gross_complete,f.discount_complete,f.gross_sales,
 f.gross_complete AND f.discount_complete AND f.gross_sales>0 AS amount_eligible,
 f.has_positive_discount AS check_has_positive_discount,
 f.gross_sales>0 AND f.recorded_discount_amount>=f.gross_sales AS is_full_comp
FROM keys k
JOIN {facts} f USING(location_id,business_date,check_id)
LEFT JOIN owners o USING(location_id,business_date,check_id)
LEFT JOIN positive p ON k.location_id=p.location_id AND k.business_date=p.business_date
 AND k.check_id=p.check_id AND k.employee_id<=>p.employee_id
LEFT JOIN check_actors a ON k.location_id=a.location_id AND k.business_date=a.business_date AND k.check_id=a.check_id
