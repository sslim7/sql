SHOW FULL PROCESSLIST;

SELECT CONCAT('KILL ', id, ';') AS kill_cmd,
       id,
       time   AS running_seconds,
       state,
       info   AS query
FROM information_schema.processlist
# WHERE user = 'brian'

ORDER BY time DESC;

SELECT CONCAT('KILL ', id, ';') AS kill_cmd,
       id,
       user,
       time AS running_seconds
FROM information_schema.processlist
WHERE command = 'Sleep'
  AND user = 'brian'          -- 특정 유저만
  -- AND time > 3600             -- n초 이상 슬립만
ORDER BY time DESC;

KILL 3370452;