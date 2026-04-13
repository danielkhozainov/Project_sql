/* Проект «Разработка витрины и решение ad-hoc задач»
 * Цель проекта: подготовка витрины данных маркетплейса «ВсёТут»
 * и решение четырех ad hoc задач на её основе
 * 
 * Автор: Хожайнов Даниил Александрович
 * Дата: 19.01.2026 
*/



/* Часть 1. Разработка витрины данных
 * Напишите ниже запрос для создания витрины данных
*/
WITH
top_regions AS (
    SELECT
    	region
 	FROM (SELECT
          	region,
           	COUNT(DISTINCT order_id),
           	ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT order_id) DESC) AS rank
          FROM ds_ecom.orders
          JOIN ds_ecom.users USING (buyer_id)
            WHERE order_status IN ('Доставлено', 'Отменено')
          GROUP BY region
             ) AS ranked_regions
        WHERE rank <= 3
),	
sorting_users AS (
	SELECT 
		order_id,
         user_id,
            region,
            order_status,
            order_purchase_ts
	FROM ds_ecom.users
	JOIN ds_ecom.orders USING (buyer_id)
			WHERE region IN (SELECT region FROM top_regions)
			AND order_status IN ('Доставлено','Отменено')
),
order_reviews_new AS (
	SELECT 
		order_id,
		avg(CASE 
				WHEN review_score >5
					THEN review_score/10
				ELSE review_score 
			END) AS review_score
	FROM ds_ecom.order_reviews
	GROUP BY order_id
),
order_items_new AS (
	SELECT
		order_id,
		SUM(price + delivery_cost) AS total_cost
    FROM ds_ecom.order_items
   GROUP BY order_id
),
 order_payments_new AS
    (
        SELECT
            order_id,        
            MAX( CASE WHEN payment_type = 'денежный перевод' AND payment_sequential = 1
                 THEN 1 ELSE 0 END )   AS used_money_transfer,
            MAX( CASE WHEN payment_installments > 1 
            	THEN 1 ELSE 0 END )    AS used_installments,
            MAX( CASE WHEN payment_type = 'промокод'
            	THEN 1 ElSE 0 END )    AS used_promocode
        FROM ds_ecom.order_payments
        GROUP BY order_id
    ),
info_orders_count AS (
	SELECT 
		user_id,
		region,
		MIN(order_purchase_ts) 											AS first_order_ts,
		MAX(order_purchase_ts) 											AS last_order_ts,
		age(MAX(order_purchase_ts), MIN(order_purchase_ts))  			AS lifetime,
		count(distinct order_id) 										AS total_orders,				
		avg(review_score) 												AS avg_order_rating,
		count(DISTINCT CASE WHEN review_score IS NOT NULL
                THEN order_id END) 										AS num_orders_with_rating,
        count(DISTINCT CASE WHEN order_status = 'Отменено'
                THEN order_id END ) 									AS num_canceled_orders,
        SUM(CASE WHEN order_status = 'Доставлено'
        		THEN total_cost ELSE 0 END) 							AS total_order_costs,															
        COUNT(DISTINCT CASE WHEN used_installments = 1
                THEN order_id END )                      				AS num_installment_orders,
        COUNT(DISTINCT CASE WHEN used_promocode = 1
                THEN order_id END )                      				AS num_orders_with_promo,
        MAX(used_money_transfer)                       					AS used_money_transfer,
        MAX(used_installments)                        					AS used_installments,
        MAX(CASE WHEN order_status = 'Отменено' THEN 1 ELSE 0 END ) 	AS used_cancel
	FROM sorting_users
	LEFT JOIN order_reviews_new USING (order_id)
	JOIN order_items_new USING (order_id)
	JOIN order_payments_new USING (order_id)
	GROUP BY user_id, region
)
	SELECT 
		user_id,
		region, 
		first_order_ts,
		last_order_ts,
		lifetime,
		total_orders,
		coalesce(avg_order_rating, -1) AS avg_order_rating,
		num_orders_with_rating,
		num_canceled_orders,
		num_canceled_orders/total_orders::numeric AS canceled_orders_ratio,
		total_order_costs,
		CASE 
			WHEN total_orders>num_canceled_orders
			THEN total_order_costs/(total_orders-num_canceled_orders)
			ELSE 0
		END AS avg_order_cost,
		num_installment_orders,
		num_orders_with_promo,
		used_money_transfer,
		used_installments,
		used_cancel,
		count(*) over()
	FROM info_orders_count
	

/* Часть 2. Решение ad hoc задач
 * Для каждой задачи напишите отдельный запрос.
 * После каждой задачи оставьте краткий комментарий с выводами по полученным результатам.
*/

/* Задача 1. Сегментация пользователей 
 * Разделите пользователей на группы по количеству совершённых ими заказов.
 * Подсчитайте для каждой группы общее количество пользователей,
 * среднее количество заказов, среднюю стоимость заказа.
 * 
 * Выделите такие сегменты:
 * - 1 заказ — сегмент 1 заказ
 * - от 2 до 5 заказов — сегмент 2-5 заказов
 * - от 6 до 10 заказов — сегмент 6-10 заказов
 * - 11 и более заказов — сегмент 11 и более заказов
*/

-- Напишите ваш запрос тут
	SELECT 
	segment,
	count(user_id) AS count_users,
	round(avg(total_orders),2) AS avg_total_cost,
	round(avg(total_order_costs)/avg(total_orders-num_canceled_orders),2) AS avg_cost_order
FROM (SELECT
	*,
	CASE 
		WHEN total_orders = 1
			THEN '1 заказ'
		WHEN total_orders BETWEEN 1 AND 5
			THEN '2-5 заказов'
		WHEN total_orders BETWEEN 6 AND 10
			THEN '6-10 заказов'
		WHEN total_orders>10
			THEN '11 и более заказов'
	END AS segment
FROM ds_ecom.product_user_features) AS asd
GROUP BY segment
ORDER BY count_users DESC 

/* Напишите краткий комментарий с выводами по результатам задачи 1.
 * 
*/Большая часть пользователей (60тыс) 
сделали один заказ, средняя стоимость которого 3200, что является самой большой в сегменте.
	Можем заметить тенденцию к уменьшению 
среднего чека за один товар с увеличением количества заказов.



/* Задача 2. Ранжирование пользователей 
 * Отсортируйте пользователей, сделавших 3 заказа и более, по убыванию среднего чека покупки.  
 * Выведите 15 пользователей с самым большим средним чеком среди указанной группы.
*/

-- Напишите ваш запрос тут
SELECT 
	user_id,
	sum(total_orders),
	avg(avg_order_cost)
FROM ds_ecom.product_user_features 
	GROUP BY user_id
	HAVING sum(total_orders) >=3
	ORDER BY avg(avg_order_cost) DESC
LIMIT 15
(Так как пользователь мог сделать заказ из нескольких регионов, 
то результаты подсчитаны с помощью группировки по каждому пользователю, независимо от региона)
/*
 *
 
*/Самый большой средний чек наблюдается у пользователей совершивших три заказа. Если же рассматривать 
эти данные в разрезе с регионами, то можно увидеть, что большая часть бользователй из Москвы:
Запрос без агрегации: 

SELECT
    user_id,
    region,
    total_orders,
    avg_order_cost
FROM ds_ecom.product_user_features
WHERE total_orders >= 3
ORDER BY avg_order_cost DESC
LIMIT 15;



/* Задача 3. Статистика по регионам. 
 * Для каждого региона подсчитайте:
 * - общее число клиентов и заказов;
 * - среднюю стоимость одного заказа;
 * - долю заказов, которые были куплены в рассрочку;
 * - долю заказов, которые были куплены с использованием промокодов;
 * - долю пользователей, совершивших отмену заказа хотя бы один раз.
*/

-- Напишите ваш запрос тут
SELECT 
	region,
	count(user_id) AS общее_число_клиентов,
	sum(total_orders) AS общее_число_заказов,
	avg(avg_order_cost) AS среднюю_стоимость_одного_заказа,
	sum(num_installment_orders)::numeric / SUM(total_orders) AS долю_заказов_купленных_в_рассрочку, 
	sum(num_orders_with_promo)::numeric / SUM(total_orders) AS долю_заказов_купленных_с_использованием_промокодов,
	AVG(used_cancel) AS долю_пользователей_c_отменой_заказа
FROM ds_ecom.product_user_features
GROUP BY region 

*/Большая часть пользователей находятся в Москве, 4-1-1 по отношению к другим регионам,
что также коррелирует с количеством совершенных заказов 4-1-1, несмотря на это,
остальные показатели примерно равны



/* Задача 4. Активность пользователей по первому месяцу заказа в 2023 году
 * Разбейте пользователей на группы в зависимости от того, в какой месяц 2023 года они совершили первый заказ.
 * Для каждой группы посчитайте:
 * - общее количество клиентов, число заказов и среднюю стоимость одного заказа;
 * - средний рейтинг заказа;
 * - долю пользователей, использующих денежные переводы при оплате;
 * - среднюю продолжительность активности пользователя.
*/
SELECT 
	date_trunc('month', first_order_ts) AS MONTH,
	count(user_id),                                                             
    sum(total_orders),
    avg(avg_order_cost),
    avg(avg_order_rating),
    count(CASE 
	    	WHEN used_money_transfer = 1 
	    		THEN 1 
	    	END )::numeric / count(*),
	 avg(lifetime)
FROM ds_ecom.product_user_features
WHERE EXTRACT(YEAR FROM first_order_ts) = 2023
GROUP BY date_trunc('month', first_order_ts)
-- Напишите ваш запрос тут
Количество пользователей и заказов линейно возрастают в течении 2023 года
и достигает пика в ноябре, при это средняя активность клинта имеет обратную зависимость,
она линейно падает в течении года и достигает минимума в декабре. 
При этом остальные показатели демонстрируют относительную стабильность.
.
 * 