-- ============================================================
-- OceanBase 租户核心监控 (5项指标, 全部3节点汇总)
--
-- 使用方法:
--   mysql -h<IP> -P2883 -u<user> -p<password> -D oceanbase -A < ob_monitor.sql
--   首次使用请修改 @tid 为你的租户ID
-- ============================================================

SET @tid = 1034;

-- 快照1
SET @s1_sel = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql select count');
SET @s1_ins = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql insert count');
SET @s1_rep = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql replace count');
SET @s1_upd = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql update count');
SET @s1_del = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql delete count');
SET @s1_oth = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql other count');
SET @s1_tcm = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='trans commit count');
SET @s1_ird = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='io read bytes');
SET @s1_iwr = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='io write bytes');

DO SLEEP(5);

-- 快照2
SET @s2_sel = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql select count');
SET @s2_ins = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql insert count');
SET @s2_rep = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql replace count');
SET @s2_upd = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql update count');
SET @s2_del = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql delete count');
SET @s2_oth = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='sql other count');
SET @s2_tcm = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='trans commit count');
SET @s2_ird = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='io read bytes');
SET @s2_iwr = (SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='io write bytes');

-- 计算速率
SET @qps = ROUND(((@s2_sel-@s1_sel)+(@s2_ins-@s1_ins)+(@s2_rep-@s1_rep)+(@s2_upd-@s1_upd)+(@s2_del-@s1_del)+(@s2_oth-@s1_oth))/5, 1);
SET @tps = ROUND((@s2_tcm-@s1_tcm)/5, 1);
SET @r_mb = ROUND((@s2_ird-@s1_ird)/5/1024/1024, 2);
SET @w_mb = ROUND((@s2_iwr-@s1_iwr)/5/1024/1024, 2);
SET @mem_used = ROUND((SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='memory usage')/1024/1024/1024, 2);
SET @mem_max = ROUND((SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='max memory size')/1024/1024/1024, 2);
SET @mem_pct = ROUND(@mem_used*100.0/NULLIF(@mem_max,0), 1);
SET @ms_used = ROUND((SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='total memstore used')/1024/1024/1024, 2);
SET @ms_max = ROUND((SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='memstore limit')/1024/1024/1024, 2);
SET @ms_pct = ROUND(@ms_used*100.0/NULLIF(@ms_max,0), 1);
SET @cpu_used = ROUND((SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='cpu usage')/100, 2);
SET @cpu_max = ROUND((SELECT SUM(value) FROM oceanbase.gv$sysstat WHERE con_id=@tid AND name='min cpus')/100, 2);
SET @cpu_pct = ROUND(@cpu_used*100.0/NULLIF(@cpu_max,0), 1);

-- 输出 (单条UNION ALL, RPAD对齐到22显示宽度)
SELECT RPAD('指标', 20, ' ') AS '', '当前值' AS '' UNION ALL
SELECT RPAD('QPS', 22, ' '), @qps UNION ALL
SELECT RPAD('TPS', 22, ' '), @tps UNION ALL
SELECT RPAD('IO读(MB/s)', 21, ' '), @r_mb UNION ALL
SELECT RPAD('IO写(MB/s)', 21, ' '), @w_mb UNION ALL
SELECT RPAD('已用内存(GB)', 18, ' '), @mem_used UNION ALL
SELECT RPAD('内存上限(GB)', 18, ' '), @mem_max UNION ALL
SELECT RPAD('内存使用率(%)', 17, ' '), @mem_pct UNION ALL
SELECT RPAD('MemStore(GB)', 22, ' '), @ms_used UNION ALL
SELECT RPAD('MemStore上限(GB)', 20, ' '), @ms_max UNION ALL
SELECT RPAD('MemStore使用率(%)', 19, ' '), @ms_pct UNION ALL
SELECT RPAD('CPU使用(核)', 19, ' '), @cpu_used UNION ALL
SELECT RPAD('CPU配额(核)', 19, ' '), @cpu_max UNION ALL
SELECT RPAD('CPU使用率(%)', 19, ' '), @cpu_pct;





SELECT t1.tenant_id,
       t1.database_name,
       t3.object_id AS database_id,
       SUM(t2.occupy_size)/1024/1024 AS data_size,
       SUM(t2.required_size)/1024/1024 AS required_size
  FROM (SELECT tenant_id, database_name, tablet_id
          FROM oceanbase.cdb_ob_table_locations
         GROUP BY tenant_id, database_name, tablet_id) t1
  LEFT JOIN (SELECT tenant_id,
                    tablet_id,
                    svr_ip,
                    svr_port,
                    occupy_size,
                    required_size
               FROM oceanbase.__all_virtual_tablet_pointer_status) t2
    ON t1.tenant_id = t2.tenant_id
   AND t1.tablet_id = t2.tablet_id
  LEFT JOIN (SELECT con_id, object_name, object_id
               FROM oceanbase.CDB_OBJECTS
              WHERE object_type = 'DATABASE') t3
    ON t1.tenant_id = t3.con_id
   AND t1.database_name = t3.object_name
  WHERE t1.tenant_id = 1034
 GROUP BY t1.tenant_id, t1.database_name
 ORDER BY 4 DESC;
