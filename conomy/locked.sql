SHOW FULL PROCESSLIST;

SELECT CONCAT('KILL ', id, ';') AS kill_cmd,
       id,
       time   AS running_seconds,
       state,
       info   AS query
FROM information_schema.processlist
WHERE user = 'brian'
ORDER BY time DESC;

