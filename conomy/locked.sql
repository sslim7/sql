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

KILL 3124940;
KILL 3127049;
KILL 3127050;
KILL 3127051;
KILL 3126510;
KILL 3126807;
KILL 3127210;
KILL 3126967;
KILL 3126399;
KILL 3127013;
KILL 3126805;
KILL 3126647;
KILL 3127198;
KILL 3126400;
KILL 3127077;
KILL 3126512;
KILL 3127012;
KILL 3126029;
KILL 3126009;
KILL 3126513;
KILL 3126483;
KILL 3126396;
KILL 3127200;
KILL 3126548;
KILL 3126581;
